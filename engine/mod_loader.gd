extends Node
## Carga mods externos desde multiples raices, para que funcione tanto el
## scoped storage de Android (donde la app escribe sin permisos) como el
## storage compartido (donde el usuario pone mods con un gestor de
## archivos).
##
## Raices escaneadas, en orden de prioridad:
##   user://mods
##     = /storage/emulated/0/Android/data/<pkg>/files/mods
##     La app puede leer y escribir siempre, sin permisos. Es donde la
##     app misma instala mods descargados.
##   /storage/emulated/0/RubiconEngine/mods
##     Storage compartido, sin punto inicial (Android 11+ bloquea
##     FileAccess sobre archivos dentro de carpetas ocultas).
##     Requiere MANAGE_EXTERNAL_STORAGE, que el engine pide al arrancar.
##   /storage/emulated/0/.RubiconEngine/mods
##     Ruta historica con punto, por compatibilidad. En la mayoria de
##     dispositivos Android 11+ falla por scoped storage sobre carpetas
##     ocultas, pero se intenta igual.
##
## Si un mod con el mismo nombre existe en varias raices, gana el de la
## primera raiz en esta lista.
##
## El estado (activo/inactivo, orden) se guarda en config/mods.json, en
## la raiz primaria. Cada mod tiene un campo root para saber de donde
## vino.

const MODS_ROOT_CANDIDATES: Array[String] = [
	"user://mods",
	"/storage/emulated/0/RubiconEngine/mods",
	"/storage/emulated/0/.RubiconEngine/mods",
]
const ANDROID_STORAGE_PERMISSION := "android.permission.MANAGE_EXTERNAL_STORAGE"
const CACHE_DIR := "user://mods_cache"
const MANIFEST_NAME := "mod.json"
const CONFIG_DIR_NAME := "config"
const CONFIG_FILE_NAME := "mods.json"

signal mods_changed

## Cada mod: {name, version, main_scene, enabled, folder, path, root}
var mods: Array[Dictionary] = []
## Raices legibles en este dispositivo, en orden de prioridad.
var mods_roots: Array[String] = []
## Raiz principal (primera legible). Se usa para config/ y para la UI.
var mods_root: String = ""
var _config: Dictionary = {"enabled": {}, "order": []}
var _loaders: Array[ResourceFormatLoader] = []


func _ready() -> void:
	_request_android_permissions()
	_register_runtime_loaders()
	mods_roots = _resolve_mods_roots()
	mods_root = mods_roots[0] if not mods_roots.is_empty() else MODS_ROOT_CANDIDATES[0]
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_load_config()
	scan()
	_load_all_enabled()


## Pide MANAGE_EXTERNAL_STORAGE en Android. Sin esto, la app no puede
## leer archivos que el usuario dejo en el storage compartido, y cada mod
## aparece con "no define main_scene" aunque el archivo exista.
##
## Best-effort: si el permiso ya esta otorgado, no hace nada. Si no,
## Android abre la pantalla de "Acceso a todos los archivos" del sistema;
## el usuario la acepta o la rechaza, y el ModLoader sigue con las raices
## que si puede leer.
func _request_android_permissions() -> void:
	if OS.get_name() != "Android":
		return
	var granted := OS.get_granted_permissions()
	if ANDROID_STORAGE_PERMISSION in granted:
		print("[ModLoader] permiso de storage ya otorgado")
		return
	print("[ModLoader] pidiendo permiso de storage")
	OS.request_permission("MANAGE_EXTERNAL_STORAGE")


func _register_runtime_loaders() -> void:
	var scripts := [
		"res://engine/runtime_texture_loader.gd",
		"res://engine/runtime_font_loader.gd",
		"res://engine/runtime_video_loader.gd",
		"res://engine/runtime_ktx_loader.gd",
		"res://engine/runtime_model_loader.gd",
		"res://engine/runtime_shader_loader.gd",
		"res://engine/runtime_audio_loader.gd",
	]
	for s in scripts:
		var loader: ResourceFormatLoader = (load(s) as GDScript).new()
		ResourceLoader.add_resource_format_loader(loader, true)
		_loaders.append(loader)
	print("[ModLoader] %d runtime loaders registrados" % _loaders.size())


## Devuelve todas las raices legibles en este dispositivo, en orden.
##
## Ademas de existir, cada candidata tiene que poder LEER un archivo real
## de adentro. Android 11+ lista carpetas ocultas con DirAccess pero
## bloquea FileAccess sobre su contenido, y sin esta comprobacion el
## ModLoader elegiria una raiz que despues no puede leer.
func _resolve_mods_roots() -> Array[String]:
	var out: Array[String] = []
	for candidate in MODS_ROOT_CANDIDATES:
		var err := DirAccess.make_dir_recursive_absolute(candidate)
		if err != OK and not DirAccess.dir_exists_absolute(candidate):
			continue
		if not _can_read_from(candidate):
			push_warning("[ModLoader] %s existe pero no es legible, se omite" % candidate)
			continue
		out.append(candidate)
		print("[ModLoader] raiz legible: %s" % candidate)
	if out.is_empty():
		out.append(MODS_ROOT_CANDIDATES[0])
	return out


## Comprueba lectura real: crea un archivo temporal, lo escribe y lo lee
## de vuelta. Si alguna parte de la cadena falla, la raiz no sirve.
func _can_read_from(dir_path: String) -> bool:
	var probe := dir_path.path_join(".read_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	var back := FileAccess.open(probe, FileAccess.READ)
	if back == null:
		DirAccess.remove_absolute(probe)
		return false
	var txt := back.get_as_text()
	back.close()
	DirAccess.remove_absolute(probe)
	return txt == "ok"


func _config_path() -> String:
	return mods_root.get_base_dir() + "/" + CONFIG_DIR_NAME + "/" + CONFIG_FILE_NAME


func _load_config() -> void:
	_config = {"enabled": {}, "order": []}
	var p := _config_path()
	if not FileAccess.file_exists(p):
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_config = parsed
	if not (_config.get("enabled") is Dictionary):
		_config["enabled"] = {}
	if not (_config.get("order") is Array):
		_config["order"] = []


func save_config() -> void:
	var p := _config_path()
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_error("[ModLoader] no puedo escribir %s" % p)
		return
	f.store_string(JSON.stringify(_config, "  "))


func is_enabled(folder: String) -> bool:
	var en: Dictionary = _config.get("enabled", {})
	if en.has(folder):
		return bool(en[folder])
	for m in mods:
		if m["folder"] == folder:
			return bool(m.get("enabled", true))
	return true


func set_enabled(folder: String, enabled: bool) -> void:
	var en: Dictionary = _config.get("enabled", {})
	en[folder] = enabled
	_config["enabled"] = en
	save_config()
	mods_changed.emit()


func toggle_enabled(folder: String) -> void:
	set_enabled(folder, not is_enabled(folder))


func move_mod(folder: String, direction: int) -> void:
	var idx := -1
	for i in mods.size():
		if mods[i]["folder"] == folder:
			idx = i
			break
	if idx < 0:
		return
	var new_idx := clampi(idx + direction, 0, mods.size() - 1)
	if new_idx == idx:
		return
	var m = mods.pop_at(idx)
	mods.insert(new_idx, m)
	var order: Array = []
	for mm in mods:
		order.append(mm["folder"])
	_config["order"] = order
	save_config()
	mods_changed.emit()


## Escanea TODAS las raices legibles y combina los mods encontrados.
##
## Si el mismo folder aparece en varias raices, gana el de la primera
## raiz en `mods_roots` (que respeta el orden de MODS_ROOT_CANDIDATES).
func scan() -> void:
	mods.clear()
	var seen: Dictionary = {}
	for root in mods_roots:
		_scan_root(root, seen)
	_apply_order()


func _scan_root(root: String, seen: Dictionary) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != ".." and dir.current_is_dir():
			if not seen.has(name):
				var m := _read_manifest(root + "/" + name)
				if not m.is_empty():
					m["folder"] = name
					m["path"] = root + "/" + name
					m["root"] = root
					mods.append(m)
					seen[name] = true
		name = dir.get_next()
	dir.list_dir_end()


func _read_manifest(path: String) -> Dictionary:
	var mf := path + "/" + MANIFEST_NAME
	if not FileAccess.file_exists(mf):
		var d := {"name": path.get_file()}
		# Autodeteccion: main.gd gana si existe; main.tscn si no.
		if FileAccess.file_exists(path + "/main.gd"):
			d["main_scene"] = "res://main.gd"
		elif FileAccess.file_exists(path + "/main.tscn"):
			d["main_scene"] = "res://main.tscn"
		return d
	var f := FileAccess.open(mf, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _apply_order() -> void:
	var explicit: Array = _config.get("order", [])
	var ordered: Array = []
	var rest: Array = mods.duplicate()
	for folder in explicit:
		for m in rest:
			if m["folder"] == folder:
				ordered.append(m)
				rest.erase(m)
				break
	rest.sort_custom(func(a, b): return a["folder"] < b["folder"])
	ordered.append_array(rest)
	mods = ordered


func _load_all_enabled() -> void:
	for m in mods:
		if is_enabled(m["folder"]):
			load_mod(m)


func load_mod(m: Dictionary) -> bool:
	var folder: String = m["folder"]
	var cache_path := CACHE_DIR + "/" + folder + ".pck"
	var mtime_path := CACHE_DIR + "/" + folder + ".mtime"
	var newest := _newest_mtime(m["path"])
	var cached_mtime := 0
	if FileAccess.file_exists(mtime_path):
		cached_mtime = int(FileAccess.open(mtime_path, FileAccess.READ).get_as_text())

	if not FileAccess.file_exists(cache_path) or cached_mtime < newest:
		if not _build_pck(m, cache_path):
			push_error("[ModLoader] no se pudo empaquetar %s" % folder)
			return false
		FileAccess.open(mtime_path, FileAccess.WRITE).store_string(str(newest))

	var ok := ProjectSettings.load_resource_pack(cache_path, true)
	if not ok:
		push_error("[ModLoader] load_resource_pack fallo para %s" % folder)
		return false
	print("[ModLoader] cargado: %s" % m.get("name", folder))
	return true


func _build_pck(m: Dictionary, out: String) -> bool:
	var packer := PCKPacker.new()
	if packer.pck_start(out) != OK:
		return false
	var files: Array[String] = []
	_collect(m["path"], "", files)
	for rel in files:
		var err := packer.add_file("res://" + rel, m["path"] + "/" + rel)
		if err != OK:
			push_warning("[ModLoader] add_file %s fallo: %d" % [rel, err])
	return packer.flush(true) == OK


func _collect(root: String, sub: String, out: Array[String]) -> void:
	var path := root if sub.is_empty() else root + "/" + sub
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var rel := name if sub.is_empty() else sub + "/" + name
			if dir.current_is_dir():
				_collect(root, rel, out)
			elif not name.ends_with(".import") and not name.ends_with(".uid") and name != MANIFEST_NAME:
				out.append(rel)
		name = dir.get_next()
	dir.list_dir_end()


func _newest_mtime(path: String) -> int:
	var newest := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path + "/" + name
			if dir.current_is_dir():
				newest = max(newest, _newest_mtime(full))
			else:
				newest = max(newest, int(FileAccess.get_modified_time(full)))
		name = dir.get_next()
	dir.list_dir_end()
	return newest
