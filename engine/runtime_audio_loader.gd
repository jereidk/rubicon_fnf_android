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

func _init() -> void:
	# Log de creacion de instancia. Si _register_runtime_loaders
	# crashea en script.new(), el _init del loader no va a aparecer
	# en el log y sabemos exactamente cual fallo.
	var dl := get_node_or_null("/root/DebugLog")
	if dl != null:
		dl.log("[runtime_audio_loader] _init OK")


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

	var bytes := FileAccess.get_file_as_bytes(src)
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
