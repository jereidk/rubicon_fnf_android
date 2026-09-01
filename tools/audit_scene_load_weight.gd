extends SceneTree

## Cuanto pesa DE VERDAD cargar una escena, en bytes que salen del disco.
##
## El log del dispositivo mide la entrada a la tienda en 45.856ms y su propia
## linea de reparto por carpetas solo explica 17,9s de esos 45,9 - el resto son
## atascos en los que no llega ninguna dependencia, o sea un fichero grande
## siendo leido. Para saber cuales, hace falta el arbol de dependencias con el
## tamaño del ARTEFACTO IMPORTADO al lado, que es lo que el APK contiene y lo
## que el telefono lee. El .png de origen no viaja: para cada recurso con
## `.import`, lo que se lee es lo que diga su `dest_files`.
##
## Run with:
##   godot --headless --path . --script tools/audit_scene_load_weight.gd [ruta.tscn]

const DEFAULT_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"

var _seen: Dictionary = {}
var _size_of: Dictionary = {}


func _initialize() -> void:
	var target: String = DEFAULT_SCENE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = args[0]

	if not ResourceLoader.exists(target):
		printerr("no existe: %s" % target)
		quit(1)
		return

	_walk(target)

	var rows: Array = []
	var total: int = 0
	for path: String in _size_of:
		total += int(_size_of[path])
		rows.append([int(_size_of[path]), path])
	rows.sort_custom(func(a, b): return a[0] > b[0])

	print("escena   : %s" % target)
	print("recursos : %d" % _size_of.size())
	print("bytes    : %.1f MB\n" % (float(total) / 1048576.0))

	print("--- los 30 mas gordos ---")
	for i: int in mini(30, rows.size()):
		print("%9.2f MB  %s" % [float(rows[i][0]) / 1048576.0, rows[i][1]])

	var by_dir: Dictionary = {}
	for row: Array in rows:
		var dir: String = String(row[1]).get_base_dir()
		by_dir[dir] = int(by_dir.get(dir, 0)) + int(row[0])
	var dirs: Array = []
	for d: String in by_dir:
		dirs.append([int(by_dir[d]), d])
	dirs.sort_custom(func(a, b): return a[0] > b[0])

	print("\n--- por carpeta, top 20 ---")
	for i: int in mini(20, dirs.size()):
		print("%9.2f MB  %s" % [float(dirs[i][0]) / 1048576.0, dirs[i][1]])

	# Y por importador y ajustes, que es donde se puede tocar sin borrar nada.
	var by_kind: Dictionary = {}
	for row: Array in rows:
		by_kind[_kind_of(String(row[1]))] = [
			int(by_kind.get(_kind_of(String(row[1])), [0, 0])[0]) + int(row[0]),
			int(by_kind.get(_kind_of(String(row[1])), [0, 0])[1]) + 1,
		]
	var kinds: Array = []
	for k: String in by_kind:
		kinds.append([by_kind[k][0], by_kind[k][1], k])
	kinds.sort_custom(func(a, b): return a[0] > b[0])

	print("\n--- por importador y ajustes ---")
	for k: Array in kinds:
		print("%9.2f MB  %4d ficheros  %s" % [float(k[0]) / 1048576.0, k[1], k[2]])

	quit(0)


## Importador y los ajustes que deciden el tamaño, como una etiqueta agrupable.
func _kind_of(path: String) -> String:
	var import_path: String = path + ".import"
	if not FileAccess.file_exists(import_path):
		return "(sin importar) " + path.get_extension()
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return "(.import ilegible)"
	var importer: String = str(cfg.get_value("remap", "importer", "?"))
	var block: Variant = cfg.get_value("params", "compress/block_size", null)
	var mips: Variant = cfg.get_value("params", "mipmaps/generate", null)
	if block == null and mips == null:
		return importer
	return "%s block=%s mipmaps=%s" % [importer, block, mips]


func _walk(path: String) -> void:
	if _seen.has(path):
		return
	_seen[path] = true

	_size_of[path] = _weight_of(path)

	for dep: String in ResourceLoader.get_dependencies(path):
		# `get_dependencies()` devuelve "uid::tipo::ruta" o "ruta::tipo" segun
		# como se escribiera la referencia; la ruta es siempre el ultimo campo
		# que empieza por res:// .
		var real: String = ""
		for part: String in dep.split("::"):
			if part.begins_with("res://") or part.begins_with("uid://"):
				real = part
		if real.begins_with("uid://"):
			var id: int = ResourceUID.text_to_id(real)
			real = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
		if real.is_empty() or not ResourceLoader.exists(real):
			continue
		_walk(real)


## Los bytes que el juego lee para este recurso.
##
## Con `.import`, lo que viaja en el APK es lo que diga `dest_files` y no el
## fichero de origen - un .png de 18MB puede quedarse en 2MB de ASTC, y un .gltf
## de 400KB puede arrastrar un .bin de 37MB que no viaja porque el importador ya
## lo horneo dentro del .scn.
func _weight_of(path: String) -> int:
	var import_path: String = path + ".import"
	if FileAccess.file_exists(import_path):
		var cfg := ConfigFile.new()
		if cfg.load(import_path) == OK:
			# Contados una sola vez. `remap/path` y `deps/dest_files` nombran el
			# MISMO artefacto en el caso normal de un destino, y sumar los dos
			# daba justo el doble: la tienda salia a 143MB cuando son 71,5.
			var out: Dictionary = {}
			var dest: Variant = cfg.get_value("remap", "path", null)
			if dest is String:
				out[String(dest)] = true
			var files: Variant = cfg.get_value("deps", "dest_files", null)
			if files is PackedStringArray or files is Array:
				for f: String in files:
					out[String(f)] = true
			var total: int = 0
			for f: String in out:
				total += _file_size(f)
			if total > 0:
				return total
	return _file_size(path)


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n: int = f.get_length()
	f.close()
	return n
