extends Node
# Captures HQDisclaimer mid fade-in (real background + text visible) and,
# after accepting, mid fade-to-black.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/disclaimer_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/disclaimer/disclaimer.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(1.5).timeout
	await _shoot("disclaimer_settled.png")

	# wait_timer is 2.0s; make sure we're past it, then accept.
	await get_tree().create_timer(1.0).timeout
	var down := InputEventKey.new()
	down.keycode = KEY_ENTER
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = KEY_ENTER
	up.pressed = false
	Input.parse_input_event(up)

	await get_tree().create_timer(0.4).timeout
	await _shoot("disclaimer_fadeout.png")

	print("DISCLAIMER_SHOT: saved")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
	print("DISCLAIMER_SHOT: saved ", filename)
