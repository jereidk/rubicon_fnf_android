extends ResourceFormatLoader
# Carga PNG/JPG/WebP crudos en runtime, para mods.
#
# Godot no puede leer un PNG suelto con load() - solo .ctex ya importados
# por el editor. Los mods traen PNGs directos, asi que sus escenas no
# resolverian las texturas. Este loader se registra ANTES del default y
# maneja solo los paths que NO tienen .import (o sea, assets crudos de
# mod). Todo lo demas cae al loader por defecto - el APK sigue igual.

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["png", "jpg", "jpeg", "webp"])

func _get_resource_type(path: String) -> String:
	return "Texture2D"

func _handles_type(type: StringName) -> bool:
	return type == &"Texture2D"

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if FileAccess.file_exists(path + ".import"):
		return ERR_FILE_NOT_FOUND
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		push_warning("[RuntimeTextureLoader] no pude leer %s (err %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(img)
