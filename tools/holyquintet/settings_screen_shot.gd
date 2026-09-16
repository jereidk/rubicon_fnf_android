extends Node
# Verifies the new Settings screen: category select, entering a category,
# toggling a bool, adjusting an int/float, back navigation.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/settings_screen_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/settings/settings_screen.tscn")
	var screen: Control = scene.instantiate()
	add_child(screen)
	await get_tree().create_timer(0.3).timeout
	await _shoot("settings_t0_categories.png")

	# Move to Gameplay (index 1), confirm.
	_press(KEY_DOWN)
	await get_tree().create_timer(0.2).timeout
	_press(KEY_ENTER)
	await get_tree().create_timer(0.3).timeout
	await _shoot("settings_t1_gameplay_open.png")
	print("SETTINGS_SHOT: in_sub_menu=", screen.in_sub_menu, " sm_cur_cat=", screen.sm_cur_cat)

	# Toggle Downscroll (first row).
	_press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	print("SETTINGS_SHOT: downscroll=", HQOptions.downscroll)
	await _shoot("settings_t2_downscroll_on.png")

	# Move down to Strum Underlay Alpha (index 2) and increase it.
	_press(KEY_DOWN)
	await get_tree().create_timer(0.1).timeout
	_press(KEY_DOWN)
	await get_tree().create_timer(0.1).timeout
	_press(KEY_RIGHT)
	_press(KEY_RIGHT)
	_press(KEY_RIGHT)
	await get_tree().create_timer(0.2).timeout
	print("SETTINGS_SHOT: strum_underlay_alpha=", HQOptions.strum_underlay_alpha)
	await _shoot("settings_t3_int_adjusted.png")

	# Scroll down to the bottom of the gameplay list (11 items) to check scroll.
	for i in 8:
		_press(KEY_DOWN)
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.4).timeout
	await _shoot("settings_t4_scrolled.png")
	print("SETTINGS_SHOT: sm_sub_sel=", screen.sm_sub_sel)

	# Back out of the category, then back to main-category select, check state.
	_press(KEY_ESCAPE)
	await get_tree().create_timer(0.3).timeout
	print("SETTINGS_SHOT: in_sub_menu after 1 back=", screen.in_sub_menu)
	await _shoot("settings_t5_back_to_categories.png")

	# Go to Language category, select Spanish.
	_press(KEY_DOWN)
	await get_tree().create_timer(0.1).timeout
	_press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	_press(KEY_DOWN)
	await get_tree().create_timer(0.1).timeout
	_press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	print("SETTINGS_SHOT: language=", HQOptions.language)
	await _shoot("settings_t6_language.png")

	# Go to Other category, select Destroy Save Data (confirm dialog appears, don't confirm the actual wipe).
	_press(KEY_ESCAPE)
	await get_tree().create_timer(0.2).timeout
	_press(KEY_DOWN)
	await get_tree().create_timer(0.1).timeout
	_press(KEY_ENTER)
	await get_tree().create_timer(0.2).timeout
	_press(KEY_DOWN)
	await get_tree().create_timer(0.1).timeout
	_press(KEY_ENTER)
	await get_tree().create_timer(0.3).timeout
	await _shoot("settings_t7_delete_confirm.png")

	print("SETTINGS_SHOT: done")
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
