extends Node

## Runs a real game scene with a real renderer and saves PNGs of it.
##
## The note in CLAUDE.md that said "Godot cannot open a window here" was true
## of the default Vulkan driver and is not true of GL Compatibility under
## Xvfb, which renders and screenshots fine:
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . \
##     --rendering-driver opengl3 res://tools/harness/scene_shot.tscn \
##     -- res://lullaby_mod/songs/chimera/sng_chimera.tscn /tmp/shots t=40 t=100
##
## Arguments after `--`: the scene, the output directory, then `w=`/`h=` for
## the window to emulate (1600x720 is the moto g53) and any number of `t=`
## song positions. It prints the window, the base resolution and the
## content-scale settings first, so a screenshot can be measured against the
## geometry that produced it instead of guessed at.
##
## `get_viewport().get_texture()` gives the CONTENT rect, not the window - at
## 1600x720 with aspect KEEP that is 1280x720, already free of the pillarbox.
## Measurements off these PNGs are in that frame.
##
## Software GL runs this at a frame every few seconds and does not light the
## scene the way a device does, so it answers "what is on screen and where",
## never "what does it cost". For a visibility question prefer scene_probe.gd,
## which answers the same thing headless in seconds.
##
## The whole project loads, autoloads included, so this is not the stub-project
## technique - it is the game. What it needs is a complete import: a checkout
## whose `.godot/imported` is missing anything the scene reaches fails at load
## with "referenced non-existent resource" rather than rendering.
##
## Run the import in a COPY of the checkout. `--import` rewrites the `uid=`
## line of the `.import` files it touches, and a changed UID is exactly the
## class of change that has broken this repo before.
var _scene_path: String = "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
var _out: String = "/tmp/shots"
var _w: int = 1600
var _h: int = 720
var _at: Array[float] = []

func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() > 0: _scene_path = argv[0]
	if argv.size() > 1: _out = argv[1]
	for i in range(2, argv.size()):
		var a: String = argv[i]
		if a.begins_with("w="): _w = int(a.substr(2))
		elif a.begins_with("h="): _h = int(a.substr(2))
		elif a.begins_with("t="): _at.append(float(a.substr(2)))

	var win: Window = get_window()
	win.size = Vector2i(_w, _h)
	print("OUT ventana=%s base=%dx%d aspect=%d modo=%d" % [
		win.size, ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
		win.content_scale_aspect, win.content_scale_mode])

	var scene: Node = (load(_scene_path) as PackedScene).instantiate()
	add_child(scene)
	_silence_gameover(scene)
	for _i in 3: await get_tree().process_frame
	print("OUT instanciada, nodos ok")

	var clock: AnimationPlayer = _find_timeline(scene)
	if clock == null:
		print("OUT sin linea de tiempo")
		get_tree().quit(1); return
	clock.play(&"scene")

	var done: float = 0.0
	for target in _at:
		while done < target:
			clock.advance(1.0 / 60.0)
			done += 1.0 / 60.0
		_pin_health(scene)
		# Enough drawn frames for the first-draw pipeline compilations to be
		# paid before the one that gets saved.
		for _i in 4:
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s/t%03d.png" % [_out, int(target)]
		img.save_png(path)
		print("OUT scene@%.2fs -> %s (%dx%d)" % [
			clock.current_animation_position, path, img.get_width(), img.get_height()])
	print("OUT listo")
	get_tree().quit()

func _find_timeline(scene: Node) -> AnimationPlayer:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var p := node as AnimationPlayer
		if p != null and p.has_animation(&"scene"): return p
		for child in node.get_children(): stack.append(child)
	return null

## Nobody is playing, so health drains to zero and Chimera's LowerHealthRect -
## a full-screen black ColorRect that draws under the notes - goes fully opaque
## and every shot is of that instead of the song.
func _pin_health(scene: Node) -> void:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if "max_health" in node and "health" in node:
			node.set("health", node.get("max_health"))
		for child in node.get_children(): stack.append(child)

func _silence_gameover(scene: Node) -> void:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script() as Script
		if script != null and "gameover" in script.resource_path.to_lower():
			node.process_mode = Node.PROCESS_MODE_DISABLED
		for child in node.get_children(): stack.append(child)
