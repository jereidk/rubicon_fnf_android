extends RefCounted

## Tests de AdobeAnimateController: registro de animaciones + busqueda de
## frame labels. Corre headless sin device (no necesita rendering real).
##
## Cubre:
## - add_by_symbol: registra todos los indices del simbolo pedido.
## - find_frame_label_indices: matchea el label contra las frames y devuelve
##   los indices cubiertos por la duracion del keyframe (Timeline.hx:145-171).
## - add_by_frame_label_indices: filtra solo los indices pedidos del label.
## - add_by_timeline: registra 0..length-1 del simbolo raiz.
## - play: setea symbol + frame.
## - get_animation_names / get_animation_indices.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	# Simbolo A: 5 frames, un color por frame.
	var colors: Array[Color] = [Color.RED, Color.GREEN, Color.BLUE, Color(1, 1, 0, 1), Color(1, 0, 1, 1)]
	for i in colors.size():
		atlas.spritemap[StringName("sprite_%d" % i)] = _make_sprite(colors[i], Vector2i(40, 40))

	# Simbolo "Anim5" con 5 frames sin labels.
	var anim5_frames: Array = []
	for i in colors.size():
		anim5_frames.push_back(_frame_no_label("sprite_%d" % i, i, 1))
	var anim5: AdobeSymbol = atlas.load_layers(true, [{"LN": "L", "FR": anim5_frames}])
	atlas.symbols[&"Anim5"] = anim5

	# Simbolo "WithLabels" con 3 keyframes:
	#   f0 d1 sin label (I:0, DU:1)
	#   f1 d3 con label "walk" (I:1, DU:3)
	#   f4 d2 sin label (I:4, DU:2)  <- length = 6
	var labeled_frames: Array = [
		_frame_no_label("sprite_0", 0, 1),
		_frame_with_label("sprite_1", 1, 3, "walk"),
		_frame_no_label("sprite_2", 4, 2),
	]
	var with_labels: AdobeSymbol = atlas.load_layers(true, [{"LN": "L", "FR": labeled_frames}])
	atlas.symbols[&"WithLabels"] = with_labels

	atlas.stage_symbol = &"Anim5"

	var node: AnimateSymbol = AnimateSymbol.new()
	node.atlases = [atlas]
	node.symbol = "Anim5"
	tree.root.add_child(node)
	await tree.process_frame

	# --- Test add_by_symbol ---
	node.anim.add_by_symbol("all5", "Anim5")
	var indices: PackedInt32Array = node.anim.get_animation_indices("all5")
	if indices.size() != 5:
		failures.push_back("add_by_symbol: esperaba 5 indices, hay %d" % indices.size())
	else:
		for i in 5:
			if indices[i] != i:
				failures.push_back("add_by_symbol: indices[%d]=%d, esperaba %d" % [i, indices[i], i])

	# --- Test find_frame_label_indices ---
	var walk: PackedInt32Array = node.anim.find_frame_label_indices("walk")
	if walk.size() != 3:
		failures.push_back("find_frame_label_indices('walk'): esperaba 3 indices, hay %d" % walk.size())
	else:
		# Label "walk" en frame I=1, DU=3 => indices [1, 2, 3].
		for i in 3:
			if walk[i] != (1 + i):
				failures.push_back("find_frame_label_indices('walk'): walk[%d]=%d, esperaba %d" % [i, walk[i], 1 + i])

	# Label que no existe.
	var nada: PackedInt32Array = node.anim.find_frame_label_indices("no-existe")
	if not nada.is_empty():
		failures.push_back("find_frame_label_indices('no-existe'): esperaba vacio, hay %d" % nada.size())

	# --- Test add_by_frame_label ---
	node.anim.add_by_frame_label("walk_anim", "walk")
	var walk_indices: PackedInt32Array = node.anim.get_animation_indices("walk_anim")
	if walk_indices.size() != 3:
		failures.push_back("add_by_frame_label: esperaba 3 indices, hay %d" % walk_indices.size())

	# --- Test add_by_frame_label_indices: solo el primero y el ultimo ---
	node.anim.add_by_frame_label_indices("walk_picks", "walk", PackedInt32Array([0, 2]))
	var picks: PackedInt32Array = node.anim.get_animation_indices("walk_picks")
	if picks.size() != 2:
		failures.push_back("add_by_frame_label_indices: esperaba 2 indices, hay %d" % picks.size())
	elif picks[0] != 1 or picks[1] != 3:
		failures.push_back("add_by_frame_label_indices: picks=[%d,%d], esperaba [1,3]" % [picks[0], picks[1]])

	# --- Test add_by_timeline ---
	node.anim.add_by_timeline("tl")
	var tl: PackedInt32Array = node.anim.get_animation_indices("tl")
	if tl.size() != 5:
		failures.push_back("add_by_timeline: esperaba 5 indices (length de Anim5), hay %d" % tl.size())

	# --- Test play ---
	node.anim.play("all5")
	if node.frame != 0:
		failures.push_back("play('all5'): frame=%d, esperaba 0" % node.frame)
	if node.anim.get_current_anim() != "all5":
		failures.push_back("play('all5'): current_anim='%s', esperaba 'all5'" % node.anim.get_current_anim())

	# --- Test get_animation_names ---
	var names: Array[String] = node.anim.get_animation_names()
	if names.size() != 4:
		failures.push_back("get_animation_names: esperaba 4, hay %d" % names.size())

	# --- Test symbol inexistente ---
	node.anim.add_by_symbol("ghost", "NoExiste")
	if not node.anim.get_animation_indices("ghost").is_empty():
		failures.push_back("add_by_symbol('ghost', 'NoExiste'): deberia no registrarse")

	# --- Limpieza ---
	node.queue_free()
	await tree.process_frame

	return {
		"name": "AnimateController: registro + busqueda + play",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _make_sprite(color: Color, size: Vector2i) -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(Vector2i.ZERO, size)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(color, size)
	sprite.transform = Transform2D.IDENTITY
	return sprite


func _frame_no_label(sprite_name: String, index: int, duration: int) -> Dictionary:
	return {
		"I": index,
		"DU": duration,
		"E": [{"ASI": {"N": sprite_name, "MX": [1, 0, 0, 1, 0, 0]}}],
	}


func _frame_with_label(sprite_name: String, index: int, duration: int, label: String) -> Dictionary:
	return {
		"I": index,
		"DU": duration,
		"N": label,
		"E": [{"ASI": {"N": sprite_name, "MX": [1, 0, 0, 1, 0, 0]}}],
	}
