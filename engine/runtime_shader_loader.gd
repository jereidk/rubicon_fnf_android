extends ResourceFormatLoader
# Carga .gdshader crudos en runtime, para mods.
#
# Godot importa los shaders a .res al abrir el proyecto, y load() solo
# resuelve esos. Los mods traen el .gdshader directo, con la sintaxis
# propia de Godot (shader_type, void fragment(), etc). Mismo patron que
# los otros loaders: si hay .import, deferimos; si no, leemos el codigo
# y devolvemos un Shader.

const EXTENSIONS: PackedStringArray = ["gdshader"]

func _get_recognized_extensions() -> PackedStringArray:
	return EXTENSIONS

func _get_resource_type(_path: String) -> String:
	return "Shader"

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
	return type == &"Shader"

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(path):
		return null
	var code := FileAccess.get_file_as_string(path)
	if code.is_empty():
		return null
	var shader := Shader.new()
	shader.code = code
	return shader
