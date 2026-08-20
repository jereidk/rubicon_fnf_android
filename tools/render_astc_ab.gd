extends SceneTree

## Renders an original PNG next to its ASTC-compressed self, so a compression
## decision can be looked at instead of inferred from a PSNR.
##
## measure_astc_quality.gd answers "how far off is it"; this answers "does it
## look broken". Both are needed, because the numbers mislead in both
## directions here: settings_icons.png averages 40.9 dB and still swings
## individual pixels by 186/255, while an opaque background scores badly on
## detail nobody can see.
##
## Three things it has to do or the picture lies:
##
## - **Composite over a background.** Nearly all of this art is hard-edged
##   cutout and ASTC 8x8 fringes every boundary, so the damage is in the alpha
##   channel. Drawn on transparency it is invisible; drawn over grey it is the
##   whole story. The checkerboard is what a fringe reads against.
## - **Show the alpha channel on its own.** A fringe that survives compositing
##   still has to be told apart from a colour shift.
## - **Crop to the worst block, at 1:1.** A 936x2174 sheet scaled to fit hides
##   an 8x8 artefact completely. The strip finds the block with the largest
##   channel error and shows it unscaled.
##
##   godot --headless --script tools/render_astc_ab.gd -- <png> [out.png] [4x4|8x8]

const PANEL := 420
const CROP := 96


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("OUT usage: -- <png> [out.png] [4x4|8x8]")
		quit()
		return

	var src_path: String = args[0]
	var out_path: String = args[1] if args.size() > 1 else "res://astc_ab.png"
	var block: String = args[2] if args.size() > 2 else "8x8"

	var src := Image.load_from_file(src_path)
	if src == null:
		print("OUT cannot load ", src_path)
		quit()
		return
	src.convert(Image.FORMAT_RGBA8)

	var fmt := Image.ASTC_FORMAT_4x4 if block == "4x4" else Image.ASTC_FORMAT_8x8
	var astc := src.duplicate() as Image
	if astc.compress(Image.COMPRESS_ASTC, Image.COMPRESS_SOURCE_GENERIC, fmt) != OK:
		print("OUT compress failed")
		quit()
		return
	astc.decompress()
	astc.convert(Image.FORMAT_RGBA8)

	var worst := _worst_block(src, astc)
	var sheet := _build(src, astc, worst, src_path.get_file(), block)
	sheet.save_png(out_path)
	print("OUT %s -> %s  (%dx%d, peor bloque en %d,%d)"
		% [src_path.get_file(), out_path, src.get_width(), src.get_height(), worst.x, worst.y])
	quit()


## Where the largest single-channel error is, so the 1:1 crop lands on it
## rather than on whatever happens to be in the middle of the sheet.
func _worst_block(a: Image, b: Image) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_err: float = -1.0
	var step: int = maxi(1, int(a.get_width() / 220))
	for y in range(0, a.get_height(), step):
		for x in range(0, a.get_width(), step):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			var err: float = maxf(maxf(absf(pa.r - pb.r), absf(pa.g - pb.g)),
				maxf(absf(pa.b - pb.b), absf(pa.a - pb.a)))
			if err > best_err:
				best_err = err
				best = Vector2i(x, y)
	return best


func _build(src: Image, astc: Image, worst: Vector2i, title: String, block: String) -> Image:
	var cols: int = 3
	var sheet := Image.create(PANEL * cols, PANEL * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.09, 0.11, 1.0))

	# Fila 1: la hoja entera, original / ASTC / alfa del ASTC.
	_blit_fit(sheet, _over_checker(src), Vector2i(0, 0))
	_blit_fit(sheet, _over_checker(astc), Vector2i(PANEL, 0))
	_blit_fit(sheet, _alpha_only(astc), Vector2i(PANEL * 2, 0))

	# Fila 2: el peor bloque a 1:1, original / ASTC / diferencia amplificada.
	var c_src := _crop(src, worst)
	var c_astc := _crop(astc, worst)
	_blit_fit(sheet, _over_checker(c_src), Vector2i(0, PANEL))
	_blit_fit(sheet, _over_checker(c_astc), Vector2i(PANEL, PANEL))
	_blit_fit(sheet, _diff(c_src, c_astc), Vector2i(PANEL * 2, PANEL))

	print("OUT paneles: [hoja original | hoja ASTC %s | alfa ASTC] / [crop 1:1 original | crop ASTC | diferencia x4]  %s"
		% [block, title])
	return sheet


## The checkerboard is the point: a cutout's fringe is an alpha error, and
## alpha errors are invisible against transparency.
func _over_checker(img: Image) -> Image:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var square: int = maxi(4, int(maxi(w, h) / 24))
	for y in h:
		for x in w:
			var light: bool = ((x / square) + (y / square)) % 2 == 0
			var bg := Color(0.62, 0.62, 0.64, 1.0) if light else Color(0.40, 0.40, 0.43, 1.0)
			var p := img.get_pixel(x, y)
			out.set_pixel(x, y, bg.lerp(Color(p.r, p.g, p.b, 1.0), p.a))
	return out


func _alpha_only(img: Image) -> Image:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var a: float = img.get_pixel(x, y).a
			out.set_pixel(x, y, Color(a, a, a, 1.0))
	return out


func _diff(a: Image, b: Image) -> Image:
	var w: int = a.get_width()
	var h: int = a.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			# x4 so a 30/255 error is visible; alpha error goes in red because
			# that is the channel this compression breaks.
			var da: float = clampf(absf(pa.a - pb.a) * 4.0, 0.0, 1.0)
			var dc: float = clampf(maxf(maxf(absf(pa.r - pb.r), absf(pa.g - pb.g)),
				absf(pa.b - pb.b)) * 4.0, 0.0, 1.0)
			out.set_pixel(x, y, Color(da, dc, dc * 0.5, 1.0))
	return out


func _crop(img: Image, centre: Vector2i) -> Image:
	var x: int = clampi(centre.x - CROP / 2, 0, maxi(0, img.get_width() - CROP))
	var y: int = clampi(centre.y - CROP / 2, 0, maxi(0, img.get_height() - CROP))
	var w: int = mini(CROP, img.get_width())
	var h: int = mini(CROP, img.get_height())
	return img.get_region(Rect2i(x, y, w, h))


func _blit_fit(sheet: Image, img: Image, at: Vector2i) -> void:
	var pad: int = 10
	var box: int = PANEL - pad * 2
	var scale: float = minf(float(box) / float(img.get_width()), float(box) / float(img.get_height()))
	var w: int = maxi(1, int(img.get_width() * scale))
	var h: int = maxi(1, int(img.get_height() * scale))
	var scaled := img.duplicate() as Image
	# NEAREST on the 1:1 crops, so an 8x8 block stays a block instead of being
	# smoothed into looking fine.
	scaled.resize(w, h, Image.INTERPOLATE_NEAREST if img.get_width() <= CROP else Image.INTERPOLATE_LANCZOS)
	sheet.blit_rect(scaled, Rect2i(0, 0, w, h),
		at + Vector2i(pad + (box - w) / 2, pad + (box - h) / 2))
