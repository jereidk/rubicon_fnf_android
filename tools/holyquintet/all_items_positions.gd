extends Node
# Renderiza cada item del menu principal (todas las posiciones reales) para
# verificar visualmente si alguno quedo mal ubicado en el port.
const SHOT_DIR := "/tmp/hq_renders"
const ITEMS := ["story", "freeplay", "gauntlet", "accolades", "gallery", "credits", "settings", "shop"]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)
	await get_tree().create_timer(0.3).timeout

	for i in ITEMS.size():
		if i < 7:
			screen._change_selection(i - screen.mm_cur_sel, false)
		else:
			for g in screen._graphics:
				g.hide_art()
			screen._graphics[7].show_art()
		await get_tree().create_timer(3.0).timeout
		await _shoot("pos_%s.png" % ITEMS[i])

	print("ALL_ITEMS_POSITIONS: done")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT_DIR.path_join(filename))
