extends Node

## Runs a real game scene with a real renderer and saves PNGs of it.
##
## The note in CLAUDE.md that said "Godot cannot open a window here" was true
## of the default Vulkan driver and is not true of GL Compatibility under
## Xvfb, which renders and screenshots fine:
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . \
##     --rendering-driver opengl3 res://tools/harness/scene_shot.tscn \
##     -- res://lullaby_mod/songs/chimera/sng_chimera.tscn 3 /tmp/shots 1600 720
##
## Arguments after `--`: scene, seconds to run, output directory, and the
## window size to emulate (1600x720 is the moto g53). It prints the window,
## the base resolution and the content-scale settings first, so a screenshot
## can be measured against the geometry that produced it instead of guessed at.
##
## The whole project loads, autoloads included, so this is not the stub-project
## technique - it is the game. What it needs is a complete import: a checkout
## whose `.godot/imported` is missing anything the scene reaches will fail at
## load with "referenced non-existent resource" rather than render.
##
## Run the import in a COPY of the checkout. `--import` rewrites the `uid=`
## line of the `.import` files it touches, and a changed UID is exactly the
## class of change that has broken this repo before.
var _scene_path: String = "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
var _seconds: float = 3.0
var _out: String = "/tmp/shots"
var _w: int = 1600
var _h: int = 720

func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() > 0: _scene_path = argv[0]
	if argv.size() > 1: _seconds = float(argv[1])
	if argv.size() > 2: _out = argv[2]
	if argv.size() > 3: _w = int(argv[3])
	if argv.size() > 4: _h = int(argv[4])

	var win: Window = get_window()
	win.size = Vector2i(_w, _h)
	print("OUT ventana=%s base=%dx%d aspect=%d modo=%d" % [
		win.size, ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
		win.content_scale_aspect, win.content_scale_mode])

	print("OUT cargando ", _scene_path)
	var t0: int = Time.get_ticks_msec()
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		print("OUT FALLO al cargar")
		get_tree().quit(1)
		return
	print("OUT cargada en %dms" % (Time.get_ticks_msec() - t0))

	var inst: Node = packed.instantiate()
	add_child(inst)
	print("OUT instanciada, nodos=%d" % _count(inst))

	var elapsed: float = 0.0
	var shot: int = 0
	while elapsed < _seconds:
		await RenderingServer.frame_post_draw
		elapsed += get_process_delta_time()
		if elapsed >= float(shot) * 0.5:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("%s/t%04d.png" % [_out, int(elapsed * 1000.0)])
			shot += 1
	print("OUT listo, %d capturas" % shot)
	get_tree().quit()

func _count(n: Node) -> int:
	var c: int = 1
	for ch in n.get_children(): c += _count(ch)
	return c
