extends Node
# Renders our port's Freeplay and Credits MainMenuSprite art (navigated to,
# not just Story at rest) to compare against real reference screenshots the
# user sent from the original mod.
const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)
	await get_tree().create_timer(0.3).timeout

	# Freeplay = index 1
	screen._change_selection(1, false)
	await get_tree().create_timer(1.0).timeout
	await _shoot("cmp_freeplay.png")

	# Credits = index 5
	screen._change_selection(4, false)  # 1 -> 5
	await get_tree().create_timer(1.0).timeout
	await _shoot("cmp_credits.png")

	print("FREEPLAY_CREDITS_COMPARE: done")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR.path_join(filename))
