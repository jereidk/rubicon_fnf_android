extends ResourceFormatLoader

## Carga .gdshader crudos en runtime, para mods.
##
## Godot importa los shaders a .res al abrir el proyecto, y load() solo
## resuelve esos. Los mods traen el .gdshader directo, con la sintaxis
## propia de Godot (shader_type, void fragment(), etc).
##
## Mismo patron que runtime_texture_loader: si el path es de un mod,
## leer del archivo fisico (el mapeo res:// -> fisico vive en
## mod_all_paths). Si es del APK, delegar al loader nativo via null.

var mod_all_paths: Dictionary = {}

const EXTENSIONS: PackedStringArray = ["gdshader"]


func _get_recognized_extensions() -> PackedStringArray:
	return EXTENSIONS


func _get_resource_type(_path: String) -> String:
	return "Shader"


func _recognize_path(path: String, _for_type: StringName) -> bool:
	return path.get_extension().to_lower() in EXTENSIONS


func _handles_type(type: StringName) -> bool:
	return type == &"Shader"


func _exists(path: String) -> bool:
	return mod_all_paths.has(path)


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	var src: String = path
	if mod_all_paths.has(path):
		src = String(mod_all_paths[path])
	elif FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(src):
		return null
	var code := FileAccess.get_file_as_string(src)
	if code.is_empty():
		return null
	var shader := Shader.new()
	shader.code = code
	return shader
