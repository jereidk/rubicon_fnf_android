extends ResourceFormatLoader
# Carga fuentes .ttf/.otf crudas en runtime, para mods.
#
# FontFile.load_dynamic_font_from_buffer NO EXISTE en Godot 4.7.1 (solo
# esta la version desde path, bindeada a GDScript). Pero load_dynamic_font
# abre el archivo con FileAccess internamente, y FileAccess virtualiza los
# paths del .pck montado - asi que pasarle el res:// del mod funciona
# exactamente igual que si fuera un archivo en disco.

const EXTENSIONS := PackedStringArray(["ttf", "otf"])

func _get_recognized_extensions() -> PackedStringArray:
	return EXTENSIONS

func _get_resource_type(_path: String) -> String:
	return "FontFile"

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
