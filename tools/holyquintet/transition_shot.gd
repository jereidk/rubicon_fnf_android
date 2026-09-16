extends Node
# Captures HQTransition mid-outro (black fading in, Kyubey running in) and
# mid-intro (black fading out, Kyubey running off) against a plain
# background, so both halves of the real HQTransition.hx animation can be
# checked independently of any specific screen.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/transition_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.5, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var trans = get_node("/root/HQTransition")

	trans._play_outro()
	await get_tree().create_timer(0.35).timeout
	await _shoot("transition_outro_mid.png")

	await get_tree().create_timer(0.5).timeout

	trans._play_intro()
	await get_tree().create_timer(0.35).timeout
	await _shoot("transition_intro_mid.png")

	print("TRANSITION_SHOT: saved")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
	print("TRANSITION_SHOT: saved ", filename)
