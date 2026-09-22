extends RefCounted

## Cadena de bounds POR FRAME: Timeline.getBounds (Timeline.hx:244-290) ->
## Layer.getBounds / getFrameAtIndex -> Frame.getBounds (Frame.hx:165-196) ->
## Element.getBounds, de MaybeMaru/flixel-animate@dcaa33c.
##
## Entra aca por F4: el hitbox de un boton es exactamente esto - los bounds
## del frame HIT del sub-simbolo (ButtonInstance.hx:45-51) - y sin la cadena
## no hay forma de portear el boton. Lo que queda de Timeline.hx y Frame.hx
## (cache, filtros, baking) se revisa en F5/F7.
##
## OJO con AdobeSymbol.bounding_box, que ya existia y NO es esto: ese es el
## equivalente de getWholeBounds, la union sobre TODOS los frames.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_sprite_bounds(failures)
	_test_per_frame_bounds(failures)
	_test_nested_symbol_bounds(failures)
	_test_mask_bounds(failures)
	_test_button_uses_hit_frame(failures)

	return {
		"name": "bounds por frame: Timeline/Frame/Element getBounds",
		"passed": failures.is_empty(),
		"failures": failures,
	}


## Un solo sprite: los bounds son su region movida por su matriz.
func _test_sprite_bounds(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"s"] = _sprite(Vector2i(40, 20))

	var sym: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 10, 5]}}]}]},
	])

	var got: Rect2 = atlas.symbol_bounds(sym, 0)
	if got != Rect2(10, 5, 40, 20):
		failures.push_back("sprite suelto: dio %s, esperaba (10, 5, 40, 20)" % got)

	# Con matriz externa se traslada todo.
	var moved: Rect2 = atlas.symbol_bounds(sym, 0, Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(100, 200)))
	if moved != Rect2(110, 205, 40, 20):
		failures.push_back("sprite con matriz externa: dio %s, esperaba (110, 205, 40, 20)" % moved)

	# Un simbolo sin nada: applyMatrixToRect sobre un rect vacio da un PUNTO
	# en el origen de la matriz (Timeline.hx:296-297), no un rect en (0,0).
	var empty_symbol: AdobeSymbol = atlas.load_layers(true, [{"LN": "L", "FR": []}])
	var empty: Rect2 = atlas.symbol_bounds(empty_symbol, 0, Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(7, 8)))
	if empty != Rect2(7, 8, 0, 0):
		failures.push_back("simbolo vacio: dio %s, esperaba el punto (7, 8, 0, 0)" % empty)


## Los bounds cambian por frame: es la diferencia con bounding_box, que une
## todos los frames.
func _test_per_frame_bounds(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"s"] = _sprite(Vector2i(10, 10))

	var sym: AdobeSymbol = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				{"I": 1, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 500, 0]}}]},
			],
		},
	])

	var f0: Rect2 = atlas.symbol_bounds(sym, 0)
	var f1: Rect2 = atlas.symbol_bounds(sym, 1)
	if f0 != Rect2(0, 0, 10, 10):
		failures.push_back("frame 0: dio %s, esperaba (0, 0, 10, 10)" % f0)
	if f1 != Rect2(500, 0, 10, 10):
		failures.push_back("frame 1: dio %s, esperaba (500, 0, 10, 10)" % f1)

	# Dos capas en el mismo frame: se unen.
	var two: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "A", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
		{"LN": "B", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 90, 40]}}]}]},
	])
	var union: Rect2 = atlas.symbol_bounds(two, 0)
	if union != Rect2(0, 0, 100, 50):
		failures.push_back("dos capas: dio %s, esperaba (0, 0, 100, 50)" % union)


## Una instancia de simbolo recursiona y aplica su propia matriz
## (SymbolInstance.hx:163-185).
func _test_nested_symbol_bounds(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"s"] = _sprite(Vector2i(20, 20))

	atlas.symbols[&"sub"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])
	# La instancia escala x2 y mueve a (30, 40).
	var root: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"SI": {"SN": "sub", "ST": "G", "MX": [2, 0, 0, 2, 30, 40]}}]}]},
	])

	var got: Rect2 = atlas.symbol_bounds(root, 0)
	if got != Rect2(30, 40, 40, 40):
		failures.push_back("simbolo anidado: dio %s, esperaba (30, 40, 40, 40)" % got)

	# Un simbolo que no existe no aporta bounds ni revienta.
	var broken: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"SI": {"SN": "no_existe", "ST": "G", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])
	if atlas.symbol_bounds(broken, 0) != Rect2():
		failures.push_back("simbolo inexistente: deberia aportar un rect vacio")


## mask_bounds, port de Timeline.maskBounds.
func _test_mask_bounds(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var cases: Array = [
		[Rect2(0, 0, 100, 100), Rect2(50, 50, 100, 100), Rect2(50, 50, 50, 50), "interseccion parcial"],
		[Rect2(0, 0, 100, 100), Rect2(200, 200, 10, 10), Rect2(), "sin overlap -> vacio"],
		[Rect2(0, 0, 100, 100), Rect2(), Rect2(0, 0, 100, 100), "masker vacio -> no toca el rect"],
		[Rect2(0, 0, 100, 100), Rect2(10, 10, 20, 20), Rect2(10, 10, 20, 20), "masker adentro"],
	]
	for case: Array in cases:
		var got: Rect2 = atlas.mask_bounds(case[0], case[1])
		if got != case[2]:
			failures.push_back("mask_bounds (%s): dio %s, esperaba %s" % [case[3], got, case[2]])


## ButtonInstance.hx:45-51: los bounds de un boton son los del frame HIT (3)
## del sub-simbolo, NO los del frame que esta mostrando.
func _test_button_uses_hit_frame(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"s"] = _sprite(Vector2i(10, 10))

	# 4 frames: UP/OVER/DOWN chiquitos en el origen, HIT grande y corrido.
	atlas.symbols[&"boton"] = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				{"I": 1, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				{"I": 2, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				{"I": 3, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [5, 0, 0, 5, 200, 300]}}]},
			],
		},
	])
	var root: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"SI": {"SN": "boton", "ST": "B", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])

	# El boton esta en UP (frame 0), pero los bounds tienen que ser los del HIT.
	var got: Rect2 = atlas.symbol_bounds(root, 0)
	if got != Rect2(200, 300, 50, 50):
		failures.push_back("boton: los bounds tienen que ser los del frame HIT (200, 300, 50, 50), dio %s" % got)

	# Un boton cuyo sub-simbolo no llega al frame 3 se clampea al ultimo.
	atlas.symbols[&"corto"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 60, 70]}}]}]},
	])
	var root_corto: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"SI": {"SN": "corto", "ST": "B", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])
	var corto: Rect2 = atlas.symbol_bounds(root_corto, 0)
	if corto != Rect2(60, 70, 10, 10):
		failures.push_back("boton de 1 frame: HIT se clampea al ultimo frame real, dio %s" % corto)


func _sprite(size: Vector2i) -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(Vector2i.ZERO, size)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(Color.RED, size)
	sprite.transform = Transform2D.IDENTITY
	return sprite
