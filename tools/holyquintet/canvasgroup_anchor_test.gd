extends Node
# Checks whether a Control with anchors_preset=15 (full-rect stretch) still
# correctly fills the 1920x1080 viewport when its parent is a CanvasGroup
# (Node2D-based, not a Control) instead of another Control — de-risking a
# planned main_menu.tscn restructure (wrapping everything in a CanvasGroup
# so beginStoryMode's Bloom/Transverse/adjustColor shaders, which need to
# read what's already been drawn, can apply to a local composited buffer
# instead of the screen texture — unsupported on this project's GL
# Compatibility renderer, as multiply_blend_debug.gd already found for an
# unrelated blend-mode bug).
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/canvasgroup_anchor_test.tscn

func _ready() -> void:
	var group := CanvasGroup.new()
	add_child(group)

	var ctrl := ColorRect.new()
	ctrl.color = Color.RED
	ctrl.position = Vector2.ZERO
	ctrl.size = Vector2(1920, 1080)
	group.add_child(ctrl)

	var pivot := Node2D.new()
	pivot.position = Vector2(960, 540)
	add_child(pivot)
	remove_child(group)
	pivot.add_child(group)
	group.position = Vector2(-960, -540)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("CANVASGROUP_TEST: ctrl.size=", ctrl.size, " ctrl.global_position=", ctrl.global_position)
	print("CANVASGROUP_TEST: expected global_position=(0,0) at rest (pivot at center, group offset -960,-540)")

	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("/tmp/hq_renders/canvasgroup_anchor_test.png")
	print("CANVASGROUP_TEST: pixel at (10,10)=", image.get_pixel(10, 10))
	print("CANVASGROUP_TEST: pixel at center=", image.get_pixel(image.get_width() / 2, image.get_height() / 2))
	print("CANVASGROUP_TEST: pixel at bottom-right-ish=", image.get_pixel(image.get_width() - 10, image.get_height() - 10))

	# Now rotate/scale the pivot 45deg + 1.5x and re-check: center pixel should
	# still be red (pivot rotation/scale is around its own origin = screen
	# center), corners should now show the CanvasGroup's own composited edge
	# artifacts if any (there shouldn't be any — plain rotation/scale of an
	# opaque full rect).
	pivot.rotation = deg_to_rad(45.0)
	pivot.scale = Vector2(1.5, 1.5)
	await get_tree().process_frame
	var image2: Image = get_viewport().get_texture().get_image()
	image2.save_png("/tmp/hq_renders/canvasgroup_anchor_test_rotated.png")
	print("CANVASGROUP_TEST: after rotate/scale, pixel at center=", image2.get_pixel(image2.get_width() / 2, image2.get_height() / 2))
	print("CANVASGROUP_TEST: after rotate/scale, pixel at (10,10) (should now be black/background, rotated out)=", image2.get_pixel(10, 10))

	get_tree().quit()
