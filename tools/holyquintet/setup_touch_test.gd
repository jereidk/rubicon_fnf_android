extends Node
# Simulates a mouse/touch click directly on the "Yes" button (no keyboard
# input at all) to verify hq_message_window's new tap-to-select-and-confirm
# path actually advances the setup flow, not just that it parses.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/setup_touch_test.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/setup/setup_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.6).timeout

	# RightButton ("Yes") screen rect is [985,1435]x[650,789] in the LOGICAL
	# 1920x1080 canvas. The physical window can be smaller (stretch/scale),
	# so convert through the viewport's actual transform rather than assuming
	# a 1:1 pixel mapping.
	var logical_pos := Vector2(1210, 720)
	var xform: Transform2D = get_viewport().get_final_transform()
	var click_pos: Vector2 = xform * logical_pos
	print("SETUP_TOUCH_TEST: logical=", logical_pos, " -> physical=", click_pos,
		" window_size=", get_viewport().size)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = click_pos
	Input.parse_input_event(down)
	await get_tree().process_frame

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = click_pos
	Input.parse_input_event(up)
	await get_tree().process_frame

	await get_tree().create_timer(0.4).timeout

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/setup_touch_test.png")
	print("SETUP_TOUCH_TEST: saved (should show step 2, Keep Flashing Lights?)")
	get_tree().quit()
