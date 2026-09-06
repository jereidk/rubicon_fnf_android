extends SceneTree

var _scene: Node
var _timer: float = 0.0
var _captured: bool = false

func _initialize() -> void:
	var scene_path := "res://holyquintet_mod/menus/main/main_menu.tscn"
	
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		push_error("Cannot load scene: " + scene_path)
		quit(1)
		return
	
	root.size = Vector2i(1920, 1080)
	root.transparent_bg = false
	
	_scene = packed.instantiate()
	root.add_child(_scene)
	print("Scene loaded: " + scene_path)

func _process(delta: float) -> bool:
	_timer += delta
	if _timer > 4.0 and not _captured:
		_captured = true
		var image := root.get_texture().get_image()
		if image:
			image.save_png("/tmp/hq_main_menu.png")
			print("SCREENSHOT SAVED to /tmp/hq_main_menu.png")
		else:
			print("ERROR: could not get image from viewport")
		quit(0)
	return false
