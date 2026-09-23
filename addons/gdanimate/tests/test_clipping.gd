extends RefCounted

## Etapa 1A - fix de clipping: una capa con Clipped_by cuyo Clipper no existe
## (o el nombre matchea pero no es tipo Clp) tiene que quedar oculta por
## completo, no caer silenciosamente al parent sin clip.
##
## cne-flixel-animate/src/animate/internal/Layer.hx:141-164 (_loadJson):
## busca hacia arriba (indices menores) la capa mas cercana con el mismo
## nombre Y tipo Clipper; si no la encuentra, visible=false.
##
## Este test llama directo a AdobeAtlas.load_layers() (el parser real, no una
## reconstruccion a mano de AdobeLayer) con JSON sintetico, para ejercitar el
## codigo que arregla esto en adobe_atlas.gd. La assertion determinística es
## sobre el estado de los AdobeLayer resultantes; la captura de pantalla es
## de cortesia para que el usuario vea que no crashea y compare a ojo.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"clipper_sprite"] = _make_sprite(Color.RED, Vector2i(40, 40))
	atlas.spritemap[&"clipped_sprite"] = _make_sprite(Color(0, 0, 1, 1), Vector2i(60, 60))

	# Caso OK: ClippedLayer.Clpb apunta a ClipperLayer, que existe arriba y es
	# tipo Clp -> debe quedar visible, clipeada normalmente.
	var layers_ok: Array = [
		{"LN": "ClipperLayer", "LT": "Clp", "FR": [_frame_with_sprite("clipper_sprite")]},
		{"LN": "ClippedLayer", "Clpb": "ClipperLayer", "FR": [_frame_with_sprite("clipped_sprite")]},
	]
	var symbol_ok: AdobeSymbol = atlas.load_layers(true, layers_ok)

	if symbol_ok.layers.size() != 2:
		failures.push_back("caso OK: esperaba 2 capas, hay %d" % symbol_ok.layers.size())
	else:
		if symbol_ok.layers[1].hidden:
			failures.push_back("caso OK: ClippedLayer quedo hidden=true, deberia ser false (su Clipper existe)")
		if symbol_ok.layers[1].clipped_by != "ClipperLayer":
			failures.push_back("caso OK: clipped_by se borro (%s), no deberia tocarse cuando el Clipper existe" % symbol_ok.layers[1].clipped_by)

	# Caso roto: hay una capa llamada "ClipperLayer" arriba, pero NO es tipo
	# Clp (LT ausente = NORMAL). El nombre matchea, el tipo no. La capa
	# clipeada tiene que quedar oculta segun Layer.hx:158-163.
	var layers_missing: Array = [
		{"LN": "ClipperLayer", "FR": [_frame_with_sprite("clipper_sprite")]},
		{"LN": "ClippedLayer", "Clpb": "ClipperLayer", "FR": [_frame_with_sprite("clipped_sprite")]},
	]
	var symbol_missing: AdobeSymbol = atlas.load_layers(true, layers_missing)

	if symbol_missing.layers.size() != 2:
		failures.push_back("caso roto: esperaba 2 capas, hay %d" % symbol_missing.layers.size())
	else:
		if not symbol_missing.layers[1].hidden:
			failures.push_back("caso roto: ClippedLayer deberia quedar hidden=true (su Clipper no es tipo Clp)")
		# maru Layer.hx:158-163 NO limpia Clpb cuando el clipper no aparece:
		# solo pone parentLayer=null, isMasked=false, visible=false. El
		# clipped_by se mantiene intacto. (El port viejo lo limpiaba; F6
		# corrige a maru.)
		if symbol_missing.layers[1].clipped_by != "ClipperLayer":
			failures.push_back("caso roto: clipped_by tiene que mantenerse 'ClipperLayer', quedo '%s'" % symbol_missing.layers[1].clipped_by)
		if symbol_missing.layers[1].parent_layer != null:
			failures.push_back("caso roto: parent_layer deberia ser null")

	# Captura visual de cortesia: dos AnimateSymbol lado a lado. El de la
	# izquierda (clip_ok) deberia mostrar el cuadrado azul clipeado dentro
	# del rojo; el de la derecha (clip_missing) deberia mostrar SOLO el
	# cuadrado "clipper" suelto, sin nada clipeado encima encima (ClippedLayer
	# no se dibuja en absoluto).
	atlas.symbols[&"clip_ok"] = symbol_ok
	atlas.symbols[&"clip_missing"] = symbol_missing
	# Ver _helpers.gd:make_test_atlas - draw_on() vuelve sin dibujar nada si
	# stage_symbol esta vacio, aunque symbols.has(draw_info.symbol) sea true.
	atlas.stage_symbol = &"clip_ok"

	var root_node: Node2D = Node2D.new()
	tree.root.add_child(root_node)

	var symbol_ok_node: AnimateSymbol = AnimateSymbol.new()
	symbol_ok_node.atlases = [atlas]
	symbol_ok_node.symbol = "clip_ok"
	symbol_ok_node.position = Vector2(20, 20)
	root_node.add_child(symbol_ok_node)

	var symbol_missing_node: AnimateSymbol = AnimateSymbol.new()
	symbol_missing_node.atlases = [atlas]
	symbol_missing_node.symbol = "clip_missing"
	symbol_missing_node.position = Vector2(120, 20)
	root_node.add_child(symbol_missing_node)

	await Helpers.wait_frames(tree, 3)
	var png: String = Helpers.capture_png(tree, "clipping.png")

	root_node.queue_free()
	await tree.process_frame

	return {
		"name": "clipping: capa sin Clipper valido queda oculta",
		"passed": failures.is_empty(),
		"failures": failures,
		"png": png,
	}


func _make_sprite(color: Color, size: Vector2i) -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(Vector2i.ZERO, size)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(color, size)
	sprite.transform = Transform2D.IDENTITY
	return sprite


func _frame_with_sprite(sprite_name: String) -> Dictionary:
	return {
		"I": 0,
		"DU": 1,
		"E": [{"ASI": {"N": sprite_name, "MX": [1, 0, 0, 1, 0, 0]}}],
	}
