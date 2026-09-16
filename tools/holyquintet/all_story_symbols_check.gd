extends Node
# Renders each nested per-character symbol used by Story_Animation, at its
# own last frame, to identify which one (if any) matches a mystery close-up
# character reported by the user (dark hair, forehead gem, white aura).
const SHOT_DIR := "/tmp/hq_renders"
const NAMES := ["Story/STORY_GF", "Story/STORY_SAYAKA", "Story/STORY_KYOKO", "Story/STORY_MADOKA", "Story/STORY_MAMI", "Story/STORY_HOMURA"]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var atlas := AdobeAtlas.new()
	atlas.folder_path = "res://holyquintet_mod/source/images/ui/main/anim_story/"

	for n in NAMES:
		var node := AnimateSymbol.new()
		node.atlases = [atlas]
		node.symbol = n
		node.centered = false
		node.position = Vector2(300, 200)
		add_child(node)
		await get_tree().process_frame
		var length: int = node.get_animation_length()
		node.frame = length - 1
		await get_tree().process_frame
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		var safe_name: String = n.replace("/", "_")
		image.save_png(SHOT_DIR + "/allsym_%s.png" % safe_name)
		print("ALL_STORY_SYMBOLS: ", n, " length=", length)
		node.queue_free()
		await get_tree().process_frame

	print("ALL_STORY_SYMBOLS: done")
	get_tree().quit()
