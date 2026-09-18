extends ResourceFormatLoader

## Paths res:// de todos los mods activos. Compartido por referencia
## con ModLoader. Si el path esta aca, es un archivo crudo de un mod
## y hay que leerlo ignorando su .import hermano (que el editor dejo
## en el mod y que apunta a un .oggstr/.ctex que no existe en el pck).
var mod_all_paths: Dictionary = {}

# Carga .ogg/.mp3/.wav crudos en runtime, para mods.
#
# Sin esto, un mod que traiga audio crudo falla: el built-in de Godot no
# reemplaza .ogg/.mp3/.wav desde un .pck montado con replace_files
# (godotengine/godot#104678, confirmado por Calinou). El motivo es que
# esos formatos pasan por el import process del editor, y un .pck montado
# en runtime no puede correr ese proceso. Los loaders de runtime
# interceptan la carga ANTES del import, que es lo que los hace
# funcionar donde el built-in no llega.
#
# Firmas verificadas contra el source de 4.7.1-stable:
#   AudioStreamOggVorbis.load_from_buffer(bytes)             -> Ref
#   AudioStreamMP3.load_from_buffer(bytes)                   -> Ref
#   AudioStreamWAV.load_from_buffer(bytes, options={})       -> Ref
# Los tres son static y estan bindeados a GDScript.

const EXTENSIONS: PackedStringArray = ["ogg", "mp3", "wav"]

func _get_recognized_extensions() -> PackedStringArray:
	return EXTENSIONS

func _get_resource_type(_path: String) -> String:
	return "AudioStream"

func _recognize_path(path: String, _for_type: StringName) -> bool:
	# Godot llama a recognize_path con el type_hint que el analyzer le
	# pasa al preload(). Para preload("res://x.png") en un script que no
	# lo usa explicitamente como Texture2D, el hint llega como
	# "PackedScene". El filtro por defecto (handles_type) devuelve false
	# para PackedScene, y el loader se descarta ANTES de que _load()
	# corra. _recognize_path se evalua antes de ese filtro, asi que
	# devolviendo true para nuestras extensiones ignoramos el type_hint.
	return path.get_extension().to_lower() in EXTENSIONS

func _handles_type(type: StringName) -> bool:
	return type == &"AudioStream"

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if not mod_all_paths.has(path) and FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(path):
		return null

	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null

	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null
