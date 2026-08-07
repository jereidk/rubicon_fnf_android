extends SceneTree

## Loads the same texture from the pck and from the port and compares the
## dimensions and pixels. gdanimate slices its spritemaps with regions taken
## from spritemap*.json in exact source pixels, so a spritemap that came out of
## the importer at even a slightly different size draws every frame off by a
## few pixels - which reads as "the character is standing in the wrong place",
## not as a broken texture.
##
##   godot --headless --script tools/diff_pck_texture.gd -- <pc_path> <port_path>

const PCK := "res://lullaby_mod/original_pck/Lullaby.pck"

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("OUT usage: -- <pc_path> <port_path>")
		quit()
		return

	if not ProjectSettings.load_resource_pack(PCK, false):
		print("OUT could not mount pck")
		quit()
		return

	var pc: Texture2D = _load(args[0], "PC")
	var port: Texture2D = _load(args[1], "PORT")
	if pc == null or port == null:
		quit()
		return

	if pc.get_size() != port.get_size():
		print("OUT SIZE MISMATCH pc=", pc.get_size(), " port=", port.get_size())
		quit()
		return

	var a: Image = pc.get_image()
	var b: Image = port.get_image()
	if a == null or b == null:
		print("OUT could not read image data pc=", a, " port=", b)
		quit()
		return

	# Compressed formats differ bit for bit between codecs even when they look
	# the same, so compare decoded pixels, and report the worst channel delta
	# rather than a pass/fail - ASTC vs whatever the PC used will never be
	# byte-identical.
	a.decompress()
	b.decompress()
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)

	var worst: float = 0.0
	var differing: int = 0
	var step: int = maxi(1, int(a.get_width() / 512))
	var samples: int = 0
	for y in range(0, a.get_height(), step):
		for x in range(0, a.get_width(), step):
			samples += 1
			var pa: Color = a.get_pixel(x, y)
			var pb: Color = b.get_pixel(x, y)
			var d: float = maxf(maxf(absf(pa.r - pb.r), absf(pa.g - pb.g)),
				maxf(absf(pa.b - pb.b), absf(pa.a - pb.a)))
			if d > 0.02:
				differing += 1
			worst = maxf(worst, d)

	print("OUT size=", a.get_size(), " sampled=", samples,
		" differing=", differing, " worst_delta=", "%.4f" % worst)
	quit()

func _load(path: String, tag: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		print("OUT ", tag, " missing: ", path)
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		print("OUT ", tag, " not a Texture2D: ", path)
		return null
	print("OUT ", tag, " ", path, " size=", tex.get_size(), " class=", tex.get_class())
	return tex
