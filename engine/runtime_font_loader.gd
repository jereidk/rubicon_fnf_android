extends ResourceFormatLoader

## Paths res:// de todos los mods activos. Compartido por referencia
## con ModLoader. Si el path esta aca, es un archivo crudo de un mod
## y hay que leerlo ignorando su .import hermano (que el editor dejo
## en el mod y que apunta a un .oggstr/.ctex que no existe en el pck).
var mod_all_paths: Dictionary = {}

# Carga fuentes .ttf/.otf crudas en runtime, para mods.
#
# FontFile.load_dynamic_font_from_buffer NO EXISTE en Godot 4.7.1 (solo
# esta la version desde path, bindeada a GDScript). Pero load_dynamic_font
# abre el archivo con FileAccess internamente, y FileAccess virtualiza los
# paths del .pck montado - asi que pasarle el res:// del mod funciona
# exactamente igual que si fuera un archivo en disco.

const EXTENSIONS: PackedStringArray = ["ttf", "otf"]

func _get_recognized_extensions() -> PackedStringArray:
	return EXTENSIONS

func _get_resource_type(path: String) -> String:
	# Chequear la extension ANTES de devolver el tipo. Sin esto, el
	# loader devuelve "FontFile" para CUALQUIER path (incluso .tscn)
	# y el analyzer cree que un preload de .tscn es un FontFile.
	if path.get_extension().to_lower() in EXTENSIONS:
		return "FontFile"
	return ""

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
	return type == &"FontFile"

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
	var font := FontFile.new()
	var err := font.load_dynamic_font(src)
	if err != OK:
		push_warning("[RuntimeFontLoader] no pude cargar %s (err %d)" % [path, err])
		return null
	return font
