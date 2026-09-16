extends Node
const SHOT_DIR := "/tmp/hq_renders/fullscan"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)
	await get_tree().process_frame

	var story: Node = screen._graphics[0]
	story.hide_art()
	story.visible = true

	for f in range(60, 180, 5):
		story.frame = f
		await get_tree().process_frame
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(SHOT_DIR + "/f%03d.png" % f)

	print("FULLSCAN: done")
	get_tree().quit()
