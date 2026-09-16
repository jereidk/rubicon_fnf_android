extends Node
func _ready() -> void:
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)
	await get_tree().create_timer(0.3).timeout

	for i in screen._graphics.size():
		var g = screen._graphics[i]
		var atlas: AdobeAtlas = g.atlases[0]
		var t: Transform2D = atlas.stage_transform
		print(g.item, " full_transform=", t, " scale=", t.get_scale(), " rot=", t.get_rotation())

	print("STAGE_DUMP: done")
	get_tree().quit()
