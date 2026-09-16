extends Node
# Diagnostic: renders back.png (a semi-transparent gradient with real alpha
# 0 in some areas, ~90/255 in others, 255 in the solid triangle) over a
# bright magenta background with CanvasItemMaterial blend_mode=MUL (3), to
# see whether Godot's multiply blend correctly respects per-pixel alpha
# (should leave alpha=0 areas at the background's original bright color) or
# ignores it (darkens everywhere regardless of transparency) — investigating
# why the main menu's "wedge" background area renders much darker than the
# real reference screenshot even after fixing blend_mode from 2 (Sub) to 3
# (Mul).
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/multiply_blend_debug.tscn

const SHOT_DIR := "/tmp/hq_renders"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)

	var bg := ColorRect.new()
	bg.color = Color(1, 0, 1)  # bright magenta, easy to eyeball vs black
	bg.size = Vector2(1920, 1080)
	add_child(bg)

	var back := TextureRect.new()
	back.texture = load("res://holyquintet_mod/source/images/ui/common/back.png")
	back.size = Vector2(1920, 1080)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	back.material = mat
	add_child(back)

	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + "/multiply_blend_debug.png")
	print("MUL_DEBUG: image size=", image.get_size(), " viewport visible rect=", get_viewport().get_visible_rect())

	# viewport is scaled to the window; sample proportionally
	var scale_x: float = image.get_width() / 1920.0
	var scale_y: float = image.get_height() / 1080.0
	for p in [Vector2(10, 10), Vector2(100, 100), Vector2(900, 100), Vector2(900, 604), Vector2(1266, 604), Vector2(1600, 604)]:
		var px: Vector2i = Vector2i(p.x * scale_x, p.y * scale_y)
		print("MUL_DEBUG: logical=", p, " pixel=", px, " color=", image.get_pixelv(px))

	var center: Vector2i = Vector2i(image.get_width() / 2, image.get_height() / 2)
	print("MUL_DEBUG: with back VISIBLE, center pixel=", image.get_pixelv(center))

	back.visible = false
	await get_tree().process_frame
	var image2: Image = get_viewport().get_texture().get_image()
	print("MUL_DEBUG: with back HIDDEN, center pixel=", image2.get_pixelv(center))

	back.material = null
	back.visible = true
	await get_tree().process_frame
	var image3: Image = get_viewport().get_texture().get_image()
	print("MUL_DEBUG: with back VISIBLE no-material (plain alpha blend), center pixel=", image3.get_pixelv(center))
	image3.save_png(SHOT_DIR + "/multiply_blend_debug_nomat.png")

	print("MUL_DEBUG: done")
	get_tree().quit()
