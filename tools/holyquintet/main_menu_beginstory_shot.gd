extends Node
# Confirms beginStoryMode()'s real cinematic: ui_storystart SFX, menu music
# fading out, and the camera spin+zoom (root rotation/scale standing in for
# FlxG.camera.angle/zoom) — previously only the fade-to-black half of this
# was ported.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/main_menu_beginstory_shot.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var scene: PackedScene = load("res://holyquintet_mod/menus/main/main_menu.tscn")
	var screen: Node = scene.instantiate()
	add_child(screen)

	await get_tree().create_timer(0.5).timeout
	print("BEGIN_STORY_SHOT: music playing before story confirm=", HQTransition._music.playing)

	await _press(KEY_ENTER)  # Story -> StoryDiffUI (fresh save)
	await get_tree().create_timer(0.6).timeout
	await _press(KEY_LEFT)  # select Easy (starts with nothing selected)
	await get_tree().create_timer(0.2).timeout
	await _press(KEY_ENTER)  # confirm Easy

	for t in [0.2, 1.0, 2.0, 2.6]:
		await get_tree().create_timer(t if t == 0.2 else t - 0.2).timeout
		print("BEGIN_STORY_SHOT: t=", t,
			" rotation_deg=", rad_to_deg(screen.pivot.rotation),
			" scale=", screen.pivot.scale,
			" shader_bloom=", (screen.scene_group.material.get_shader_parameter("bloom_amt") if screen.scene_group.material else null),
			" shader_falloff=", (screen.scene_group.material.get_shader_parameter("transverse_falloff") if screen.scene_group.material else null),
			" shader_sat=", (screen.scene_group.material.get_shader_parameter("saturation") if screen.scene_group.material else null),
			" music.playing=", HQTransition._music.playing,
			" music.volume_db=", HQTransition._music.volume_db)
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(SHOT_DIR + "/beginstory_t%02d.png" % int(t * 10))

	print("BEGIN_STORY_SHOT: done")
	get_tree().quit()


func _press(keycode: int) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
