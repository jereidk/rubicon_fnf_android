extends ResourceFormatLoader
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

func _get_resource_type(_path: String) -> String:
	return "FontFile"

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

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(path):
		return null
	var font := FontFile.new()
	var err := font.load_dynamic_font(path)
	if err != OK:
		push_warning("[RuntimeFontLoader] no pude cargar %s (err %d)" % [path, err])
		return null
	return font
