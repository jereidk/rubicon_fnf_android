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
	_test_tile_matrix(failures)
	_test_replace_frame(failures)

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


## tile_matrix es el port de FlxFrame.prepareBlitMatrix(mat, false)
## (flixel 6.2.0, FlxFrame.hx:184-204), que AtlasInstance cachea en el ctor
## (AtlasInstance.hx:58). Tiene que dar lo MISMO que la rotacion que antes se
## armaba inline en draw_atlas_sprite/calculate_bounding_box.
func _test_tile_matrix(failures: Array[String]) -> void:
	var plain: AdobeAtlasSprite = _make_sprite(Color.RED, Vector2i(40, 20))
	if plain.tile_matrix != Transform2D.IDENTITY:
		failures.push_back("tile_matrix: un sprite sin rotar tiene que dar identidad, dio %s" % plain.tile_matrix)

	var turned: AdobeAtlasSprite = _make_sprite(Color.RED, Vector2i(40, 20))
	turned.rotated = true
	# ANGLE_NEG_90: rotateByNegative90() + translate(0, frame.width).
	var expected: Transform2D = Transform2D(-PI / 2.0, Vector2(0.0, 40))
	if turned.tile_matrix != expected:
		failures.push_back("tile_matrix: sprite rotado dio %s, esperaba %s" % [turned.tile_matrix, expected])

	# Y la bounding box tiene que seguir saliendo igual que con la formula
	# vieja (transform * rotacion aplicado al rect del region).
	turned.transform = Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2(7, 9))
	var old_way: Rect2 = (turned.transform * expected) * Rect2(Vector2.ZERO, Vector2(turned.region.size))
	if turned.bounding_box != old_way:
		failures.push_back("bounding_box de sprite rotado: dio %s, la formula vieja da %s" % [turned.bounding_box, old_way])


## replace_frame, AtlasInstance.hx:70-86.
func _test_replace_frame(failures: Array[String]) -> void:
	var sprite: AdobeAtlasSprite = _make_sprite(Color.RED, Vector2i(80, 40))
	var replacement: AdobeAtlasSprite = _make_sprite(Color(0, 0, 1, 1), Vector2i(40, 20))

	sprite.replace_frame(replacement)

	if sprite.texture != replacement.texture:
		failures.push_back("replace_frame: no tomo la textura nueva")
	if sprite.region.size != Vector2i(40, 20):
		failures.push_back("replace_frame: no tomo la region nueva (%s)" % sprite.region.size)
	# adjustScale: a = anchoOriginal / anchoNuevo = 80/40 = 2, d = 40/20 = 2.
	if not is_equal_approx(sprite.tile_matrix.x.x, 2.0) or not is_equal_approx(sprite.tile_matrix.y.y, 2.0):
		failures.push_back("replace_frame: adjust_scale dio a=%f d=%f, esperaba 2 y 2" % [sprite.tile_matrix.x.x, sprite.tile_matrix.y.y])
	# Con la escala, el frame nuevo tiene que ocupar lo mismo que el viejo.
	if sprite.bounding_box.size != Vector2(80, 40):
		failures.push_back("replace_frame: con adjust_scale la bounding box deberia seguir siendo 80x40, dio %s" % sprite.bounding_box.size)

	# null vuelve al frame original.
	sprite.replace_frame(null)
	if sprite.region.size != Vector2i(80, 40):
		failures.push_back("replace_frame(null): no volvio al frame original (%s)" % sprite.region.size)

	# Sin adjust_scale la tile matrix no se toca.
	var sprite2: AdobeAtlasSprite = _make_sprite(Color.RED, Vector2i(80, 40))
	sprite2.replace_frame(replacement, false)
	if sprite2.tile_matrix != Transform2D.IDENTITY:
		failures.push_back("replace_frame(adjust_scale=false): la tile matrix se toco igual (%s)" % sprite2.tile_matrix)
	if sprite2.bounding_box.size != Vector2(40, 20):
		failures.push_back("replace_frame(adjust_scale=false): la bounding box deberia ser la del frame nuevo, dio %s" % sprite2.bounding_box.size)
