extends Node

# Renders holyquintet_mod/menus/warning/warning_screen.tscn so it can be
# looked at. Run with:
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/warning_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/warning/warning_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().process_frame
	await get_tree().process_frame

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/warning_shot.png")
	print("WARNING_SHOT: saved")
	get_tree().quit()
