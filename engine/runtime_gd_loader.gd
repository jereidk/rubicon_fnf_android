extends ResourceFormatLoader

## Compila .gd desde mods montados en pck.
##
## El ResourceFormatLoaderGDScript nativo devuelve un GDScript hueco
## (base RefCounted, sin metodos) cuando el .gd vive dentro de un pck
## montado con load_resource_pack(). El sintoma es "Script is invalid"
## o "Script inherits from native type 'RefCounted'" al asignarlo a
## un nodo, y "Identifier not found" para los identificadores que el
## script hueco no declara.
##
## Este loader se registra at_front=true, antes que el nativo. Solo
## intercepta paths que ModLoader registro como provenientes de un mod
## activo. Para todo lo demas devuelve null y Godot delega al nativo.
##
## El registro mod_gd_paths es un Dictionary compartido con ModLoader.
## En GDScript los Dictionary se pasan por referencia, asi que mutarlo
## desde ModLoader se ve aca sin sincronizacion.

## Paths .gd que vienen de algun mod activo. Lo llena ModLoader en
## _register_mod_gd_paths, uno por cada archivo .gd dentro de cada mod.
## Compartido por referencia - no copiar.
var mod_gd_paths: Dictionary = {}


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gd"])


func _get_resource_type(path: String) -> String:
	if mod_gd_paths.has(path):
		return "GDScript"
	return ""


func _handles_type(type: StringName) -> bool:
	return type == &"GDScript" or type == &"Script"


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	# No es un .gd de un mod: devolver null para que Godot siga con el
	# loader nativo. El ciclo de ResourceLoader::_load() chequea
	# res.is_valid() y continua si no lo es.
	if not mod_gd_paths.has(path):
		return null
	if not FileAccess.file_exists(path):
		return null

	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		push_warning("[RuntimeGDLoader] %s esta vacio" % path)
		return null

	var gd := GDScript.new()
	gd.source_code = src
	if gd.reload() != OK:
		push_warning("[RuntimeGDLoader] reload fallo para %s" % path)
		return null
	return gd
