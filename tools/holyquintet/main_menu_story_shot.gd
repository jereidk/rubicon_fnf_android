extends Node
# Confirms Story on a fresh save (cur_story_progress == 0) opens the real
# StoryDiffUI easy/hard picker, and that selecting a side actually shows it.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/main_menu_story_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	add_child(scene.instantiate())

	await get_tree().create_timer(0.5).timeout
	await _press(KEY_ENTER)
	await get_tree().create_timer(0.6).timeout
	await _shoot("main_menu_storydiff.png")

	await _press(KEY_RIGHT)
	await get_tree().create_timer(0.6).timeout
	await _shoot("main_menu_storydiff_hard.png")

	print("MAIN_MENU_STORY_SHOT: saved")
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
	print("MAIN_MENU_STORY_SHOT: saved ", filename)
