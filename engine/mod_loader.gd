extends Node
## Carga mods externos desde una carpeta en el almacenamiento del telefono.
## Cada mod vive en /storage/emulated/0/.RubiconEngine/mods/<nombre>/ y
## contiene un mod.json + archivos con estructura espejo de res://.

const MODS_ROOT_CANDIDATES: Array[String] = [
	"/storage/emulated/0/.RubiconEngine/mods",
	"user://mods",
]
const ORDER_FILE_NAME := "mods_order.txt"
const CACHE_DIR := "user://mods_cache"
const MANIFEST_NAME := "mod.json"

var mods: Array[Dictionary] = []
var mods_root: String = ""

func _ready() -> void:
	mods_root = _resolve_mods_root()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	scan()
	_load_all_enabled()

func _resolve_mods_root() -> String:
	for candidate in MODS_ROOT_CANDIDATES:
		var err := DirAccess.make_dir_recursive_absolute(candidate)
		if err == OK or DirAccess.dir_exists_absolute(candidate):
			return candidate
	return MODS_ROOT_CANDIDATES[0]

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
		return {}
	var f := FileAccess.open(mf, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

func _apply_order() -> void:
	var order_path := mods_root.get_base_dir() + "/config/" + ORDER_FILE_NAME
	var order: Array[String] = []
	if FileAccess.file_exists(order_path):
		var txt := FileAccess.open(order_path, FileAccess.READ).get_as_text()
		for line in txt.split("\n"):
			var s := line.strip_edges()
			if not s.is_empty() and not s.begins_with("#"):
				order.append(s)

	var ordered: Array = []
	var rest: Array = mods.duplicate()
	for folder in order:
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
		if m.get("enabled", true):
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
