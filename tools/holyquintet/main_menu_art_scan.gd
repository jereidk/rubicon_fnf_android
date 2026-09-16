extends Node
# Diagnostic: forces the Story MainMenuSprite to specific frames (bypassing
# the start/loop tween entirely) and screenshots each, to find out whether
# ANY frame in its 0-179 range matches the user's real reference screenshot
# (a huge, fully-visible cast illustration dominating the left-center of the
# screen) — my start/loop tween render only ever showed a small sliver in
# the bottom-right corner, so this checks whether that's a genuine bug
# (wrong position/scale/anchor) or just a timing issue in my tween capture.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/main_menu_art_scan.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)
	await get_tree().process_frame

	var story: Node = screen._graphics[0]
	story.hide_art()  # kill the running tween so we control frame directly
	story.visible = true

	for f in [0, 20, 40, 59, 60, 80, 100, 120, 140, 160, 179]:
		story.frame = f
		await get_tree().process_frame
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(SHOT_DIR + "/art_scan_f%03d.png" % f)
		print("ART_SCAN: frame=", f, " actual=", story.frame)

	print("ART_SCAN: done")
	get_tree().quit()
