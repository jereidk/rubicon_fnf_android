extends Node

# Renders holyquintet_mod/menus/setup/setup_screen.tscn at its first message
# window (step 1: "Setup Settings?") so it can be compared against a real
# PC screenshot.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/setup_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/setup/setup_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.6).timeout

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/setup_shot.png")
	print("SETUP_SHOT: saved")
	get_tree().quit()
