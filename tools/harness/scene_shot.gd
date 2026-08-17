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

## Whether to make PreloadCamera take its real path.
##
## Without this the harness does not reproduce the shipped sequence at all:
## `_ready()` reads `SceneChanger.awaiting_manual_end`, and outside a real
## scene change it is false, so the camera calls finish_preload() on the spot
## and the `precache` animation never plays. Every bug that lives in what
## precache leaves behind is invisible unless this is on.
var _precache: bool = false

## Nodes to report the on-screen rect of once the scene has settled, so a
## measurement off a screenshot has something to be compared against.
var _watch: PackedStringArray = PackedStringArray()

func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() > 0: _scene_path = argv[0]
	if argv.size() > 1: _seconds = float(argv[1])
	if argv.size() > 2: _out = argv[2]
	if argv.size() > 3: _w = int(argv[3])
	if argv.size() > 4: _h = int(argv[4])
	for i in range(5, argv.size()):
		if argv[i] == "precache":
			_precache = true
		else:
			_watch.append(argv[i])

	var win: Window = get_window()
	win.size = Vector2i(_w, _h)
	print("OUT ventana=%s base=%dx%d aspect=%d modo=%d precache=%s" % [
		win.size, ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
		win.content_scale_aspect, win.content_scale_mode, _precache])

	print("OUT cargando ", _scene_path)
	var t0: int = Time.get_ticks_msec()
	var packed: PackedScene = load(_scene_path)
	if packed == null:
		print("OUT FALLO al cargar")
		get_tree().quit(1)
		return
	print("OUT cargada en %dms" % (Time.get_ticks_msec() - t0))

	var changer: Node = get_node_or_null(^"/root/SceneChanger")
	if _precache and changer != null and "awaiting_manual_end" in changer:
		changer.set("awaiting_manual_end", true)

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

	_report(inst)
	print("OUT listo, %d capturas" % shot)
	get_tree().quit()

func _count(n: Node) -> int:
	var c: int = 1
	for ch in n.get_children(): c += _count(ch)
	return c

## Prints, for each watched node path, whether it is visible and what rect it
## occupies in window pixels.
##
## In window pixels rather than base ones on purpose. `content_scale_aspect`
## letterboxes, so a Control's own rect and the rect a screenshot shows are two
## different numbers, and every wrong guess about this scene's black graphic
## came from comparing one against the other.
func _report(scene: Node) -> void:
	if _watch.is_empty():
		return
	var xform: Transform2D = get_viewport().get_screen_transform()
	print("OUT --- nodos vigilados (pixeles de ventana) ---")
	for path in _watch:
		var node: Node = scene.get_node_or_null(NodePath(path))
		if node == null:
			print("OUT %-46s NO EXISTE" % path)
			continue
		var shown: String = "?"
		if node is CanvasItem or node is Node3D:
			shown = str(node.is_visible_in_tree())
		if node is Control:
			var r: Rect2 = xform * (node.get_global_transform() * Rect2(Vector2.ZERO, node.size))
			print("OUT %-46s visible=%-5s %dx%d en %d,%d" % [
				path, shown, roundi(r.size.x), roundi(r.size.y),
				roundi(r.position.x), roundi(r.position.y)])
		else:
			print("OUT %-46s visible=%s" % [path, shown])
