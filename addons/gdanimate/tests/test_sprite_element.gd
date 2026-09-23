extends RefCounted

## F13b-iii - AdobeSpriteElement. Cubre: bbox, capture/restore del padre,
## y un bake completo con un ColorRect movido al SubViewport.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_bbox(failures)
	_test_capture_restore_parent(failures)
	await _test_node_bake(tree, failures)

	return {
		"name": "sprite_element: bbox + capture + bake (F13b-iii)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _test_bbox(failures: Array[String]) -> void:
	var spe: AdobeSpriteElement = AdobeSpriteElement.new()
	var rect: Control = Control.new()
	rect.size = Vector2(40.0, 30.0)
	spe.target = rect
	spe.transform = Transform2D(0.0, Vector2(10.0, 20.0))
	var bb: Rect2 = spe.bounding_box
	if bb.position != Vector2(10.0, 20.0):
		failures.push_back("bbox: pos=%s, esperaba (10, 20)" % bb.position)
	if bb.size != Vector2(40.0, 30.0):
		failures.push_back("bbox: size=%s, esperaba (40, 30)" % bb.size)
	rect.free()


func _test_capture_restore_parent(failures: Array[String]) -> void:
	var parent_a: Node2D = Node2D.new()
	var parent_b: Node2D = Node2D.new()
	var target: Node2D = Node2D.new()
	parent_a.add_child(target)

	var spe: AdobeSpriteElement = AdobeSpriteElement.new()
	spe.target = target
	spe.capture_original_parent()

	parent_a.remove_child(target)
	parent_b.add_child(target)

	spe.restore_target_parent()
	if target.get_parent() != parent_a:
		failures.push_back("restore: el target no volvio a parent_a")

	parent_a.free()
	parent_b.free()


func _test_node_bake(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	baker.invalidate("spe_test_bake")

	var rect: Control = Control.new()
	rect.size = Vector2(32.0, 32.0)
	rect.custom_minimum_size = Vector2(32.0, 32.0)
	var cr: ColorRect = ColorRect.new()
	cr.color = Color.RED
	cr.size = Vector2(32.0, 32.0)
	rect.add_child(cr)

	var spe: AdobeSpriteElement = AdobeSpriteElement.new()
	spe.target = rect

	var placeholder: Node = Node.new()
	tree.root.add_child(placeholder)
	placeholder.add_child(rect)

	baker.request_node_bake("spe_test_bake", spe, Vector2i(32, 32))
	await Helpers.wait_frames(tree, 5)

	if not baker.has_cached("spe_test_bake"):
		failures.push_back("bake: no quedo cacheado tras 5 frames")
		placeholder.queue_free()
		return

	var tex: ImageTexture = baker.get_cached("spe_test_bake")
	if tex == null:
		failures.push_back("bake: get_cached null")
		placeholder.queue_free()
		return

	var img: Image = tex.get_image()
	var px: Color = img.get_pixel(16, 16)
	if px.r < 0.5:
		failures.push_back("bake: centro del rect no es rojo (r=%f)" % px.r)

	if rect.get_parent() != placeholder:
		failures.push_back("bake: el target no volvio a placeholder")

	placeholder.queue_free()
