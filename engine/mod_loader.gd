extends Node
## Carga mods externos desde /storage/emulated/0/.RubiconEngine/mods/.
## El estado (activo/inactivo, orden) se guarda en config/mods.json,
## gestionado por la pantalla ModManager. El campo "enabled" de cada
## mod.json solo se usa como valor por defecto la primera vez.

const MODS_ROOT_CANDIDATES: Array[String] = [
	"/storage/emulated/0/.RubiconEngine/mods",
	"user://mods",
]
const CACHE_DIR := "user://mods_cache"
const MANIFEST_NAME := "mod.json"
const CONFIG_DIR_NAME := "config"
const CONFIG_FILE_NAME := "mods.json"

signal mods_changed

var mods: Array[Dictionary] = []
var mods_root: String = ""
var _config: Dictionary = {"enabled": {}, "order": []}
var _loaders: Array[ResourceFormatLoader] = []


func _ready() -> void:
	_register_texture_loader()
	mods_root = _resolve_mods_root()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_load_config()
	scan()
	_load_all_enabled()


func _register_texture_loader() -> void:
	var scripts := [
		"res://engine/runtime_texture_loader.gd",
		"res://engine/runtime_font_loader.gd",
		"res://engine/runtime_video_loader.gd",
	]
	for s in scripts:
		var loader: ResourceFormatLoader = (load(s) as GDScript).new()
		ResourceLoader.add_resource_format_loader(loader, true)
		_loaders.append(loader)
	print("[ModLoader] %d runtime loaders registrados (texture/font/video)" % _loaders.size())


func _resolve_mods_root() -> String:
	for candidate in MODS_ROOT_CANDIDATES:
		var err := DirAccess.make_dir_recursive_absolute(candidate)
		if err == OK or DirAccess.dir_exists_absolute(candidate):
			return candidate
	return MODS_ROOT_CANDIDATES[0]


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


func scan() -> void:
	mods.clear()
	var dir := DirAccess.open(mods_root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != ".." and dir.current_is_dir():
			var m := _read_manifest(mods_root + "/" + name)
			if not m.is_empty():
				m["folder"] = name
				m["path"] = mods_root + "/" + name
				mods.append(m)
		name = dir.get_next()
	dir.list_dir_end()
	_apply_order()


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
	if explicit.is_empty():
		var legacy := mods_root.get_base_dir() + "/config/mods_order.txt"
		if FileAccess.file_exists(legacy):
			var txt := FileAccess.open(legacy, FileAccess.READ).get_as_text()
			for line in txt.split("
"):
				var s := line.strip_edges()
				if not s.is_empty() and not s.begins_with("#"):
					explicit.append(s)

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
