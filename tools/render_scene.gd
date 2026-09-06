@tool
extends SceneTree

var _scene: Node
var _timer: float = 0.0
var _captured: bool = false

func _init():
	pass

func _initialize():
	var args = OS.get_cmdline_args()
	var scene_path = ""
	for i in range(args.size()):
		if args[i] == "--scene" and i + 1 < args.size():
			scene_path = args[i + 1]
		if args[i] == "--output" and i + 1 < args.size():
			pass
	
	if scene_path.is_empty():
		scene_path = "res://holyquintet_mod/menus/main/main_menu.tscn"
	
	var packed = load(scene_path)
	if packed == null:
		push_error("Failed to load: " + scene_path)
		quit(1)
		return
	
	_scene = packed.instantiate()
	root.add_child(_scene)
	
	# Set viewport size
	root.get_viewport().size = Vector2i(1920, 1080)

func _process(delta: float) -> bool:
	_timer += delta
	if _timer > 3.0 and not _captured:
		_captured = true
		var image = root.get_viewport().get_texture().get_image()
		image.save_png("/tmp/hq_main_menu.png")
		print("SCREENSHOT SAVED to /tmp/hq_main_menu.png")
		quit(0)
	return false
