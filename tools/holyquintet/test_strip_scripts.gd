extends Node2D

func _ready() -> void:
	var level := load("res://songs/resonance/resonance.tscn").instantiate()

	# Remove all HQ scripts and problematic nodes before entering tree.
	for name_str in ["HQSongCompletion", "HQGameOverHandler", "HQEventDispatcher",
					 "HQStageEvents", "HQGauntletRuntime", "HQPause", "HQDialogue"]:
		var n := level.get_node_or_null(name_str)
		if n:
			n.get_parent().remove_child(n)
			n.queue_free()
			print("STRIP: removed ", name_str)

	# Remove Camera2D.
	var cam := level.get_node_or_null("RubiconInterpolatedCamera2D")
	if cam:
		cam.get_parent().remove_child(cam)
		cam.queue_free()
		print("STRIP: removed Camera2D")

	add_child(level)

	# Add plain Camera2D.
	var plain := Camera2D.new()
	plain.position = Vector2(150.0, 50.0)
	plain.zoom = Vector2(0.55, 0.55)
	plain.make_current()
	add_child(plain)

	# Also manually set canvas_transform (belt and suspenders).
	var vp_size := Vector2(get_viewport().get_visible_rect().size)
	var half := vp_size / (2.0 * Vector2(0.55, 0.55))
	var origin := Vector2(150.0, 50.0) - half
	get_viewport().canvas_transform = Transform2D(
		Vector2(0.55, 0.0), Vector2(0.0, 0.55), origin)

	await get_tree().create_timer(0.5).timeout

	# Print diagnostic info about Stage children.
	var stage := level.get_node_or_null("Stage")
	if stage:
		print("STRIP: Stage visible=", stage.visible, " modulate=", stage.modulate)
		for c in stage.get_children():
			print("  ", c.name, " visible=", c.visible, " type=", c.get_class(),
				  " pos=", c.position, " z=", c.z_index)

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("/tmp/hq_renders/strip_test.png")
	print("STRIP: saved")
	get_tree().quit()
