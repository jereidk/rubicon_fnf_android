extends Node

# Renders holyquintet_mod/menus/setup/setup_screen.tscn at each of its 4
# first-time-setup steps, simulating "select Yes -> accept" between shots,
# so each can be compared against a real PC screenshot.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/setup_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/setup/setup_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.6).timeout
	await _shoot("setup_shot_step1.png")

	await _press("ui_right")
	await _press("ui_accept")
	await get_tree().create_timer(0.4).timeout
	await _shoot("setup_shot_step2.png")

	await _press("ui_right")
	await _press("ui_accept")
	await get_tree().create_timer(0.4).timeout
	await _shoot("setup_shot_step3.png")

	await _press("ui_right")
	await _press("ui_accept")
	await get_tree().create_timer(0.4).timeout
	await _shoot("setup_shot_step4.png")

	print("SETUP_SHOT: all steps saved")
	get_tree().quit()


const ACTION_KEYS := {"ui_left": KEY_LEFT, "ui_right": KEY_RIGHT, "ui_accept": KEY_ENTER}

func _press(action: String) -> void:
	# Input.action_press() only affects polling APIs (is_action_pressed) —
	# hq_message_window.gd reads input via _unhandled_input now, so this
	# must feed a real InputEventKey to be seen at all.
	var down := InputEventKey.new()
	down.keycode = ACTION_KEYS[action]
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = ACTION_KEYS[action]
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
	print("SETUP_SHOT: saved ", filename)
