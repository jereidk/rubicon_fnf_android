extends Node
# Verifies the mobile dev-console button (top-right keyboard icon) and the
# EditorPicker it can open: tap icon -> popup appears, type "9" -> stub
# warning (HQSHOP), type "editors" -> EditorPicker opens, navigate down,
# confirm on Wiki -> OS.shell_open (no visual change expected, but no crash),
# cancel closes it.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/dev_console_shot.gd

const SHOT_DIR := "/tmp/hq_renders"

var screen: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	screen = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.5).timeout
	await _shoot("dev_t0_rest.png")

	# Tap the dev console button (top-right icon).
	var btn: Control = screen._dev_console_btn
	var center: Vector2 = btn.global_position + btn.size * 0.5
	var xform: Transform2D = screen.get_viewport().get_final_transform()
	await _click(xform * center)
	await get_tree().create_timer(0.3).timeout
	await _shoot("dev_t1_popup_open.png")

	# Type "9" and submit.
	var input := _find_line_edit()
	if input:
		input.text = "9"
		input.text_submitted.emit("9")
	await get_tree().create_timer(0.3).timeout
	await _shoot("dev_t2_after_nine.png")
	print("DEV_CONSOLE_SHOT: after '9' code, no crash")

	# Re-open, type "editors".
	await _click(xform * center)
	await get_tree().create_timer(0.3).timeout
	input = _find_line_edit()
	if input:
		input.text = "editors"
		input.text_submitted.emit("editors")
	await get_tree().create_timer(0.3).timeout
	await _shoot("dev_t3_editor_picker_open.png")

	# Navigate down twice, screenshot highlight moving.
	_press(KEY_DOWN)
	await get_tree().create_timer(0.15).timeout
	_press(KEY_DOWN)
	await get_tree().create_timer(0.3).timeout
	await _shoot("dev_t4_editor_picker_nav.png")

	# Confirm on whatever's selected now (row 2 = "Stage Editor", a stub).
	_press(KEY_ENTER)
	await get_tree().create_timer(0.6).timeout
	await _shoot("dev_t5_editor_picker_confirm_stub.png")
	print("DEV_CONSOLE_SHOT: confirmed a stub editor, no crash")

	# Cancel/back out.
	_press(KEY_ESCAPE)
	await get_tree().create_timer(0.3).timeout
	await _shoot("dev_t6_editor_picker_closed.png")

	print("DEV_CONSOLE_SHOT: saved")
	get_tree().quit()


func _find_line_edit() -> LineEdit:
	# The popup is a direct child of get_tree().root, not of `screen`.
	for child in get_tree().root.get_children():
		if child is Control:
			var le := _find_line_edit_recursive(child)
			if le:
				return le
	return null


func _find_line_edit_recursive(node: Node) -> LineEdit:
	if node is LineEdit:
		return node
	for c in node.get_children():
		var found := _find_line_edit_recursive(c)
		if found:
			return found
	return null


func _click(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)
	await get_tree().process_frame


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
