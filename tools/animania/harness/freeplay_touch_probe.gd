# Comprueba que freeplay se maneja ENTERO con el dedo, ahora que no lleva mando.
#
# Lo que hay que demostrar son las cuatro acciones y en el sitio donde de verdad cae el
# dedo, no llamando a los metodos: se toca el centro de cada caja y se mira que cambia.
#
#   flecha izquierda -> el disco elegido retrocede
#   flecha derecha   -> avanza
#   flecha de abajo  -> cambia la dificultad
#   disco elegido    -> confirma (entra en la cancion)
#   otro disco       -> lo trae al frente, NO confirma
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --fixed-fps 60 --path . \
#       res://tools/animania/harness/freeplay_touch_probe.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
## Lo mismo que en slot_shot: el televisor tarda en encender y `allow_input` no llega antes.
const SETTLE := 2.5

var _screen: Node = null
var _t: float = 0.0
var _done: bool = false
var _bad: int = 0


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < SETTLE:
		return
	_done = true
	_run()


func _run() -> void:
	# Fuera del hueco aleatorio: ahi no hay cancion, la dificultad no se mueve y confirmar
	# es otra cosa -capsuleOnConfirmRandom-. Con una cancion de verdad debajo se ve todo.
	_screen.call("change_selection", 1, false)
	await _settle()
	if not bool(_screen.get("allow_input")):
		print("OUT FALLO: la pantalla no acepta entrada todavia")
		get_tree().quit()
		return

	var arrows: Node2D = _screen.get_node(^"Selectors")
	print("OUT partida en disco %d, dificultad %s" % [int(_screen.get("cur_selected")),
		String(_screen.get("current_difficulty"))])

	# 1 y 2: las flechas de los lados mueven el carrusel.
	for spec: Array in [["SongArrowRight", 1], ["SongArrowLeft", -1]]:
		var before: int = int(_screen.get("cur_selected"))
		await _tap_node(arrows.get_node(NodePath(spec[0] as String)))
		var after: int = int(_screen.get("cur_selected"))
		var want: int = wrapi(before + (spec[1] as int), 0,
			(_screen.get("current_filtered_songs") as Array).size())
		_say(spec[0] as String, "%d -> %d (queria %d)" % [before, after, want], after == want)

	# 3: la de abajo del cartel cambia la dificultad.
	var diff_before: String = String(_screen.get("current_difficulty"))
	await _tap_node(arrows.get_node(^"DiffArrow"))
	var diff_after: String = String(_screen.get("current_difficulty"))
	_say("DiffArrow", "%s -> %s" % [diff_before, diff_after], diff_after != diff_before)

	# 4: tocar OTRO disco lo elige y no entra en nada.
	var disks: Node2D = _screen.get("disks")
	var sel: int = int(_screen.get("cur_selected"))
	var other: Node2D = null
	for child: Node in disks.get_children():
		if int((child as Node2D).get_meta(&"index")) == wrapi(sel + 2, 0,
				(_screen.get("current_filtered_songs") as Array).size()):
			other = child as Node2D
	if other != null:
		await _tap_node(other)
		var moved: bool = int(_screen.get("cur_selected")) != sel
		_say("disco de al lado", "elegido %d, confirmado %s" % [
			int(_screen.get("cur_selected")), str(_screen.get("_confirmed"))],
			moved and not bool(_screen.get("_confirmed")))

	# 5: tocar el ELEGIDO confirma. Va el ultimo: despues de esto la pantalla se va.
	var current: Node2D = null
	for child: Node in disks.get_children():
		if int((child as Node2D).get_meta(&"index")) == int(_screen.get("cur_selected")):
			current = child as Node2D
	if current != null:
		await _tap_node(current)
		_say("disco elegido", "confirmado=%s" % str(_screen.get("_confirmed")),
			bool(_screen.get("_confirmed")))

	print("OUT fallos=%d" % _bad)
	get_tree().quit()


## El centro de la caja del dedo, pasado de la escena a la PANTALLA: es al reves de lo que
## hace `_to_world`, y hay que hacerlo porque la camara lleva su `offset` a la deriva.
func _tap_node(node: Node2D) -> void:
	var at: Vector2 = get_viewport().get_canvas_transform() * node.position
	for pressed: bool in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = at
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await _settle()


func _settle() -> void:
	for _i: int in 20:
		await get_tree().process_frame


func _say(what: String, detail: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("OUT %-18s %-34s %s" % [what, detail, "OK" if ok else "FALLO"])
