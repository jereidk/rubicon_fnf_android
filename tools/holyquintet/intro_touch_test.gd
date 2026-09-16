extends Node
# Verifies intro_screen.gd's tap-to-select-and-confirm path (added since
# the real HQIntro only ever had keyboard nav) actually fires _select()+
# _confirm() when tapping the Yes sprite directly, no keyboard at all.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/intro_touch_test.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/intro/intro_screen.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	# Skip most of the intro video so can_control flips true quickly: a
	# little playback left for "finished" to fire naturally, plus the
	# 0.5s/1.5s parallel fade-in tween chained after it.
	screen.intro_video.stream_position = 11.5
	var elapsed := 0.0
	while not screen.can_control and elapsed < 6.0:
		await get_tree().create_timer(0.2).timeout
		elapsed += 0.2
	print("INTRO_TOUCH_TEST: can_control=", screen.can_control, " before tap (waited ", elapsed, "s)")

	# YesSprite rect is (1167,700)-(1453,977) logical; convert through the
	# viewport's real transform rather than assuming 1:1 pixel mapping.
	var logical_pos := Vector2(1310, 838)
	var xform: Transform2D = get_viewport().get_final_transform()
	var click_pos: Vector2 = xform * logical_pos

	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = click_pos
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = click_pos
	Input.parse_input_event(up)
	await get_tree().process_frame

	await get_tree().create_timer(0.3).timeout
	print("INTRO_TOUCH_TEST: selecting_yes=", screen.selecting_yes,
		" has_moved=", screen.has_moved, " can_control=", screen.can_control)
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/intro_touch_test.png")
	print("INTRO_TOUCH_TEST: saved")
	get_tree().quit()
