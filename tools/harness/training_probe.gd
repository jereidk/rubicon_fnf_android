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

	if overlay:
		var drill: Label = overlay.get_node_or_null(^"Root/Drill")
		var stats: Label = overlay.get_node_or_null(^"Root/Stats")
		print("OUT           overlay drill=\"%s\" fuente_stats=%d" % [
			drill.text if drill else "?",
			stats.get_theme_font_size(&"font_size") if stats else -1])

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
