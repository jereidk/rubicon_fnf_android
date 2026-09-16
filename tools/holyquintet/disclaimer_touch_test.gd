extends Node
# Verifies disclaimer.gd's tap-to-accept path (InputEventScreenTouch routed
# through _unhandled_input) actually fires _accept(), not just that it
# parses — a real touch anywhere on screen, no keyboard at all.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/disclaimer_touch_test.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/disclaimer/disclaimer.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	# wait_timer is 2.0s; must be past it for the tap to do anything.
	await get_tree().create_timer(2.2).timeout

	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = Vector2(960, 540)
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = Vector2(960, 540)
	Input.parse_input_event(up)
	await get_tree().process_frame

	await get_tree().create_timer(0.3).timeout
	print("DISCLAIMER_TOUCH_TEST: accepted=", screen.accepted)
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/disclaimer_touch_test.png")
	print("DISCLAIMER_TOUCH_TEST: saved (should be mid fade-to-black)")
	get_tree().quit()
