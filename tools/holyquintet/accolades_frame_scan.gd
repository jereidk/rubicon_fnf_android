extends Node
const SHOT_DIR := "/tmp/hq_renders"
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)
	await get_tree().process_frame

	var g = screen._graphics[3]  # accolades
	g.hide_art()
	g.visible = true

	for f in [0, 15, 30, 45, 59, 60, 90, 120, 150, 179]:
		g.frame = f
		await get_tree().process_frame
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(SHOT_DIR + "/acc_scan_f%03d.png" % f)

	print("ACC_SCAN: done")
	get_tree().quit()
