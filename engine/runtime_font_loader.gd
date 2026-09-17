extends ResourceFormatLoader
# Carga fuentes .ttf/.otf crudas en runtime, para mods.
#
# Godot importa las fuentes a .fontdata al abrir el proyecto, y load()
# solo resuelve esas. Los mods traen el .ttf/.otf directo, asi que sin
# este loader sus escenas no verian la fuente. Mismo patron que el
# texture loader: si hay .import, deferimos; si no, leemos el archivo
# crudo y devolvemos un FontFile.

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
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var font := FontFile.new()
	var err := font.load_dynamic_font_from_buffer(bytes)
	if err != OK:
		push_warning("[RuntimeFontLoader] no pude cargar %s (err %d)" % [path, err])
		return null
	return font
