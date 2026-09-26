extends RefCounted

## F13b-ii.3c - integracion del pipeline de bake.
##
## Testeable sin render real:
## - _filters_bake_key: devuelve "" o key segun los filtros de la capa.
## - AdobeRenderBaker.request con filtros: aplica filtros despues del bake.
##
## El test visual (sprite con BLUR se ve blureado en pantalla) NO se cubre
## aca; va a los tests visuales como test_swf_mode.gd.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const NORMAL := AdobeLayer.LayerType.NORMAL


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_bake_key_no_filters(failures)
	_test_bake_key_glow_only(failures)
	_test_bake_key_blur(failures)
	_test_bake_key_dropshadow(failures)
	await _test_baker_applies_filters_after_bake(tree, failures)

	return {
		"name": "bake_integration: key + baker con filtros (F13b-ii.3c)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _make_atlas_with_layer(filters: Array) -> Dictionary:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.symbols[&"sub"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [
			{"ASI": {"N": "pixel", "MX": [1, 0, 0, 1, 0, 0]}},
		]}]},
	])
	atlas.spritemap[&"pixel"] = _make_sprite()

	var sym: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "Mixto", "FR": [
			{"I": 0, "DU": 1, "F": filters, "E": [
				{"SI": {"SN": "sub", "ST": "G", "MX": [1, 0, 0, 1, 0, 0]}},
			]},
		]},
	])
	return {"atlas": atlas, "sym": sym}


func _make_sprite() -> AdobeAtlasSprite:
	var s: AdobeAtlasSprite = AdobeAtlasSprite.new()
	s.region = Rect2i(0, 0, 16, 16)
	s.texture = Helpers.make_solid_texture(Color.RED, Vector2i(16, 16))
	return s


## Sin filtros: la key debe ser "".
func _test_bake_key_no_filters(failures: Array[String]) -> void:
	var d: Dictionary = _make_atlas_with_layer([])
	var atlas: AdobeAtlas = d["atlas"]
	var sym: AdobeSymbol = d["sym"]
	var layer: AdobeLayer = sym.layers[0]
	var lf: AdobeLayerFrame = layer.frames[0]
	var key: String = atlas._filters_bake_key(layer, 0, lf)
	if not key.is_empty():
		failures.push_back("no_filters: key='%s', esperaba ''" % key)


## Glow solo: la key debe ser "" (glow va por shader inline).
func _test_bake_key_glow_only(failures: Array[String]) -> void:
	var d: Dictionary = _make_atlas_with_layer([
		{"N": "GF", "C": "#FF0000", "BLX": 6.0, "BLY": 6.0},
	])
	var atlas: AdobeAtlas = d["atlas"]
	var sym: AdobeSymbol = d["sym"]
	var layer: AdobeLayer = sym.layers[0]
	var lf: AdobeLayerFrame = layer.frames[0]
	var key: String = atlas._filters_bake_key(layer, 0, lf)
	if not key.is_empty():
		failures.push_back("glow_only: key='%s', esperaba '' (glow no bakea)" % key)


## BLUR: la key debe ser no vacia.
func _test_bake_key_blur(failures: Array[String]) -> void:
	var d: Dictionary = _make_atlas_with_layer([
		{"N": "BLF", "BLX": 8.0, "BLY": 8.0, "Q": 1},
	])
	var atlas: AdobeAtlas = d["atlas"]
	var sym: AdobeSymbol = d["sym"]
	var layer: AdobeLayer = sym.layers[0]
	var lf: AdobeLayerFrame = layer.frames[0]
	var key: String = atlas._filters_bake_key(layer, 0, lf)
	if key.is_empty():
		failures.push_back("blur: key vacia, esperaba no-vacia")
	if not key.begins_with("layer:"):
		failures.push_back("blur: key='%s', esperaba empezar con 'layer:'" % key)


## DropShadow: la key debe ser no vacia.
func _test_bake_key_dropshadow(failures: Array[String]) -> void:
	var d: Dictionary = _make_atlas_with_layer([
		{"N": "DSF", "D": 5.0, "AL": 45.0, "C": "#000000"},
	])
	var atlas: AdobeAtlas = d["atlas"]
	var sym: AdobeSymbol = d["sym"]
	var layer: AdobeLayer = sym.layers[0]
	var lf: AdobeLayerFrame = layer.frames[0]
	var key: String = atlas._filters_bake_key(layer, 0, lf)
	if key.is_empty():
		failures.push_back("dropshadow: key vacia, esperaba no-vacia")


## Integracion baker: request con filtros BLUR produce textura filtrada
## cacheada.
func _test_baker_applies_filters_after_bake(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	baker.invalidate("test_bake_with_blur")

	# Fuente: textura con borde duro (mitad roja / mitad transparente).
	var src_img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	src_img.fill(Color(0, 0, 0, 0))
	for y in 32:
		for x in range(0, 16):
			src_img.set_pixel(x, y, Color.RED)
	var src_tex: ImageTexture = ImageTexture.create_from_image(src_img)

	var filters: Array[AdobeFilter] = AdobeFilter.parse_list([
		{"N": "BLF", "BLX": 8.0, "BLY": 8.0, "Q": 1},
	])

	# Request con draw_cb que dibuja el src al SubViewport.
	baker.request("test_bake_with_blur", Vector2i(32, 32), func(rid: RID, size: Vector2) -> void:
		RenderingServer.canvas_item_add_texture_rect(
			rid, Rect2(Vector2.ZERO, size), src_tex.get_rid(), false)
	, filters)

	# Esperar a que el bake + apply_filters_to_texture terminen.
	await Helpers.wait_frames(tree, 5)

	if not baker.has_cached("test_bake_with_blur"):
		failures.push_back("baker_int: no quedo cacheado tras 5 frames")
		return

	var result: ImageTexture = baker.get_cached("test_bake_with_blur")
	if result == null:
		failures.push_back("baker_int: get_cached null")
		return

	# El pixel del borde (x=15) en el resultado tiene que estar atenuado
	# por el blur (mezcla con la mitad transparente).
	var img: Image = result.get_image()
	var edge: Color = img.get_pixel(15, 16)
	if edge.r >= 0.99:
		failures.push_back("baker_int: blur no aplicado (r=%f en borde)" % edge.r)
