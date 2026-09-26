extends RefCounted

## F13b-i - AdobeRenderBaker: infra de render-to-texture.
## Cubre: request + bake via SubViewport + cache + invalidate.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	await _test_bake_simple(tree, failures)
	await _test_cache_hit(tree, failures)
	_test_invalidate(failures)

	return {
		"name": "render_baker: request + bake + cache + invalidate (F13b-i)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _test_bake_simple(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	if baker == null:
		failures.push_back("baker: instance() devolvio null")
		return

	# Pedir un bake de un rect rojo 32x32.
	baker.request("test_simple", Vector2i(32, 32), func(rid: RID, size: Vector2) -> void:
		RenderingServer.canvas_item_add_rect(rid, Rect2(Vector2.ZERO, size), Color.RED)
	)

	# Esperar 3 frames para que termine el bake.
	await Helpers.wait_frames(tree, 3)

	if not baker.has_cached("test_simple"):
		failures.push_back("bake: no quedo cacheado despues de 3 frames")
		return

	var tex: ImageTexture = baker.get_cached("test_simple")
	if tex == null:
		failures.push_back("bake: get_cached devolvio null")
		return

	if tex.get_width() != 32 or tex.get_height() != 32:
		failures.push_back("bake: size=%dx%d, esperaba 32x32" % [tex.get_width(), tex.get_height()])


func _test_cache_hit(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()

	# Sin request nuevo: el cache sigue el mismo.
	var tex_before: ImageTexture = baker.get_cached("test_simple")
	await Helpers.wait_frames(tree, 2)
	var tex_after: ImageTexture = baker.get_cached("test_simple")

	if tex_before != tex_after:
		failures.push_back("cache: la textura cambio sin request nuevo")


func _test_invalidate(failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	baker.invalidate("test_simple")
	if baker.has_cached("test_simple"):
		failures.push_back("invalidate: el cache sigue teniendo la key")
