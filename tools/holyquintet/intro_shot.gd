extends Node
# Captures HQIntro at: mid intro_start video, and mid wish-prompt (after the
# video ends, glow+rings+yes/no faded in).
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/intro_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/intro/intro_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(2.0).timeout
	await _shoot("intro_video_playing.png")

	# Skip most of the intro video by forcing it to end early via seek, rather
	# than waiting the full real-time duration. intro_start.ogv is Theora
	# with real motion interpolation (mpdecimate+minterpolate), which loses
	# ~0.8s off the true 12.68s source right at its end (a static held pose,
	# confirmed harmless) — seeking past its ~11.9s actual playable length
	# lands on undefined/wrong content instead of clamping, so keep this
	# comfortably under that.
	screen.intro_video.stream_position = 11.5
	await get_tree().create_timer(0.5).timeout
	await _shoot("intro_prompt_fadein.png")

	await get_tree().create_timer(1.5).timeout
	await _shoot("intro_prompt_settled.png")

	print("INTRO_SHOT: saved")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
	print("INTRO_SHOT: saved ", filename)
