extends ResourceFormatLoader
# Carga texturas KTX con ASTC/ETC2/BC7 adentro, incluyendo las que el
# modder nombre .astc por comodidad.
#
# Godot no tiene load_astc_from_buffer(), pero SI load_ktx_from_buffer(),
# y el KTX es el contenedor estandar de Khronos que puede llevar ASTC
# adentro. Asi que la convencion del mod es: el archivo es un KTX real,
# pero se llama .astc para que sea obvio que es un asset comprimido en
# ASTC. El loader acepta ambas extensiones y las trata igual.
#
# Para generar el archivo (con astcenc):
#   astcenc -cl input.png output.ktx 6x6
# Y luego renombrar output.ktx -> output.astc antes de meterlo al mod.

const EXTENSIONS: PackedStringArray = ["ktx", "astc"]

func _get_recognized_extensions() -> PackedStringArray:
	return EXTENSIONS

func _get_resource_type(_path: String) -> String:
	return "Texture2D"

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
	return type == &"Texture2D"

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := img.load_ktx_from_buffer(bytes)
	if err != OK:
		push_warning("[RuntimeKTXLoader] no pude cargar %s (err %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(img)
