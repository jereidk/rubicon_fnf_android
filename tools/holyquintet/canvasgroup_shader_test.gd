extends Node
# Isolates whether a plain passthrough shader on a CanvasGroup renders
# correctly at all, before debugging story_cinematic.gdshader's own math —
# the full menu went solid white with that shader applied mid-cinematic.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/canvasgroup_shader_test.tscn

func _ready() -> void:
	var pivot := Node2D.new()
	pivot.position = Vector2(960, 540)
	add_child(pivot)

	var group := CanvasGroup.new()
	group.position = Vector2(-960, -540)
	pivot.add_child(group)

	var ctrl := ColorRect.new()
	ctrl.color = Color(0.2, 0.6, 0.9)
	ctrl.position = Vector2.ZERO
	ctrl.size = Vector2(1920, 1080)
	group.add_child(ctrl)

	var circle := ColorRect.new()
	circle.color = Color.RED
	circle.position = Vector2(800, 400)
	circle.size = Vector2(320, 280)
	group.add_child(circle)

	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("/tmp/hq_renders/canvasgroup_shader_none.png")

	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = texture(TEXTURE, UV);\n}\n"
	mat.shader = shader
	group.material = mat

	await get_tree().process_frame
	await get_tree().process_frame
	var img2: Image = get_viewport().get_texture().get_image()
	img2.save_png("/tmp/hq_renders/canvasgroup_shader_passthrough.png")
	print("SHADER_TEST: passthrough pixel at bg area (100,100)=", img2.get_pixel(100, 100))
	print("SHADER_TEST: passthrough pixel at red rect (900,500)=", img2.get_pixel(900, 500))

	get_tree().quit()
