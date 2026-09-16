extends Node
# Verifies the Destroy Save Data confirm dialog renders (never confirms it).
const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/settings/settings_screen.tscn")
	var screen: Control = scene.instantiate()
	add_child(screen)
	await get_tree().create_timer(0.3).timeout

	# Jump straight to "Other" (index 4) and confirm.
	screen.sm_cur_sel = 4
	screen._change_selection(0)
	await get_tree().process_frame
	_press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	print("DELETE_SHOT: in_sub_menu=", screen.in_sub_menu, " sm_cur_cat=", screen.sm_cur_cat)
	await _shoot("delete_t0_other_open.png")

	# Move to "Destroy Save Data" (index 1) and confirm.
	_press(KEY_DOWN)
	await get_tree().create_timer(0.2).timeout
	_press(KEY_ENTER)
	await get_tree().create_timer(0.4).timeout
	await _shoot("delete_t1_confirm_dialog.png")
	print("DELETE_SHOT: message_window valid=", is_instance_valid(screen.message_window))

	# Cancel it (left/No), verify it closes and nothing was erased.
	_press(KEY_LEFT)
	await get_tree().create_timer(0.3).timeout
	print("DELETE_SHOT: message_window._selected after LEFT=", screen.message_window._selected if is_instance_valid(screen.message_window) else "N/A")
	_press(KEY_ENTER)
	await get_tree().create_timer(2.0).timeout
	print("DELETE_SHOT: message_window valid after cancel=", is_instance_valid(screen.message_window))
	print("DELETE_SHOT: save file still exists=", FileAccess.file_exists("user://hq_save.json"))
	await _shoot("delete_t2_cancelled.png")

	print("DELETE_SHOT: done")
	get_tree().quit()


func _press(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR.path_join(filename))
