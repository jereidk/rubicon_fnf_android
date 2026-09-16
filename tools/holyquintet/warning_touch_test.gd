extends Node
# Verifies warning_screen.gd's tap-to-confirm path (added alongside the
# real keyboard-only ACCEPT, since Android has no keyboard) actually
# fires _confirm() via a real InputEventScreenTouch.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/warning_touch_test.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/warning/warning_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.3).timeout

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
	print("WARNING_TOUCH_TEST: transitioning=", screen.transitioning)
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/warning_touch_test.png")
	print("WARNING_TOUCH_TEST: saved (should show the flash starting)")
	get_tree().quit()
