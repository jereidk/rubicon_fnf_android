extends Node2D

func _ready() -> void:
	# Load only the stage, no characters, no HQ scripts.
	var stage = load("res://holyquintet_mod/stages/stg_resonance.tscn").instantiate()
	add_child(stage)

	# Add camera.
	var cam := Camera2D.new()
	cam.make_current()
	cam.position = Vector2(150.0, 50.0)
	cam.zoom = Vector2(0.55, 0.55)
	add_child(cam)

	# Add a character sprite to verify.
	var tex = load("res://holyquintet_mod/source/images/stages/resonance/simpleBG.png")
	if tex:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = Vector2(0, -1200)
		s.centered = false
		s.scale = Vector2(1.5, 1.5)
		add_child(s)
		print("STAGE: BG sprite added")

	await get_tree().create_timer(0.5).timeout
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("/tmp/hq_renders/stage_render.png")
	print("STAGE: saved")
	get_tree().quit()
