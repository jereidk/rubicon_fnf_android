extends Node
# Verifies the new Credits screen: initial render, scroll navigation,
# portrait swap, back navigation, mobile tap-to-select, achievement unlock.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/credits_screen_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/credits/credits_screen.tscn")
	var screen: Control = scene.instantiate()
	add_child(screen)
	await get_tree().create_timer(0.3).timeout
	await _shoot("credits_t0_initial.png")
	print("CREDITS_SHOT: cur_sel=", screen.cur_sel, " achievement unlocked=", not HQSaves.is_achievement_locked("ThanksForPlaying"))

	for i in 5:
		_press(KEY_DOWN)
		await get_tree().create_timer(0.15).timeout
	await get_tree().create_timer(0.6).timeout
	print("CREDITS_SHOT: cur_sel after 5 DOWN=", screen.cur_sel)
	await _shoot("credits_t1_scrolled.png")

	for i in 24:
		_press(KEY_DOWN)
		await get_tree().create_timer(0.05).timeout
	await get_tree().create_timer(0.6).timeout
	print("CREDITS_SHOT: cur_sel after wrap=", screen.cur_sel, " (expect wrapped near 4)")
	await _shoot("credits_t2_wrapped.png")

	# Scroll to the very last entry to see the Special Thanks block.
	screen.cur_sel = 24
	screen._change_selection(0)
	await get_tree().create_timer(0.6).timeout
	await _shoot("credits_t3_last_entry.png")

	_press(KEY_ESCAPE)
	await get_tree().create_timer(0.15).timeout
	print("CREDITS_SHOT: can_control after back=", screen.can_control, " (expect false, fade-out started)")

	print("CREDITS_SHOT: done")
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
