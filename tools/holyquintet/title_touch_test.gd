extends Node
# Verifies title_screen.gd's tap-to-continue path (InputEventScreenTouch
# routed through _unhandled_input) actually fires _go_into_menu() once
# can_continue is true — no keyboard at all.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/title_touch_test.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/title/title_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	# 1.0s create() timer + intro + showTitle()'s 1.5s zoom-settle before
	# can_continue flips true; wait generously past that.
	await get_tree().create_timer(6.0).timeout
	print("TITLE_TOUCH_TEST: can_continue=", screen._can_continue, " before tap")

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
	print("TITLE_TOUCH_TEST: transitioning=", screen._transitioning)
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/title_touch_test.png")
	print("TITLE_TOUCH_TEST: saved")
	get_tree().quit()
