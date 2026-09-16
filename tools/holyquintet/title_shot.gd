extends Node
# Captures HQTitle at: mid star-zoom intro (camera zoomed/rotated in,
# glow building), right after showTitle() reveals the logo/keyart, and
# idle a bit later with the press-start text blinking in and the
# backdrops scrolling.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/title_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/title/title_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	# create()'s 1.0s timer, then well into startIntro()'s 1.75s zoom.
	await get_tree().create_timer(2.0).timeout
	await _shoot("title_zoom_intro.png")

	# start1Sound duration determines when showTitle() fires; wait generously.
	await get_tree().create_timer(3.0).timeout
	await _shoot("title_revealed.png")

	# press start text fades in 1.5s after showTitle(), zoom settles at 1.5s too.
	await get_tree().create_timer(2.0).timeout
	await _shoot("title_idle.png")

	print("TITLE_SHOT: saved")
	get_tree().quit()


func _shoot(filename: String) -> void:
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/" + filename)
	print("TITLE_SHOT: saved ", filename)
