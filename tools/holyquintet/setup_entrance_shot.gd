extends Node
# Captures the entrance sequence at several timepoints: right after open
# (dim+slide+icon mid-drop), after the icon's first glowPulse, and (after
# selecting Yes into step 2, a 'danger' icon) mid-way through its repeating
# 2.5s pulse.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/setup_entrance_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/setup/setup_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.15).timeout
	await _shoot("entrance_t015.png")

	await get_tree().create_timer(0.55).timeout  # t=0.7, just after icon settles + first glow spawns
	await _shoot("entrance_t070.png")

	# Move into step 2 (Keep Flashing Lights, icon='danger') to check the loop.
	# Real InputEventKey, not Input.action_press(): hq_message_window.gd
	# reads input via _unhandled_input now, which action_press() can't reach.
	await _press(KEY_RIGHT)
	await _press(KEY_ENTER)

	await get_tree().create_timer(3.0).timeout  # first loop pulse fires at settle+2.5s
	await _shoot("entrance_danger_loop.png")

	print("ENTRANCE_SHOT: all saved")
	get_tree().quit()


func _press(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
	print("ENTRANCE_SHOT: saved ", filename)
