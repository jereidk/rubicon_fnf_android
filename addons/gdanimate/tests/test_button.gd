extends RefCounted

## F4 - ButtonInstance.hx (153) de MaybeMaru/flixel-animate@dcaa33c.
##
## La mitad de "que frame muestro segun el estado" ya estaba; lo que faltaba
## era todo el input: el hitbox (bounds del frame HIT del sub-simbolo,
## ButtonInstance.hx:45-51), la maquina de estados UP/OVER/DOWN
## (ButtonInstance.hx:73-121) y la senal onClick.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const UP := AdobeButtonInstance.ButtonState.UP
const OVER := AdobeButtonInstance.ButtonState.OVER
const DOWN := AdobeButtonInstance.ButtonState.DOWN


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_frame_index(failures)
	_test_update_state(failures)
	_test_click_edge(failures)
	await _test_hitbox_is_local(tree, failures)

	return {
		"name": "button: hitbox + estados UP/OVER/DOWN + onClick (ButtonInstance.hx)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


## ButtonInstance.hx:53-56: min(curButtonState, frameCount - 1).
func _test_frame_index(failures: Array[String]) -> void:
	var button: AdobeButtonInstance = AdobeButtonInstance.new()

	for state: int in [UP, OVER, DOWN]:
		button.cur_state = state
		if button.button_frame_index(4) != state:
			failures.push_back("frame index: estado %d en un simbolo de 4 frames dio %d" % [state, button.button_frame_index(4)])

	# Clampeo: un boton de 2 frames no puede mostrar el frame 2.
	button.cur_state = DOWN
	if button.button_frame_index(2) != 1:
		failures.push_back("frame index: DOWN en un simbolo de 2 frames tiene que clampear a 1, dio %d" % button.button_frame_index(2))
	if button.button_frame_index(0) != 0:
		failures.push_back("frame index: simbolo vacio tiene que dar 0")


## ButtonInstance.hx:73-121, updateButtonState.
func _test_update_state(failures: Array[String]) -> void:
	var button: AdobeButtonInstance = AdobeButtonInstance.new()
	button.last_hitbox = Rect2(100, 100, 50, 40)

	var cases: Array = [
		# [punto, apretado, estado esperado, descripcion]
		[Vector2(0, 0), false, UP, "afuera, sin apretar"],
		[Vector2(120, 120), false, OVER, "adentro, sin apretar"],
		[Vector2(120, 120), true, DOWN, "adentro, apretado"],
		[Vector2(0, 0), true, UP, "afuera aunque este apretado"],
		# El source compara con <= / >=, asi que el borde CUENTA como adentro.
		[Vector2(100, 100), false, OVER, "esquina superior izquierda (borde incluido)"],
		[Vector2(150, 140), false, OVER, "esquina inferior derecha (borde incluido)"],
		[Vector2(151, 140), false, UP, "un pixel afuera a la derecha"],
	]

	for case: Array in cases:
		# Estado neutro antes de cada caso, y sin arrastrar el flanco.
		button.cur_state = UP
		button._was_pressed_last_frame = case[1]
		button.update_state(case[0], case[1])
		if button.cur_state != case[2]:
			failures.push_back("update_state (%s): dio %d, esperaba %d" % [case[3], button.cur_state, case[2]])

	# El valor de retorno dice si CAMBIO, que es lo que dispara el redraw.
	button.cur_state = UP
	button._was_pressed_last_frame = false
	if not button.update_state(Vector2(120, 120), false):
		failures.push_back("update_state: pasar de UP a OVER tiene que devolver true")
	if button.update_state(Vector2(121, 121), false):
		failures.push_back("update_state: quedarse en OVER tiene que devolver false")


## onClick dispara en el FLANCO de subida, no mientras se mantiene apretado.
## Y entrar al hitbox con el boton ya apretado no dispara (el source usa
## FlxG.mouse.justPressed, que es global).
func _test_click_edge(failures: Array[String]) -> void:
	var button: AdobeButtonInstance = AdobeButtonInstance.new()
	button.last_hitbox = Rect2(0, 0, 100, 100)

	var clicks: Array[int] = [0]
	button.clicked.connect(func() -> void: clicks[0] += 1)

	var inside: Vector2 = Vector2(50, 50)
	var outside: Vector2 = Vector2(500, 500)

	# Adentro, suelto -> apretado -> apretado -> suelto -> apretado = 2 clicks.
	button.update_state(inside, false)
	button.update_state(inside, true)
	if clicks[0] != 1:
		failures.push_back("click: el flanco de subida tiene que disparar una vez, van %d" % clicks[0])
	button.update_state(inside, true)
	if clicks[0] != 1:
		failures.push_back("click: mantener apretado NO puede disparar de nuevo, van %d" % clicks[0])
	button.update_state(inside, false)
	button.update_state(inside, true)
	if clicks[0] != 2:
		failures.push_back("click: soltar y volver a apretar tiene que disparar, van %d" % clicks[0])

	# Apretar afuera y entrar sin soltar: nada.
	var other: AdobeButtonInstance = AdobeButtonInstance.new()
	other.last_hitbox = Rect2(0, 0, 100, 100)
	var other_clicks: Array[int] = [0]
	other.clicked.connect(func() -> void: other_clicks[0] += 1)

	other.update_state(outside, false)
	other.update_state(outside, true)
	other.update_state(inside, true)
	if other_clicks[0] != 0:
		failures.push_back("click: entrar al hitbox con el boton ya apretado no tiene que disparar, van %d" % other_clicks[0])


## El hitbox tiene que salir del frame HIT del sub-simbolo y quedar en
## coordenadas LOCALES del nodo - o sea, NO moverse cuando el nodo se mueve.
func _test_hitbox_is_local(tree: SceneTree, failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"s"] = _sprite(Vector2i(10, 10))

	# Frames 0..2 (UP/OVER/DOWN) chicos en el origen, frame 3 (HIT) grande.
	atlas.symbols[&"boton"] = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				{"I": 0, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				{"I": 1, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				{"I": 2, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [1, 0, 0, 1, 0, 0]}}]},
				{"I": 3, "DU": 1, "E": [{"ASI": {"N": "s", "MX": [4, 0, 0, 4, 20, 30]}}]},
			],
		},
	])
	atlas.symbols[&"root"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"SI": {"SN": "boton", "ST": "B", "MX": [1, 0, 0, 1, 5, 5]}}]}]},
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

	var buttons: Array[AdobeButtonInstance] = node._buttons
	if buttons.size() != 1:
		failures.push_back("hitbox: esperaba 1 boton registrado en el dibujo, hay %d" % buttons.size())
		root_node.queue_free()
		await tree.process_frame
		return

	# HIT: sprite 10x10 escalado x4 en (20, 30) = (20, 30, 40, 40), mas el
	# (5, 5) de la matriz de la instancia = (25, 35, 40, 40) en coords del
	# sub-simbolo. El port le resta el bbox del simbolo ("root") via
	# compute_bounds_offset, que post-fix del calculate_bounding_box da
	# -(25,35). Resultado final en coords LOCALES del nodo: (0, 0, 40, 40).
	#
	# Antes del fix del bbox el shift era cero y este valor era
	# (25,35,40,40). El comentario original sigue valiendo: coords locales
	# del nodo, no se mueve al mover el nodo.
	var expected: Rect2 = Rect2(0, 0, 40, 40)
	if buttons[0].last_hitbox != expected:
		failures.push_back("hitbox: dio %s, esperaba %s (frame HIT, en coords locales)" % [buttons[0].last_hitbox, expected])

	# Mover el nodo NO puede cambiar el hitbox, porque es local.
	node.position = Vector2(700, 50)
	node.frame_dirty = true
	node.queue_redraw()
	await Helpers.wait_frames(tree, 3)

	if buttons[0].last_hitbox != expected:
		failures.push_back("hitbox: se movio con el nodo (%s), tiene que ser local" % buttons[0].last_hitbox)

	root_node.queue_free()
	await tree.process_frame


func _sprite(size: Vector2i) -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(Vector2i.ZERO, size)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(Color.RED, size)
	sprite.transform = Transform2D.IDENTITY
	return sprite
