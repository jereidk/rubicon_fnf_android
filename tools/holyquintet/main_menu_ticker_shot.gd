extends Node
# Verifies the real live-fetched news ticker: HTTPRequest to the mod
# author's Google Doc, parsed the same way as global.hx's HttpUtil-based
# fetch, then scrolled if it overflows the 1275px clip.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/main_menu_ticker_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	for t in [1.0, 3.0, 5.0, 8.0]:
		await get_tree().create_timer(t).timeout
		print("TICKER_SHOT: t=", t, " text='", screen.ticker_txt.text, "' pos.x=", screen.ticker_txt.position.x)
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(SHOT_DIR + "/ticker_t%02d.png" % int(t))

	print("TICKER_SHOT: done")
	get_tree().quit()
