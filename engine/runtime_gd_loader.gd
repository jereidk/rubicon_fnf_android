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

## Igual que mod_gd_paths pero con el path fisico como valor.
## Con el split de pck, los .gd NO van al pck: se leen directo
## del filesystem del mod. Este mapeo dice a donde apuntar.
var mod_all_paths: Dictionary = {}


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gd"])


func _get_resource_type(path: String) -> String:
	if mod_gd_paths.has(path):
		return "GDScript"
	return ""


func _handles_type(type: StringName) -> bool:
	return type == &"GDScript" or type == &"Script"


## Override explicito de recognize_path. Necesario porque Godot llama a
## recognize_path() con el type_hint que el analyzer le pasa al preload()
## - y para un preload("res://helper.gd") en un script analizado como
## posible PackedScene, el hint llega como "PackedScene".
##
## En ese caso el filtro por defecto de ResourceFormatLoader llama a
## get_recognized_extensions_for_type("PackedScene"), que a su vez usa
## handles_type("PackedScene"), que devuelve false para un loader de
## GDScript. Resultado: el loader se descarta y Godot tira "No loader
## found for resource" sin importar que _load() hubiera funcionado.
##
## _recognize_path corre ANTES del filtro por extensiones (verificado en
## ResourceFormatLoader::recognize_path), asi que devolviendo true para
## nuestros paths ignoramos el type_hint por completo.
func _recognize_path(path: String, _for_type: StringName) -> bool:
	return mod_gd_paths.has(path)


func _exists(path: String) -> bool:
	# El analyzer llama exists() al resolver preload(). Sin pck, res://
	# no ve el filesystem del mod, asi que el default daria false y
	# abortaria el preload de cualquier .gd del mod.
	return mod_gd_paths.has(path)


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	# No es un .gd de un mod: devolver null para que Godot siga con el
	# loader nativo. El ciclo de ResourceLoader::_load() chequea
	# res.is_valid() y continua si no lo es.
	# LOG: entrada y estado de los 3 diccionarios.
	DebugLog.log("[gd_loader._load] path=%s in_mod_gd=%s in_mod_all=%s" % [
		path, mod_gd_paths.has(path), mod_all_paths.has(path),
	])
	if not mod_gd_paths.has(path):
		DebugLog.log("[gd_loader._load] RECHAZA: no esta en mod_gd_paths")
		return null
	var src_path: String = path
	if mod_all_paths.has(path):
		src_path = String(mod_all_paths[path])
	DebugLog.log("[gd_loader._load] src_path=%s exists=%s" % [
		src_path, FileAccess.file_exists(src_path),
	])
	if not FileAccess.file_exists(src_path):
		return null

	var src := FileAccess.get_file_as_string(src_path)
	if src.is_empty():
		push_warning("[RuntimeGDLoader] %s esta vacio" % path)
		return null

	var gd := GDScript.new()
	gd.source_code = src
	if gd.reload() != OK:
		push_warning("[RuntimeGDLoader] reload fallo para %s" % path)
		return null
	return gd
