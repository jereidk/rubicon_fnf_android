extends ResourceFormatLoader

## Paths res:// de todos los mods activos. Compartido por referencia
## con ModLoader. Si el path esta aca, es un archivo crudo de un mod
## y hay que leerlo ignorando su .import hermano (que el editor dejo
## en el mod y que apunta a un .oggstr/.ctex que no existe en el pck).
var mod_all_paths: Dictionary = {}

# Carga .ogv (Theora) crudos en runtime, para mods.
#
# Godot importa los videos a un .ogvstr al abrir el proyecto, y load()
# solo resuelve esos. Los mods traen el .ogv directo. VideoStreamTheora
# no tiene load_from_buffer, asi que le pasamos el path y Godot lo abre
# al reproducir. Eso funciona para archivos en disco (los mods lo estan);
# no funcionaria para archivos dentro del .pck, pero los del APK ya
# tienen su .ogvstr importado y los maneja el loader default.

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["ogv"])

func _get_resource_type(_path: String) -> String:
	return "VideoStreamTheora"

func _recognize_path(path: String, _for_type: StringName) -> bool:
	# Mismo motivo que en los demas runtime loaders: el type_hint del
	# preload() puede llegar como "PackedScene" y descartar el loader
	# antes de _load(). _recognize_path corre antes del filtro.
	return path.get_extension().to_lower() == "ogv"


func _handles_type(type: StringName) -> bool:
	return type == &"VideoStream" or type == &"VideoStreamTheora"

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if not mod_all_paths.has(path) and FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(path):
		return null
	var vs := VideoStreamTheora.new()
	vs.file = path
	return vs
