extends Node2D

func _ready() -> void:
	# Load a known texture from the stage.
	var tex = load("res://holyquintet_mod/source/images/stages/resonance/simpleBG.png")
	if tex:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.position = Vector2(682, 384)
		add_child(sprite)
		print("MINIMAL: sprite added, tex=", tex.get_size())
	else:
		print("MINIMAL: FAILED to load texture!")

	# Also add a colored rect as control.
	var rect := ColorRect.new()
	rect.color = Color(0, 0.5, 1.0, 1.0)
	rect.position = Vector2(100, 100)
	rect.size = Vector2(200, 200)
	add_child(rect)
	print("MINIMAL: rect added")

	await get_tree().create_timer(0.5).timeout

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("/tmp/hq_renders/minimal_test.png")
	print("MINIMAL: saved")
	get_tree().quit()
