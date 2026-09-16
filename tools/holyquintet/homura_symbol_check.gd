extends Node
# Renders the nested "Story/STORY_HOMURA" symbol alone (not composited inside
# Story_Animation) at a few frames, to identify what the user's screenshot's
# close-up dark-haired character with a forehead gem/white aura actually is,
# and separately whether AdobeAtlas ever renders it at a much larger scale
# than what shows in the settled group-photo composition.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/homura_symbol_check.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)

	var atlas := AdobeAtlas.new()
	atlas.folder_path = "res://holyquintet_mod/source/images/ui/main/anim_story/"

	var node := AnimateSymbol.new()
	node.atlases = [atlas]
	node.symbol = "Story/STORY_HOMURA"
	node.centered = false
	node.position = Vector2(400, 200)
	node.scale = Vector2(1.0, 1.0)
	add_child(node)
	await get_tree().process_frame

	print("HOMURA_CHECK: length=", node.get_animation_length())

	for f in [0, 3, 6, 9]:
		node.frame = f
		await get_tree().process_frame
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(SHOT_DIR + "/homura_f%02d.png" % f)

	print("HOMURA_CHECK: done")
	get_tree().quit()
