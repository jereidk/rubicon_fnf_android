# El menu de semanas: que se maneje con el dedo y que el mando no tape la dificultad.
#
# Dos cosas que hay que DEMOSTRAR, no suponer:
#   1. tocar las flechas de los lados del cartel cambia la dificultad, y tocar un titulo de
#      semana lo elige (tocar el ya elegido entra, que eso ya estaba)
#   2. ninguna caja del mando pisa el cartel de la dificultad ni sus dos flechas
#
# Lo segundo es la parte que se me escapaba mirando capturas: "no tapa" es una condicion
# entre rectangulos y se puede medir, asi que se mide.
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

	# ── 2. tocar una semana la elige ──────────────────────────────────────
	var titles: Node2D = _menu.get("titles") as Node2D
	var before_level: int = int(_menu.get("selected_level"))
	var other: int = wrapi(before_level + 1, 0, int(_menu.call("week_count")))
	await _tap(to_screen * (titles.get_child(other) as Node2D).position)
	_say("titulo de semana", "%d -> %d" % [before_level, int(_menu.get("selected_level"))],
		int(_menu.get("selected_level")) == other)

	# ── 3. el mando no tapa la dificultad ─────────────────────────────────
	var pad := _menu.find_child("MenuVirtualPad", true, false) as MenuVirtualPad
	if pad == null:
		print("OUT (esta pantalla no lleva mando)")
	else:
		print("OUT mando: cruz %s, acciones %s" % [pad.dpad, pad.action])
		var guard := {}
		for name: String in ["DifficultySprite", "DiffSelector", "LeftArrow", "RightArrow"]:
			var node := _menu.get_node_or_null(NodePath(name)) as Node2D
			if node == null or not node.visible:
				continue
			guard[name] = _rect_of(node, to_screen)
		for id: StringName in pad._rects:
			var box: Rect2 = pad._rects[id] as Rect2
			for name: String in guard:
				var over: Rect2 = box.intersection(guard[name] as Rect2)
				var area: float = over.size.x * over.size.y
				if area > 0.0:
					print("OUT   %-6s pisa %-16s %d px2" % [id, name, int(area)])
					_bad += 1
		print("OUT   el mando %s la dificultad" % ["NO tapa" if _bad == 0 else "TAPA"])

	print("OUT fallos=%d" % _bad)
	get_tree().quit()


## El rectangulo que ocupa un Node2D en la PANTALLA. Los sprites de esta pantalla van
## centrados, asi que su caja va alrededor de la posicion y no desde ella.
func _rect_of(node: Node2D, to_screen: Transform2D) -> Rect2:
	var size := Vector2.ZERO
	var sprite := node as Sprite2D
	if sprite != null and sprite.texture != null:
		size = sprite.texture.get_size() * sprite.scale
	var anim := node as AnimatedSprite2D
	if anim != null and anim.sprite_frames != null:
		var tex: Texture2D = anim.sprite_frames.get_frame_texture(anim.animation, 0)
		if tex != null:
			size = tex.get_size() * anim.scale
	var at: Vector2 = to_screen * (node.position - size * 0.5)
	return Rect2(at, size)


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
