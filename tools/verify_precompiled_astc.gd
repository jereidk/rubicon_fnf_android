extends SceneTree

## Checks that every .res in precompiled_astc_imports/ really is the compiled
## form of the source PNG its .md5 sidecar claims.
##
## This matters because of how the workflow uses these files. Godot decides
## whether to skip reimporting by comparing the current source's MD5 against
## source_md5 in the sidecar - so a sidecar written against the current PNG
## makes Godot trust the .res next to it, whatever that .res actually
## contains. Get the pairing wrong and the build silently ships the wrong
## texture, with nothing in the log to say so.
##
## Dimensions are the check that catches the failure that can actually
## happen here: an atlas sheet repacked to a different layout, whose old
## compiled output still carries the old sheet's size.
##
## Run with:
##   godot --headless --path . --script tools/verify_precompiled_astc.gd

const DIR := "res://precompiled_astc_imports"

var _checked: int = 0
var _failures: int = 0
var _skipped: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# source_md5 identifies the PNG, but not where it lives, so build a
	# basename -> path index of every source the two ASTC importers own.
	var by_name: Dictionary = {}
	_index_sources("res://", by_name)

	var dir := DirAccess.open(DIR)
	if dir == null:
		print("FALLO: no pude abrir %s" % DIR)
		quit(1)
		return

	for file: String in dir.get_files():
		if not file.ends_with(".res"):
			continue
		_check(file, by_name)

	print("")
	print("comprobados %d, saltados %d, fallos %d" % [_checked, _skipped.size(), _failures])
	for name: String in _skipped:
		print("  saltado (sin fuente en el arbol): %s" % name)
	if _failures == 0:
		print("todo OK - cada .res coincide en tamano con su PNG")
	quit(0 if _failures == 0 else 1)

func _index_sources(path: String, out: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_index_sources(path.path_join(sub), out)

	for file: String in dir.get_files():
		if file.ends_with(".png"):
			out[file] = path.path_join(file)

func _check(res_file: String, by_name: Dictionary) -> void:
	var base: String = res_file.substr(0, res_file.length() - 4)
	# "foo.png-<hash>" -> "foo.png"
	var dash: int = base.rfind("-")
	if dash == -1:
		_fail(res_file, "el nombre no tiene la forma fuente.png-hash")
		return

	var png_name: String = base.substr(0, dash)
	if not by_name.has(png_name):
		_skipped.append(res_file)
		return

	var png_path: String = by_name[png_name]

	var md5_path: String = DIR.path_join(base + ".md5")
	if not FileAccess.file_exists(md5_path):
		_fail(res_file, "no tiene .md5 al lado")
		return

	# The sidecar has to describe the PNG that is in the tree right now,
	# otherwise Godot reimports and the .res was pointless.
	var sidecar: String = FileAccess.get_file_as_string(md5_path)
	var claimed: String = ""
	for line: String in sidecar.split("\n"):
		if line.begins_with("source_md5="):
			claimed = line.get_slice("\"", 1)
	var actual: String = FileAccess.get_md5(png_path)
	if claimed != actual:
		_fail(res_file, "source_md5 no es el del PNG actual\n          sidecar %s\n          real    %s" % [claimed, actual])
		return

	var image := Image.load_from_file(png_path)
	if image == null:
		_fail(res_file, "no pude leer el PNG %s" % png_path)
		return

	var texture: Resource = ResourceLoader.load(DIR.path_join(res_file))
	if texture == null or not (texture is Texture2D):
		_fail(res_file, "el .res no carga como Texture2D")
		return

	var got := Vector2i(texture.get_width(), texture.get_height())
	var want := Vector2i(image.get_width(), image.get_height())
	_checked += 1
	if got != want:
		_fail(res_file, "tamano %s, el PNG es %s" % [got, want])
		return

	print("  ok    %-52s %s" % [png_name, got])

func _fail(res_file: String, why: String) -> void:
	_failures += 1
	print("  FALLO %s\n          %s" % [res_file, why])
