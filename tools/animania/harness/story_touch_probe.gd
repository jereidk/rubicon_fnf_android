# El menu de semanas se maneja ENTERO con lo que ya hay dibujado, sin mando. Esto lo
# demuestra tocando cada cosa y mirando que cambia:
#
#   flecha derecha / izquierda  -> cambia la dificultad, y NO entra en la semana
#   titulo de otra semana       -> la elige, y NO entra
#   titulo de la ya elegida     -> no hace nada (el confirmar tiene su sitio)
#   BF                          -> entra en la semana elegida
#
# Y que la pantalla no lleva mando, que es la otra mitad de la decision: si alguien se lo
# vuelve a colgar, esto lo dice.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --fixed-fps 60 --path . \
#       res://tools/animania/harness/story_touch_probe.tscn
extends Node2D

const MENU := "res://animania_mod/menus/story/story_menu.tscn"
const SETTLE := 1.5

var _menu: Node = null
var _t: float = 0.0
var _done: bool = false
var _bad: int = 0


func _ready() -> void:
	Engine.set_meta(&"force_menu_pad", true)
	_menu = (load(MENU) as PackedScene).instantiate()
	add_child(_menu)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < SETTLE:
		return
	_done = true
	_run()


func _run() -> void:
	var to_screen: Transform2D = get_viewport().get_canvas_transform()

	# ── 1. las flechas cambian la dificultad ──────────────────────────────
	for spec: Array in [["RightArrow", 1], ["LeftArrow", -1]]:
		var arrow := _menu.get_node(NodePath(spec[0] as String)) as AnimatedSprite2D
		var before: String = String(_menu.get("current_difficulty_id"))
		await _tap(to_screen * arrow.position)
		var after: String = String(_menu.get("current_difficulty_id"))
		# Que NO se haya confirmado importa tanto como el cambio: cuando la caja de la A
		# estaba encima de la flecha derecha, tocarla cambiaba la dificultad Y entraba en
		# la semana, y desde ahi `change_difficulty` ya no hacia nada por el `_confirmed`.
		# Asi es como se vio: la segunda flecha "no respondia".
		if bool(_menu.get("_confirmed")):
			print("OUT   FALLO: el toque en la flecha ha CONFIRMADO la semana")
			_bad += 1
		_say(spec[0] as String, "%s -> %s" % [before, after], after != before)

	# ── 2. tocar otra semana la elige, la ya elegida no hace nada ─────────
	var titles: Node2D = _menu.get("titles") as Node2D
	var before_level: int = int(_menu.get("selected_level"))
	var other: int = wrapi(before_level + 1, 0, int(_menu.call("week_count")))
	await _tap(to_screen * (titles.get_child(other) as Node2D).position)
	_say("otra semana", "%d -> %d" % [before_level, int(_menu.get("selected_level"))],
		int(_menu.get("selected_level")) == other and not bool(_menu.get("_confirmed")))

	await _tap(to_screen * (titles.get_child(other) as Node2D).position)
	_say("la ya elegida", "confirmado=%s" % str(_menu.get("_confirmed")),
		not bool(_menu.get("_confirmed")))

	# La foto va AQUI y no al final: despues de tocar a BF la pantalla ya esta entrando en
	# la semana -suena el confirmar y los props se animan- y lo que se guardaria es eso.
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://story_touch.png")
	print("OUT %s" % ProjectSettings.globalize_path("user://story_touch.png"))

	# ── 3. BF es el entrar ────────────────────────────────────────────────
	#
	# Antes hay que pararse en una semana QUE SE PUEDA JUGAR. `select_level` se planta y
	# suena el candado si la semana no tiene ni una cancion construida -linea 367-, y en
	# este puerto la unica construida es tutorial. Sin esto, el arnes tocaba a BF en Week5
	# y culpaba al toque de lo que era una semana bloqueada.
	for step: int in int(_menu.call("week_count")):
		var title: Node2D = titles.get_child(int(_menu.get("selected_level")))
		if not (_menu.call("get_songs_filtered", title) as PackedStringArray).is_empty():
			break
		_menu.call("change_level", 1, false)
		await _settle()
	print("OUT jugable: semana %d" % int(_menu.get("selected_level")))

	var bf: Node2D = null
	for prop: Node in _menu.get("_active_props"):
		if bool((prop as Node2D).get_meta(&"is_player", false)):
			bf = prop as Node2D
	if bf == null:
		print("OUT BF                 FALLO: ningun prop dice ser el jugador")
		_bad += 1
	else:
		await _tap(to_screen * bf.position)
		_say("BF", "confirmado=%s" % str(_menu.get("_confirmed")),
			bool(_menu.get("_confirmed")))

	# ── 4. y esta pantalla no lleva mando ─────────────────────────────────
	var pad := _menu.find_child("MenuVirtualPad", true, false)
	_say("sin mando", "encontrado=%s" % str(pad != null), pad == null)

	print("OUT fallos=%d" % _bad)
	get_tree().quit()


func _settle() -> void:
	for _i: int in 10:
		await get_tree().process_frame


func _tap(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = at
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
	for _i: int in 10:
		await get_tree().process_frame


func _say(what: String, detail: String, ok: bool) -> void:
	if not ok:
		_bad += 1
	print("OUT %-18s %-26s %s" % [what, detail, "OK" if ok else "FALLO"])
