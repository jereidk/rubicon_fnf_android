# Minimal stage render test — loads stg_resonance.tscn directly with a
# simple Camera2D, bypassing the full level scene.
extends Node2D

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)

	# Load stage directly.
	var stage := load("res://holyquintet_mod/stages/stg_resonance.tscn").instantiate()
	add_child(stage)

	# Add a Camera2D that sees the full stage.
	var cam := Camera2D.new()
	cam.make_current()
	cam.zoom = Vector2(0.6, 0.6)
	cam.position = Vector2(150.0, 50.0)
	add_child(cam)

	print("stage_only_test: stage children=", stage.get_child_count())
	for child in stage.get_children():
		print("  - ", child.name, " visible=", child.visible, " type=", child.get_class(), " pos=", child.position, " z=", child.z_index)
	print("stage_only_test: camera enabled=", cam.enabled, " current=", cam.current)

	# Wait a few frames for rendering to settle.
	await get_tree().create_timer(0.5).timeout

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/stage_only_test.png")
	print("stage_only_test: saved to ", SHOT_DIR + "/stage_only_test.png")
	get_tree().quit()
