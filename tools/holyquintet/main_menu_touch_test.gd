extends Node
# Verifies tapping a menu button directly selects+confirms it (Settings,
# since it needs no story-diff/message-window follow-up to observe the
# scene-switch cleanly).
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/main_menu_touch_test.tscn

func _ready() -> void:
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.5).timeout
	# Freeplay (index 1) sits on-screen at rest (y=425) — unlike Settings
	# (index 6, y=1175, off-screen until scrolled into view), so a tap can
	# actually land on it without first navigating there by keyboard.
	var freeplay_btn = screen.get_node("MenuButtons").get_child(2)  # 0:btn0 1:badge0 2:btn1
	print("MAIN_MENU_TOUCH_TEST: node=", freeplay_btn.name, " id=", freeplay_btn.id)
	var center: Vector2 = freeplay_btn.global_position + Vector2(225, 70)
	var xform: Transform2D = screen.get_viewport().get_final_transform()
	var click_pos: Vector2 = xform * center

	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = click_pos
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = click_pos
	Input.parse_input_event(up)
	await get_tree().process_frame

	await get_tree().create_timer(0.3).timeout
	print("MAIN_MENU_TOUCH_TEST: mm_cur_sel=", screen.mm_cur_sel, " can_control=", screen._can_control)
	print("MAIN_MENU_TOUCH_TEST: done")
	get_tree().quit()
