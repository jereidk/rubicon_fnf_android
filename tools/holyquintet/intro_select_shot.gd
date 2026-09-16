extends Node
const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/intro/intro_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	screen.intro_video.stream_position = 12.5
	await get_tree().create_timer(3.0).timeout
	print("BEFORE: can_control=", screen.can_control, " selecting_yes=", screen.selecting_yes,
		" has_moved=", screen.has_moved, " yes_alpha=", screen.yes_sprite.modulate.a,
		" no_alpha=", screen.no_sprite.modulate.a)

	# Input.action_press() only affects polling APIs (is_action_pressed),
	# not _unhandled_input — feed a real InputEventKey to exercise the
	# actual event-driven path the real game uses.
	var key_down := InputEventKey.new()
	key_down.keycode = KEY_RIGHT
	key_down.pressed = true
	Input.parse_input_event(key_down)
	await get_tree().process_frame

	var key_up := InputEventKey.new()
	key_up.keycode = KEY_RIGHT
	key_up.pressed = false
	Input.parse_input_event(key_up)
	await get_tree().create_timer(0.6).timeout
	print("AFTER: can_control=", screen.can_control, " selecting_yes=", screen.selecting_yes,
		" has_moved=", screen.has_moved, " yes_alpha=", screen.yes_sprite.modulate.a,
		" no_alpha=", screen.no_sprite.modulate.a, " yes_scale=", screen.yes_sprite.scale)
	await _shoot("intro_select_yes.png")

	print("INTRO_SELECT_SHOT: saved")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
