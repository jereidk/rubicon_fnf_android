extends Node
# Selects the "Yes" button (ui_right) and waits mid-pulse to capture the
# button_highlight-basic.png glow ring that ButtonUI.set_selected() loops
# while a button is selected.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/setup_highlight_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/setup/setup_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.6).timeout

	Input.action_press("ui_right")
	await get_tree().process_frame
	Input.action_release("ui_right")

	# Mid-way through the 1.0s grow+fade half of the pulse cycle.
	await get_tree().create_timer(0.4).timeout

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/setup_highlight_shot.png")
	print("SETUP_HIGHLIGHT_SHOT: saved")
	get_tree().quit()
