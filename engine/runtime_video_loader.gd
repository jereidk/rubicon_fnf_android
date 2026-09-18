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

func _exists(path: String) -> bool:
	# Godot llama a exists() al resolver un preload() y al consultar
	# ResourceLoader.exists(). Sin pck, res:// no ve el filesystem del
	# mod, asi que el default (FileAccess::exists) daria false. Este
	# override le dice que si, y el analyzer procede a _load().
	return mod_all_paths.has(path)


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	# Si el path es de un mod, leer del archivo fisico. Sin pck, res://
	# no ve el filesystem del mod - el mapeo res:// -> path fisico vive
	# en mod_all_paths (Dictionary compartido por referencia con
	# ModLoader). Si no es de un mod, es un archivo del APK: si tiene
	# .import hermano, delegar al loader nativo.
	var src: String = path
	if mod_all_paths.has(path):
		src = String(mod_all_paths[path])
	elif FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(src):
		return null
	var vs := VideoStreamTheora.new()
	vs.file = src
	return vs
