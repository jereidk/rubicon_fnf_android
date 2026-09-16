extends Node
# Follow-up to multiply_blend_debug.gd: that test showed BLEND_MODE_MUL
# zeroing RGB+alpha completely even over a fully-opaque source pixel, which
# would be surprising for a basic OpenGL blend func. This isolates whether
# it's specifically about back.png's transparency, by testing a plain,
# fully-opaque ColorRect (alpha=1 everywhere, no texture) with blend_mode=MUL
# over a magenta background.
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/multiply_blend_debug2.tscn

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(1, 0, 1, 1)
	bg.size = Vector2(400, 400)
	add_child(bg)

	var fg := ColorRect.new()
	fg.color = Color(0.5, 0.5, 0.5, 1.0)  # fully opaque 50% gray, no texture/transparency at all
	fg.size = Vector2(400, 400)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	fg.material = mat
	add_child(fg)

	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	var scale_x: float = image.get_width() / 1920.0
	var scale_y: float = image.get_height() / 1080.0
	var p := Vector2i(int(200 * scale_x), int(200 * scale_y))
	print("MUL_DEBUG2: opaque 50pct gray over magenta, expect ~(0.5,0,0.5,1), got=", image.get_pixelv(p))
	get_tree().quit()
