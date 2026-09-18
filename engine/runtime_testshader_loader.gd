extends ResourceFormatLoader

## Paths res:// de todos los mods activos. Compartido por referencia
## con ModLoader. Si el path esta aca, es un archivo crudo de un mod
## y hay que leerlo ignorando su .import hermano (que el editor dejo
## en el mod y que apunta a un .oggstr/.ctex que no existe en el pck).
var mod_all_paths: Dictionary = {}

# Carga PNG/JPG/WebP crudos en runtime, para mods.
#
# Godot no puede leer un PNG suelto con load() - solo .ctex ya importados
# por el editor. Los mods traen PNGs directos, asi que sus escenas no
# resolverian las texturas. Este loader se registra ANTES del default y
# maneja solo los paths que NO tienen .import (o sea, assets crudos de
# mod). Todo lo demas cae al loader por defecto - el APK sigue igual.

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

# Devuelve null (no ERR_*) para decirle a Godot "no lo manejo, segui con
# el loader por defecto". Un codigo de error aca aborta la cadena y deja
# al APK sin sus texturas.
func _exists(path: String) -> bool:
	# Godot llama a exists() al resolver un preload() y al consultar
	# ResourceLoader.exists(). Sin pck, res:// no ve el filesystem del
	# mod, asi que el default (FileAccess::exists) daria false. Este
	# override le dice que si, y el analyzer procede a _load().
	return mod_all_paths.has(path)


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if not mod_all_paths.has(path) and FileAccess.file_exists(path + ".import"):
		return null
	var src: String = path
	if mod_all_paths.has(path):
		src = String(mod_all_paths[path])
	if not FileAccess.file_exists(src):
		return null
	var code := FileAccess.get_file_as_string(src)
	if code.is_empty():
		return null
	var shader := Shader.new()
	shader.code = code
	return shader
