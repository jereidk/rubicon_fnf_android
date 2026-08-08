extends SceneTree

## Measures what a given ASTC block size actually does to a texture, so a
## compression change is a decision with a number behind it.
##
## The project's notes already say "always measure per texture before
## converting" - but that was about **size**. Nobody had measured **quality**,
## and the answer turns out to decide the whole question: ASTC 8x8 would cut
## this project's 510MB of Basis textures to 128MB of VRAM and shave ~75MB off
## the APK, which is by far the biggest lever anywhere in the port. It is also
## unusable on most of the art:
##
##   grass.png             18.9 dB   worst 255/255
##   hypnobald.png         23.4 dB   worst 255/255
##   rock.png              26.9 dB   worst 255/255
##   foreground_trees.png  30.4 dB   worst 255/255
##   spritemap1.png        36.0 dB   worst 255/255
##   front_trees.png       45.9 dB   worst  84/255
##   end_bg.png            51.9 dB   worst  15/255
##
## Nine of fifteen hit a 255/255 worst-case channel error. It is not detail
## loss, it is the **alpha channel**: nearly all of this art is hard-edged
## cutout - foliage, characters over transparency - and 8x8 fringes every
## boundary. end_bg.png, the one opaque background in the set, is the only
## clean result, which is the tell.
##
## Read the worst-case channel error, not the PSNR. A sharp-edged UI sheet can
## average well and still have individual pixels swing from black to white:
## settings_icons.png scores 40.9 dB at 8x8 with a worst error of 186/255.
##
##   godot --headless --script tools/measure_astc_quality.gd -- <png> [4x4|8x8]
##
## Caveat worth knowing before trusting a marginal result: this uses Godot's
## own encoder, not the EXHAUSTIVE-quality tools/astc_compress the project's
## custom importer runs. Godot's is faster and worse, so these numbers are a
## lower bound - a texture that passes here definitely passes, one that fails
## marginally might survive EXHAUSTIVE.

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("OUT usage: -- <png path> [4x4|8x8]")
		quit()
		return

	var block: String = args[1] if args.size() > 1 else "8x8"
	var src := Image.load_from_file(args[0])
	if src == null:
		print("OUT cannot load ", args[0])
		quit()
		return
	src.convert(Image.FORMAT_RGBA8)

	var fmt := Image.ASTC_FORMAT_4x4 if block == "4x4" else Image.ASTC_FORMAT_8x8
	var t := src.duplicate() as Image
	if t.compress(Image.COMPRESS_ASTC, Image.COMPRESS_SOURCE_GENERIC, fmt) != OK:
		print("OUT compress failed")
		quit()
		return

	var bytes: int = t.get_data().size()
	t.decompress()
	t.convert(Image.FORMAT_RGBA8)

	# Sampled rather than exhaustive: a few hundred rows is enough to find the
	# fringing, and a full pass over a 4096x4096 image in GDScript is minutes.
	var se: float = 0.0
	var worst: int = 0
	var worst_alpha: int = 0
	var n: int = 0
	var step: int = maxi(1, int(src.get_width() / 300))
	for y in range(0, src.get_height(), step):
		for x in range(0, src.get_width(), step):
			var pa := src.get_pixel(x, y)
			var pb := t.get_pixel(x, y)
			var channels := [[pa.r, pb.r], [pa.g, pb.g], [pa.b, pb.b], [pa.a, pb.a]]
			for i in channels.size():
				var d: float = (channels[i][0] - channels[i][1]) * 255.0
				se += d * d
				worst = maxi(worst, int(absf(d)))
				if i == 3:
					worst_alpha = maxi(worst_alpha, int(absf(d)))
				n += 1

	var mse: float = se / float(n)
	var psnr: float = 99.0 if mse <= 0.0 else 10.0 * (log(65025.0 / mse) / log(10.0))
	print("OUT %s  %s  %.1f MB  PSNR %.1f dB  worst %d/255  worst_alpha %d/255"
		% [args[0].get_file(), block, bytes / 1e6, psnr, worst, worst_alpha])
	quit()
