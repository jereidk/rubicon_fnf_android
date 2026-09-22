extends RefCounted

## F3 - SymbolInstance.hx (282) + MovieClipInstance.hx (285) de
## MaybeMaru/flixel-animate@dcaa33c.
##
## El nucleo es getFrameIndex (SymbolInstance.hx:100-140): que frame del
## sub-simbolo muestra una instancia, N frames despues del keyframe que la
## contiene, segun loop type y la ventana firstFrame/lastFrame.
##
## Las secuencias esperadas de abajo estan calculadas a mano siguiendo el
## Haxe linea por linea, NO sacadas de correr el port (seria circular).

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const LOOP := AdobeSymbolInstance.AdobeSymbolLoopMode.LOOP
const ONE_SHOT := AdobeSymbolInstance.AdobeSymbolLoopMode.ONE_SHOT
const FREEZE := AdobeSymbolInstance.AdobeSymbolLoopMode.FREEZE_FRAME


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_get_frame_index(failures)
	_test_flx_wrap(failures)
	await _test_missing_symbol(tree, failures)
	await _test_zero_alpha_skipped(tree, failures)
	_test_resolve_blend(failures)

	return {
		"name": "symbol instance: getFrameIndex (SymbolInstance.hx:100-140)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _test_get_frame_index(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	# [descripcion, length, first_frame, last_frame, loop_mode, secuencia esperada para difference = 0..N]
	var cases: Array = [
		# --- sin lastFrame ---
		[
			"FF=0 sin LF, LOOP: wrap(d, 0, 3) sobre todo el simbolo",
			4, 0, -1, LOOP, [0, 1, 2, 3, 0, 1],
		],
		[
			# EL caso que la version vieja hacia mal: el source usa
			# FlxMath.wrap(frameIndex, 0, lastIndex), asi que al pasarse del
			# final vuelve al frame 0, no a first_frame. La version vieja
			# daba 7,8,9,7,8,9.
			"FF=7 sin LF, LOOP: se pasa del final y sigue desde 0",
			10, 7, -1, LOOP, [7, 8, 9, 0, 1, 2],
		],
		[
			"FF=0 sin LF, ONE_SHOT: clampea en el ultimo",
			4, 0, -1, ONE_SHOT, [0, 1, 2, 3, 3, 3],
		],
		[
			# span = lastIndex - firstFrame + 1 = 9 - 7 + 1 = 3.
			"FF=7 sin LF, ONE_SHOT: clampea en el ultimo del simbolo",
			10, 7, -1, ONE_SHOT, [7, 8, 9, 9, 9],
		],
		# --- ventana normal (LF >= FF) ---
		[
			"FF=1 LF=2, LOOP: wrap dentro de la ventana",
			4, 1, 2, LOOP, [1, 2, 1, 2, 1],
		],
		[
			"FF=1 LF=2, ONE_SHOT: clampea en LF",
			4, 1, 2, ONE_SHOT, [1, 2, 2, 2],
		],
		[
			# min(lastFrame, lastIndex): LF=99 se recorta al largo real.
			"FF=1 LF=99 (fuera de rango), LOOP: LF se recorta a lastIndex",
			4, 1, 99, LOOP, [1, 2, 3, 1, 2, 3],
		],
		# --- ventana que se pasa del final (LF < FF) ---
		[
			# tail = 5-3 = 2 frames (3, 4); head = LF + 1 = 2 frames (0, 1).
			# totalLength = 4.
			"FF=3 LF=1, LOOP: cola 3,4 + cabeza 0,1",
			5, 3, 1, LOOP, [3, 4, 0, 1, 3, 4, 0, 1],
		],
		[
			"FF=3 LF=1, ONE_SHOT: recorre cola+cabeza una vez y se queda",
			5, 3, 1, ONE_SHOT, [3, 4, 0, 1, 1, 1],
		],
		# --- freeze ---
		[
			"FF=2, FREEZE_FRAME: siempre el mismo",
			4, 2, -1, FREEZE, [2, 2, 2, 2],
		],
		[
			"FF=2 LF=3, FREEZE_FRAME: la ventana no importa",
			4, 2, 3, FREEZE, [2, 2, 2],
		],
	]

	for case: Array in cases:
		var description: String = case[0]
		var length: int = case[1]
		var expected: Array = case[5]

		var element: AdobeSymbolInstance = AdobeSymbolInstance.new()
		element.first_frame = case[2]
		element.last_frame = case[3]
		element.loop_mode = case[4]

		var got: Array[int] = []
		for difference in expected.size():
			got.push_back(atlas.symbol_instance_frame(element, length, difference))

		if got != expected:
			failures.push_back("%s: dio %s, esperaba %s" % [description, got, expected])

	# Un sub-simbolo de largo 0 no puede reventar ni devolver basura.
	var empty: AdobeSymbolInstance = AdobeSymbolInstance.new()
	empty.first_frame = 3
	empty.last_frame = -1
	empty.loop_mode = LOOP
	if atlas.symbol_instance_frame(empty, 0, 5) != 0:
		failures.push_back("length=0: deberia dar 0")


## _flx_wrap es la transcripcion de FlxMath.wrap (max INCLUSIVO), no el
## wrapi() de Godot (max exclusivo). Se chequea contra la formula del source
## aplicada a mano.
func _test_flx_wrap(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var cases: Array = [
		[0, 0, 3, 0],
		[3, 0, 3, 3],
		[4, 0, 3, 0],
		[7, 0, 3, 3],
		[5, 2, 4, 2],
		[-1, 0, 3, 3],
		[-5, 0, 3, 3],
		[2, 5, 5, 5],
	]
	for case: Array in cases:
		var got: int = atlas._flx_wrap(case[0], case[1], case[2])
		if got != case[3]:
			failures.push_back("_flx_wrap(%d, %d, %d): dio %d, esperaba %d" % [case[0], case[1], case[2], got, case[3]])


## SymbolInstance.hx:57-58:
##     if (libraryItem == null)
##         visible = false;
## Una instancia que apunta a un simbolo que no esta en la libreria no se
## dibuja. En el port eso no estaba: draw_symbol hacia symbols[element.key]
## directo y reventaba con un error de acceso a Nil.
func _test_missing_symbol(tree: SceneTree, failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"pixel"] = _make_sprite(Color(0, 1, 0, 1), Vector2i(60, 60))

	atlas.symbols[&"existe"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "pixel", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])
	atlas.symbols[&"root"] = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				{
					"I": 0,
					"DU": 1,
					"E": [
						{"SI": {"SN": "no_existe_en_la_libreria", "ST": "G", "MX": [1, 0, 0, 1, 0, 0]}},
						{"SI": {"SN": "existe", "ST": "G", "MX": [1, 0, 0, 1, 0, 0]}},
					],
				}
			],
		},
	])
	atlas.stage_symbol = &"root"

	var root_node: Node2D = Node2D.new()
	tree.root.add_child(root_node)

	var node: AnimateSymbol = AnimateSymbol.new()
	node.atlases = [atlas]
	node.symbol = "root"
	node.centered = false
	node.position = Vector2(300, 300)
	root_node.add_child(node)

	await Helpers.wait_frames(tree, 3)

	# El simbolo valido del mismo keyframe tiene que seguir dibujandose.
	var img: Image = tree.root.get_texture().get_image()
	var found: bool = false
	for y in range(80, img.get_height()):
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(Color(0, 1, 0, 1)):
				found = true
				break
		if found:
			break

	if not found:
		failures.push_back("simbolo faltante: el simbolo valido del mismo keyframe no se dibujo")

	root_node.queue_free()
	await tree.process_frame


func _make_sprite(color: Color, size: Vector2i) -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(Vector2i.ZERO, size)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(color, size)
	sprite.transform = Transform2D.IDENTITY
	return sprite


## SymbolInstance.hx:190-211: con color propio, el source concatena y si el
## alphaMultiplier resultante es <= 0 vuelve sin dibujar nada.
##
## Lo que este test puede probar es el resultado en pantalla: la instancia
## con alpha 0 no pinta y la de al lado si. Lo que NO puede probar desde
## afuera es la otra mitad del cambio -que el subarbol ni se recorra, y por
## lo tanto no agrande el screen_rect del backbuffer-, porque eso no tiene
## efecto visual. Queda como guard de no-regresion.
func _test_zero_alpha_skipped(tree: SceneTree, failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"rojo"] = _make_sprite(Color(1, 0, 0, 1), Vector2i(60, 60))
	atlas.spritemap[&"verde"] = _make_sprite(Color(0, 1, 0, 1), Vector2i(60, 60))

	atlas.symbols[&"sub_rojo"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "rojo", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])
	atlas.symbols[&"sub_verde"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "verde", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])
	atlas.symbols[&"root"] = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				{
					"I": 0,
					"DU": 1,
					"E": [
						# "CA"/Alpha con AM = 0: invisible.
						{"SI": {"SN": "sub_rojo", "ST": "G", "MX": [1, 0, 0, 1, 0, 0], "C": {"M": "CA", "AM": 0.0}}},
						{"SI": {"SN": "sub_verde", "ST": "G", "MX": [1, 0, 0, 1, 100, 0]}},
					],
				}
			],
		},
	])
	atlas.stage_symbol = &"root"

	var root_node: Node2D = Node2D.new()
	tree.root.add_child(root_node)

	var node: AnimateSymbol = AnimateSymbol.new()
	node.atlases = [atlas]
	node.symbol = "root"
	node.centered = false
	node.position = Vector2(300, 300)
	root_node.add_child(node)

	await Helpers.wait_frames(tree, 3)

	var img: Image = tree.root.get_texture().get_image()
	if _has_color(img, Color(1, 0, 0, 1)):
		failures.push_back("alpha 0: la instancia con AM = 0 se dibujo igual")
	if not _has_color(img, Color(0, 1, 0, 1)):
		failures.push_back("alpha 0: la instancia de al lado (sin color) desaparecio")

	root_node.queue_free()
	await tree.process_frame


func _has_color(img: Image, color: Color) -> bool:
	for y in range(80, img.get_height()):
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(color):
				return true
	return false


## Blend.resolve (maru/src/animate/internal/filters/Blend.hx), llamado desde
## SymbolInstance.hx:213 como Blend.resolve(this.blend, blend): gana el blend
## PROPIO, salvo que sea NORMAL, en cuyo caso se hereda el de arriba. El port
## tenia la precedencia al reves.
func _test_resolve_blend(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var NORMAL := AdobeSymbolInstance.AdobeBlendMode.NORMAL
	var MULTIPLY := AdobeSymbolInstance.AdobeBlendMode.MULTIPLY
	var SCREEN := AdobeSymbolInstance.AdobeBlendMode.SCREEN
	var ADD := AdobeSymbolInstance.AdobeBlendMode.ADD

	var cases: Array = [
		# [propio, heredado, esperado, descripcion]
		[MULTIPLY, SCREEN, MULTIPLY, "propio != NORMAL gana sobre el heredado"],
		[NORMAL, SCREEN, SCREEN, "propio NORMAL hereda el de arriba"],
		[NORMAL, NORMAL, NORMAL, "los dos NORMAL"],
		[ADD, NORMAL, ADD, "propio sobre un padre sin blend"],
		[SCREEN, ADD, SCREEN, "propio gana aunque el padre tenga uno fuerte"],
	]
	for case: Array in cases:
		var got: int = atlas.resolve_blend(case[0], case[1])
		if got != case[2]:
			failures.push_back("resolve_blend(%d, %d): dio %d, esperaba %d (%s)" % [case[0], case[1], got, case[2], case[3]])
