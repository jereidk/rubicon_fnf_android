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
## Emitido cuando un reload automatico (vuelta del background) encontro
## cambios. La UI lo escucha para refrescar sin que el usuario tenga que
## tocar "Releer".
signal mods_reloaded(changed_folders: Array)

## Cada mod: {name, version, main_scene, enabled, folder, path, root}
var mods: Array[Dictionary] = []
## Raices legibles en este dispositivo, en orden de prioridad.
var mods_roots: Array[String] = []
## Raiz principal (primera legible). Se usa para config/ y para la UI.
var mods_root: String = ""
var _config: Dictionary = {"enabled": {}, "order": []}
var _loaders: Array[ResourceFormatLoader] = []
## Cuando la app vuelve del background marcamos para recargar en el
## proximo frame donde la escena actual sea segura (ModSelector o
## ModManager). No recargamos durante gameplay: cambiar el .pck de un mod
## mientras corre una cancion rompe las referencias cargadas.
var _pending_rescan: bool = false
## Escena actual, para detectar el cambio y solo actuar en pantallas
## seguras.
var _last_scene_path: String = ""
## Nombres de carpeta cuyo mtime cambio desde el ultimo escaneo.
var _changed_on_resume: Array[String] = []
## Mods con el mismo nombre de carpeta en mas de una raiz. Cada entrada:
## {name, roots: [root1, root2, ...], winner: root}.
var duplicates: Array[Dictionary] = []
## Colisiones entre mods habilitados: res://path -> [folder1, folder2].
## Se recalcula en cada scan() y en cada cambio de enabled/order.
var collisions: Dictionary = {}


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


func _notification(what: int) -> void:
	# Android y iOS suspenden la app cuando el usuario la deja en segundo
	# plano. Al volver, NOTIFICATION_APPLICATION_RESUMED llega antes que
	# cualquier _process, y es el punto correcto para chequear si el
	# usuario edito algun mod mientras estaba afuera.
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_pending_rescan = true


func _process(_delta: float) -> void:
	# Solo procesamos si hay un rescan pendiente. El costo en idle es una
	# comparacion de bool, invisible.
	if not _pending_rescan:
		return

	var scene := get_tree().current_scene
	if scene == null:
		return
	var path: String = scene.scene_file_path

	# Solo recargamos si estamos en una pantalla de gestion. Si el usuario
	# estaba jugando, dejamos el flag prendido y esperamos a que vuelva.
	if not (path.ends_with("mod_selector.tscn") or path.ends_with("mod_manager.tscn")):
		return

	_pending_rescan = false
	reload_changed_mods()


## Chequea que mods cambiaron desde el ultimo scan y, si hay alguno,
## re-escanea la carpeta, reconstruye los .pck cambiados y emite
## mods_reloaded con la lista. Llamado automaticamente al volver del
## background en pantallas seguras, o manualmente desde el ModManager.
func reload_changed_mods() -> void:
	var changed: Array[String] = []
	for m in mods:
		var folder: String = m["folder"]
		var newest := _newest_mtime(m["path"])
		var cached := _cached_mtime(folder)
		if newest > cached:
			changed.append(folder)

	if changed.is_empty():
		return

	print("[ModLoader] reload: %d mods cambiaron (%s)" % [changed.size(), ", ".join(changed)])
	scan()
	# Reconstruir solo los .pck cambiados. load_mod() ya chequea mtime y
	# saltea el empaquetado si nada cambio, asi que llamamos a los de la
	# lista + los que estan enabled.
	for m in mods:
		if m["folder"] in changed and is_enabled(m["folder"]):
			load_mod(m)
	_changed_on_resume = changed
	mods_changed.emit()
	mods_reloaded.emit(changed)


## Ultimo mtime guardado en disco para ese mod, 0 si no hay cache.
func _cached_mtime(folder: String) -> int:
	var p := CACHE_DIR + "/" + folder + ".mtime"
	if not FileAccess.file_exists(p):
		return 0
	return int(FileAccess.open(p, FileAccess.READ).get_as_text())


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


## Recalcula que paths de res:// estan definidos por mas de un mod
## habilitado al mismo tiempo. El resultado va a `collisions`, que la UI
## usa para avisar al usuario. No bloquea nada: solo informa.
##
## Es O(total de archivos de los mods habilitados), y corre en cada
## scan() + cada cambio de enabled. En una lista de 10 mods con 500
## archivos cada uno son 5000 lookups de path, ~10 ms. Se podria cachear
## por (folder, mtime) pero no hace falta por ahora.
func _recompute_collisions() -> void:
	collisions.clear()
	var paths: Dictionary = {}  # "res://path" -> [folder]
	for m in mods:
		if not is_enabled(m["folder"]):
			continue
		var files: Array[String] = []
		_collect(m["path"], "", files)
		for rel in files:
			var res_path := "res://" + rel
			if not paths.has(res_path):
				paths[res_path] = []
			paths[res_path].append(m["folder"])
	for res_path in paths:
		if paths[res_path].size() > 1:
			collisions[res_path] = paths[res_path]


## Devuelve los paths de res:// que define este mod y que tambien define
## otro. Usado por el ModManager para mostrar "choca con world" en la
## fila de cada mod.
func collisions_for(folder: String) -> Array[String]:
	var out: Array[String] = []
	for res_path in collisions:
		var folders: Array = collisions[res_path]
		if folder in folders:
			out.append(res_path)
	return out


## Desinstala un mod: borra su carpeta, su .pck y su entrada en la
## config. No pide confirmacion: es responsabilidad de la UI preguntar
## antes.
func uninstall_mod(folder: String) -> bool:
	var found: Dictionary = {}
	for m in mods:
		if m["folder"] == folder:
			found = m
			break
	if found.is_empty():
		push_warning("[ModLoader] uninstall: no existe %s" % folder)
		return false

	# Borrar la carpeta recursivamente
	var err := _remove_recursive(found["path"])
	if err != OK:
		push_error("[ModLoader] uninstall: no pude borrar %s (err %d)" % [found["path"], err])
		return false

	# Borrar cache del .pck
	DirAccess.remove_absolute(CACHE_DIR + "/" + folder + ".pck")
	DirAccess.remove_absolute(CACHE_DIR + "/" + folder + ".mtime")

	# Sacar de la config
	var en: Dictionary = _config.get("enabled", {})
	en.erase(folder)
	_config["enabled"] = en
	var order: Array = _config.get("order", [])
	order.erase(folder)
	_config["order"] = order
	save_config()

	# Rescan para que la lista quede actualizada
	scan()
	mods_changed.emit()
	print("[ModLoader] uninstalled: %s" % folder)
	return true


## DirAccess.remove_absolute() solo borra archivos, no directorios con
## contenido. Hay que caminar el arbol y borrar de abajo hacia arriba.
func _remove_recursive(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return DirAccess.remove_absolute(path)

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path + "/" + name
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path)


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
	_recompute_collisions()
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
	_recompute_collisions()
	mods_changed.emit()


## Escanea TODAS las raices legibles y combina los mods encontrados.
##
## Si el mismo folder aparece en varias raices, gana el de la primera
## raiz en `mods_roots` (que respeta el orden de MODS_ROOT_CANDIDATES).
func scan() -> void:
	mods.clear()
	duplicates.clear()
	var seen: Dictionary = {}  # folder -> root del ganador
	var seen_roots: Dictionary = {}  # folder -> [roots donde aparece]
	for root in mods_roots:
		_scan_root(root, seen, seen_roots)
	# Armar duplicados: folders que aparecen en mas de una raiz.
	for folder in seen_roots:
		var roots: Array = seen_roots[folder]
		if roots.size() > 1:
			duplicates.append({
				"name": folder,
				"roots": roots.duplicate(),
				"winner": roots[0],  # gana la primera raiz en mods_roots
			})
	_apply_order()
	_recompute_collisions()


func _scan_root(root: String, seen: Dictionary, seen_roots: Dictionary) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != ".." and dir.current_is_dir():
			# Registrar siempre en seen_roots, para saber si el folder
			# aparece tambien en otra raiz.
			if not seen_roots.has(name):
				seen_roots[name] = []
			seen_roots[name].append(root)
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
