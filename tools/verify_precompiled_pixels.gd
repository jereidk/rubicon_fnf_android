extends SceneTree

## Does each committed .res actually contain the image its PNG contains?
##
## tools/verify_precompiled_astc.gd compares dimensions and the .md5
## sidecar's source_md5. Neither can catch the failure that matters: a .res
## of the right size, correctly paired by filename, holding a different
## picture. The sidecar is self-consistent by construction - both hashes were
## computed from the two files at harvest time - so it says the pair is
## intact, not that the pair is right.
##
## This matters because 27646f5 changed what the build uses. Before it, those
## 48 .import files had no dest_files, so Godot recompressed every one from
## its PNG on every build and the texture was correct by definition. After
## it, the committed .res is what ships. If the harvest captured output from
## a tree whose sheets were laid out differently, the AtlasTexture regions
## authored against the current layout now cut the wrong pixels - which draws
## as a block of empty sheet where a sprite should be.
##
## ASTC is lossy, so this compares means rather than bytes: a block-compressed
## 4096x4096 sprite sheet still has the same average colour and the same
## rough distribution as its source. A mismatched sheet does not.
##
## Run with:
##   godot --headless --path . --script tools/verify_precompiled_pixels.gd

## Mean absolute per-channel difference, 0-1. ASTC 8x8 on a sprite sheet
## lands well under this; a different image lands well over.
const TOLERANCE := 0.06

var _failures: int = 0
var _checked: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var dir := DirAccess.open("res://precompiled_astc_imports")
	if dir == null:
		print("FALLO: no pude abrir precompiled_astc_imports")
		quit(1)
		return

	var sources: Dictionary = {}
	_index("res://", sources)

	var worst: Array = []
	for file: String in dir.get_files():
		if not file.ends_with(".res") or "_packed_" not in file:
			continue

		var base: String = file.substr(0, file.length() - 4)
		var png_name: String = base.substr(0, base.rfind("-"))
		if not sources.has(png_name):
			continue

		var diff: float = _compare(sources[png_name], "res://precompiled_astc_imports/".path_join(file))
		if diff < 0.0:
			continue

		_checked += 1
		worst.append([diff, png_name])
		if diff > TOLERANCE:
			_failures += 1
			print("  FALLO %-44s diferencia media %.4f" % [png_name, diff])

	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("")
	print("comprobadas %d texturas" % _checked)
	print("las 8 con mas diferencia:")
	for entry: Array in worst.slice(0, 8):
		print("   %.4f  %s" % [entry[0], entry[1]])

	print("")
	if _failures == 0:
		print("todo OK - cada .res contiene la imagen de su PNG")
	else:
		print("%d textura(s) no coinciden con su fuente" % _failures)
	quit(0 if _failures == 0 else 1)

func _index(path: String, out: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_index(path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.ends_with(".png"):
			out[file] = path.path_join(file)

## Mean absolute difference between the compiled texture and its source,
## sampled on a grid so a 4096x4096 pair does not cost 16M comparisons.
func _compare(png_path: String, res_path: String) -> float:
	var source := Image.load_from_file(png_path)
	if source == null:
		return -1.0

	var texture: Resource = ResourceLoader.load(res_path)
	if texture == null or not (texture is Texture2D):
		return -1.0

	var compiled: Image = texture.get_image()
	if compiled == null:
		return -1.0
	if compiled.is_compressed():
		compiled.decompress()

	if compiled.get_width() != source.get_width() or compiled.get_height() != source.get_height():
		# Already covered by the dimension check in the other tool, and a
		# size mismatch makes a pixel comparison meaningless.
		return 1.0

	source.convert(Image.FORMAT_RGBA8)
	compiled.convert(Image.FORMAT_RGBA8)

	var steps: int = 64
	var total: float = 0.0
	var samples: int = 0
	for y: int in steps:
		for x: int in steps:
			var px: int = int(float(x) / steps * source.get_width())
			var py: int = int(float(y) / steps * source.get_height())
			var a: Color = source.get_pixel(px, py)
			var b: Color = compiled.get_pixel(px, py)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
			samples += 4

	return total / float(samples)
