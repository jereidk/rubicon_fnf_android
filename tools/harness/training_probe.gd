extends Node
## Carga songs/test/test.tscn con una peticion de Training viva y reporta que
## se construyo de verdad: la mecanica, el overlay, los controles tactiles, y
## el estado interno del que dependia cada uno de los tres bugs.
func _ready() -> void:
	for mech in [1, 2, 3]:
		LullabyTraining.requested = mech
		var ps: PackedScene = load(LullabyTraining.TEST_SONG)
		if ps == null:
			print("OUT no se pudo cargar el nivel de test"); get_tree().quit(1); return
		var lvl: Node = ps.instantiate()
		add_child(lvl)
		for _i in 12: await get_tree().process_frame
		_report(mech, lvl)
		lvl.queue_free()
		await get_tree().process_frame
	await _typing_chains()
	await _button_reaches_mechanic()
	print("OUT listo")
	get_tree().quit()

## Lo que un sondeo de un solo frame no puede ver: que al resolver una palabra
## llega la siguiente. typing_challenge.gd no encadena solo - Monochrome le da
## una palabra nueva desde su animacion de escena y aqui no hay animacion.
func _typing_chains() -> void:
	var lvl: Node = _spawn(3)
	var t: Node = _find_class(lvl, "TypingChallenge")
	var overlay: Node = _find_class(lvl, "LullabyTrainingOverlay")
	for _i in 12: await get_tree().process_frame
	var first: String = t.current_word
	for c: String in first:
		t.input_letter(c)
	var waited: float = 0.0
	while waited < 5.0 and t.current_word == first:
		await get_tree().process_frame
		waited += get_process_delta_time()
	print("OUT bucle   \"%s\" -> \"%s\" en %.1fs, hits=%d, time_end=%.2f  %s" % [
		first, t.current_word, waited, overlay.hits, t.time_end,
		"ENCADENA" if t.current_word != first else "*** ATASCADA ***"])
	lvl.queue_free()
	await get_tree().process_frame

## Y que el boton redondo despacha de verdad hasta la mecanica. Es un
## InputEventAction sintetico que tiene que llegar al _input() del controlador
## por Input.parse_input_event, no una llamada directa.
func _button_reaches_mechanic() -> void:
	var lvl: Node = _spawn(2)
	var overlay: Node = _find_class(lvl, "LullabyTrainingOverlay")
	var btn: Node = _find_named(lvl, "TrainingSpecialButton")
	for _i in 12: await get_tree().process_frame
	for _i in 20:
		btn.emit_signal("pressed")
		for _j in 4: await get_tree().process_frame
	var total: int = overlay.hits + overlay.misses
	print("OUT boton   hits=%d misses=%d  %s" % [overlay.hits, overlay.misses,
		"LLEGA A LA MECANICA" if total > 0 else "*** NO HACE NADA ***"])
	lvl.queue_free()
	await get_tree().process_frame

func _spawn(mech: int) -> Node:
	LullabyTraining.requested = mech
	var lvl: Node = (load(LullabyTraining.TEST_SONG) as PackedScene).instantiate()
	add_child(lvl)
	return lvl

func _report(mech: int, lvl: Node) -> void:
	var names := {1: "PENDULUM", 2: "PULSE", 3: "TYPING"}
	var overlay := _find_class(lvl, "LullabyTrainingOverlay")
	var special := _find_named(lvl, "TrainingSpecialButton")
	var typetouch := _find_named(lvl, "TrainingTypingTouch")
	var lineedit := _find_type(lvl, "LineEdit")
	var mechnode: Node = null
	var mechname := ""
	for probe in ["LullabyPendulumServer", "HeartbeatController", "TypingChallenge"]:
		var n := _find_class(lvl, probe)
		if n != null:
			mechnode = n; mechname = probe
	print("OUT %-9s mecanica=%-22s overlay=%s  boton_especial=%s  teclado=%s  LineEdit=%s" % [
		names[mech], (mechname if mechname != "" else "*** NINGUNA ***"),
		"si" if overlay else "*** NO ***",
		"si" if special else "*** NO ***",
		"si" if typetouch else "-", "si" if lineedit else "-"])

	if mechname == "LullabyPendulumServer":
		var vis := _find_class(lvl, "LullabyPendulum")
		var anchor: Node2D = vis.get_node_or_null(^"Anchor") if vis else null
		print("OUT           started=%s dropped=%s  anchor.modulate.a=%.2f (0 = invisible)" % [
			mechnode.started, mechnode.dropped,
			anchor.modulate.a if anchor else -1.0])
	elif mechname == "HeartbeatController":
		var heart := mechnode.get_parent() as Node2D
		print("OUT           beating=%s heart.position=%s (0,0 = linea ECG fuera de pantalla)" % [
			mechnode.beating_enabled, heart.position if heart else Vector2.ZERO])
	elif mechname == "TypingChallenge":
		print("OUT           active=%s prompt=%s show_celebi=%s time_end=%.2f palabra=\"%s\" unowns=%d" % [
			mechnode.active, mechnode.prompt_user, mechnode.show_celebi,
			mechnode.time_end, mechnode.current_word, mechnode.unowns.size()])

	_where(mechname, mechnode)
	if special:
		print("OUT           boton redondo=%s" % [(special as Control).get_global_rect()])

	if overlay:
		var drill: Label = overlay.get_node_or_null(^"Root/Drill")
		var stats: Label = overlay.get_node_or_null(^"Root/Stats")
		print("OUT           overlay drill=\"%s\" fuente_stats=%d" % [
			drill.text if drill else "?",
			stats.get_theme_font_size(&"font_size") if stats else -1])

## Donde cae de verdad cada mecanica, en pixeles del lienzo base (1920x1080,
## centro 960,540). Se leen posiciones de nodo y puntos de Line2D en vez de
## medir sprites, porque en este workspace las texturas no importan y una caja
## de sprite saldria vacia - una posicion de nodo no depende de eso.
func _where(mechname: String, mechnode: Node) -> void:
	var vp: Vector2 = Vector2(1920, 1080)
	match mechname:
		"LullabyPendulumServer":
			var vis: Node = _find_class(mechnode.get_parent(), "LullabyPendulum")
			if vis == null:
				return
			var anchor: Node2D = vis.get_node_or_null(^"Anchor")
			var bob: Node2D = vis.get_node_or_null(^"Anchor/Pendulum")
			var ctrl := vis as Control
			print("OUT           rect del Control=%s  Anchor=%s  Pendulo=%s   centro=%s" % [
				ctrl.get_global_rect(),
				anchor.get_global_transform_with_canvas().origin if anchor else Vector2.ZERO,
				bob.get_global_transform_with_canvas().origin if bob else Vector2.ZERO,
				vp * 0.5])
		"HeartbeatController":
			var heart: Node2D = mechnode.get_parent()
			var line: Line2D = mechnode.line_reference
			var o: Vector2 = heart.get_global_transform_with_canvas().origin
			var lo: Vector2 = line.get_global_transform_with_canvas().origin
			var xs: Array[float] = []
			for i in line.get_point_count():
				xs.append(lo.x + line.get_point_position(i).x)
			xs.sort()
			print("OUT           corazon=%s  linea x=%.0f..%.0f (centro %.0f)   centro pantalla=%s" % [
				o, xs[0], xs[-1], (xs[0] + xs[-1]) * 0.5, vp * 0.5])
		"TypingChallenge":
			for n: String in ["Celebi", "Unowns", "UnownLetters"]:
				var node: Node2D = mechnode.get_node_or_null(NodePath(n))
				if node:
					print("OUT           %-13s %s" % [n, node.get_global_transform_with_canvas().origin])
			print("OUT           centro pantalla=%s" % [vp * 0.5])

func _find_class(root: Node, cls: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var s: Script = n.get_script() as Script
		if s != null and s.get_global_name() == cls:
			return n
		for c in n.get_children(): stack.append(c)
	return null

func _find_named(root: Node, node_name: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == node_name: return n
		for c in n.get_children(): stack.append(c)
	return null

func _find_type(root: Node, type_name: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_class() == type_name: return n
		for c in n.get_children(): stack.append(c)
	return null
