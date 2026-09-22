extends RefCounted

## F2 - Element.hx (78) + AtlasInstance.hx (244) de
## MaybeMaru/flixel-animate@dcaa33c.
##
## Cubre las dos reglas del source que el port no tenia:
##  - Frame.hx:423-426: cada elemento se dibuja SOLO si element.visible.
##    AnimateElement.visible (Element.hx:19, seteado a true en el ctor) es
##    parte de todo elemento, no solo de las capas.
##  - AtlasInstance.hx:98-99: draw() vuelve sin dibujar si el frame no existe
##    ("if (frame == null || frame.frame == null) return"). En el port un
##    nombre de sprite que no esta en el spritemap daba un AdobeAtlasSprite
##    vacio con texture == null y draw_atlas_sprite lo desreferenciaba.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_missing_sprite_keeps_matrix(failures)
	await _test_missing_sprite_no_crash(tree, failures)
	await _test_element_visible(tree, failures)

	return {
		"name": "element: visible + sprite faltante (Element.hx / AtlasInstance.hx)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


## AtlasInstance.hx:43-48: getByName puede devolver null, pero `this.matrix
## = data.MX.toMatrix()` se ejecuta igual. El port devolvia un
## AdobeAtlasSprite recien creado y tiraba la matriz.
func _test_missing_sprite_keeps_matrix(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"existe"] = _make_sprite(Color(0, 1, 0, 1), Vector2i(10, 10))

	var missing: AdobeAtlasSprite = atlas.load_atlas_sprite(true, {
		"ASI": {"N": "no_existe", "MX": [1, 0, 0, 1, 12, 34]},
	})
	if missing == null:
		failures.push_back("sprite faltante: load_atlas_sprite devolvio null")
		return
	if missing.texture != null:
		failures.push_back("sprite faltante: deberia quedar sin textura")
	if missing.transform.origin != Vector2(12, 34):
		failures.push_back("sprite faltante: la matriz se perdio (origin %s, esperaba (12, 34))" % missing.transform.origin)

	# Y el caso normal no puede haber cambiado.
	var ok: AdobeAtlasSprite = atlas.load_atlas_sprite(true, {
		"ASI": {"N": "existe", "MX": [1, 0, 0, 1, 5, 6]},
	})
	if ok.texture == null:
		failures.push_back("sprite existente: perdio la textura")
	if ok.transform.origin != Vector2(5, 6):
		failures.push_back("sprite existente: la matriz dio %s, esperaba (5, 6)" % ok.transform.origin)


## Un ASI que apunta a un nombre que no existe en el spritemap no puede
## romper el dibujado del resto del keyframe.
func _test_missing_sprite_no_crash(tree: SceneTree, failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"existe"] = _make_sprite(Color(0, 1, 0, 1), Vector2i(60, 60))

	atlas.symbols[&"root"] = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				{
					"I": 0,
					"DU": 1,
					"E": [
						{"ASI": {"N": "no_existe_en_el_spritemap", "MX": [1, 0, 0, 1, 0, 0]}},
						{"ASI": {"N": "existe", "MX": [1, 0, 0, 1, 0, 0]}},
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

	# El sprite que SI existe tiene que seguir dibujandose: si el elemento
	# roto hubiera cortado el loop, no habria ningun pixel verde.
	var img: Image = tree.root.get_texture().get_image()
	if not _has_color(img, Color(0, 1, 0, 1)):
		failures.push_back("sprite faltante: el sprite valido del mismo keyframe no se dibujo")

	root_node.queue_free()
	await tree.process_frame


func _has_color(img: Image, color: Color) -> bool:
	for y in range(80, img.get_height()):
		for x in img.get_width():
			if img.get_pixel(x, y).is_equal_approx(color):
				return true
	return false


func _make_sprite(color: Color, size: Vector2i) -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(Vector2i.ZERO, size)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(color, size)
	sprite.transform = Transform2D.IDENTITY
	return sprite


## Frame.hx:423-426: el loop de dibujo del keyframe saltea todo elemento con
## visible == false. Antes el port no tenia el campo y dibujaba todo.
func _test_element_visible(tree: SceneTree, failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"rojo"] = _make_sprite(Color(1, 0, 0, 1), Vector2i(60, 60))
	atlas.spritemap[&"azul"] = _make_sprite(Color(0, 0, 1, 1), Vector2i(60, 60))

	# Los dos sprites en el mismo keyframe, separados para que no se tapen.
	atlas.symbols[&"root"] = atlas.load_layers(true, [
		{
			"LN": "L",
			"FR": [
				{
					"I": 0,
					"DU": 1,
					"E": [
						{"ASI": {"N": "rojo", "MX": [1, 0, 0, 1, 0, 0]}},
						{"ASI": {"N": "azul", "MX": [1, 0, 0, 1, 100, 0]}},
					],
				}
			],
		},
	])
	atlas.stage_symbol = &"root"

	var elements: Array[AdobeDrawable] = atlas.symbols[&"root"].layers[0].frames[0].elements
	if elements.size() != 2:
		failures.push_back("visible: esperaba 2 elementos, hay %d" % elements.size())
		return
	for element: AdobeDrawable in elements:
		if not element.visible:
			failures.push_back("visible: el default tiene que ser true (Element.hx:29)")

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
	if not _has_color(img, Color(1, 0, 0, 1)):
		failures.push_back("visible: con los dos visibles, el rojo no se dibujo")
	if not _has_color(img, Color(0, 0, 1, 1)):
		failures.push_back("visible: con los dos visibles, el azul no se dibujo")

	# Apagar el rojo: tiene que desaparecer y el azul quedarse.
	elements[0].visible = false
	node.frame_dirty = true
	node.queue_redraw()
	await Helpers.wait_frames(tree, 3)

	img = tree.root.get_texture().get_image()
	if _has_color(img, Color(1, 0, 0, 1)):
		failures.push_back("visible=false: el rojo se siguio dibujando")
	if not _has_color(img, Color(0, 0, 1, 1)):
		failures.push_back("visible=false: el azul (que sigue visible) desaparecio")

	root_node.queue_free()
	await tree.process_frame
