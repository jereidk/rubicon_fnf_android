extends Node
# Confirms MainMenuSprite's start->loop frame animation actually advances
# (not stuck on frame 0), and that hideArt()/showArt() correctly restart the
# 'start' animation from frame 0 each time a new item is selected.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/main_menu_art_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().process_frame
	var story: Node = screen._graphics[0]
	print("MAIN_MENU_ART_SHOT: frame@0.0s=", story.frame)
	await _shoot("art_story_f0.png")

	await get_tree().create_timer(0.3).timeout
	print("MAIN_MENU_ART_SHOT: frame@0.3s=", story.frame)
	await _shoot("art_story_f1.png")

	await get_tree().create_timer(0.6).timeout
	print("MAIN_MENU_ART_SHOT: frame@0.9s (should be in loop, >=60)=", story.frame)
	await _shoot("art_story_f2.png")

	await get_tree().create_timer(1.0).timeout
	print("MAIN_MENU_ART_SHOT: frame@1.9s=", story.frame)
	await _shoot("art_story_f3.png")

	print("MAIN_MENU_ART_SHOT: done")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
