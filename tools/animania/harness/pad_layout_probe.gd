# El mando SOLO, sin menu detras: comprueba las cuatro combinaciones que se usan.
#
# Por que separado de menu_pad_probe.gd: aquel instancia una pantalla de verdad para
# demostrar el cableado -dedo -> tecla -> menu- y eso cuesta cargar todo su arte, mas de un
# minuto por escena. La COLOCACION no necesita nada de eso, y es lo que cambia a menudo.
# Aqui se monta el mando a pelo y se mide en segundos.
#
# Lo que comprueba, por combinacion:
#   - que estan exactamente los botones que toca y ninguno mas
#   - que cada caja cae donde dice FlxVirtualPad.hx, escalado de 1280x720 a la pantalla
#   - que el centro de cada boton no cae dentro de otro (las cajas se solapan 27 px)
#   - que un dedo en el centro manda la tecla que el menu espera
# Y guarda un PNG de cada una para poder mirarlas.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/pad_layout_probe.tscn
extends Node2D

## Las combinaciones que usan las pantallas, con el nombre de quien la usa.
const CASES := [
	["LEFT_FULL", "A_B_TOP", "options_screen"],
	["UP_DOWN", "A_B_TOP", "credits_menu / pause_menu"],
]
## Las esquinas de FlxVirtualPad.hx tal cual, para comprobar contra ellas y no contra la
## misma tabla que usa el mando -si no, esto solo comprobaria que sabe copiar-.
const REF := {
	"LEFT_FULL": {
		&"up": Vector2(105.0, 720.0 - 345.0), &"left": Vector2(0.0, 720.0 - 243.0),
		&"right": Vector2(207.0, 720.0 - 243.0), &"down": Vector2(105.0, 720.0 - 135.0),
	},
	"UP_DOWN": {&"up": Vector2(0.0, 720.0 - 255.0), &"down": Vector2(0.0, 720.0 - 135.0)},
	"A_B": {
		&"b": Vector2(1280.0 - 258.0, 720.0 - 135.0),
		&"a": Vector2(1280.0 - 132.0, 720.0 - 135.0),
	},
	# La misma fila colgada de arriba: 87 px por debajo del borde, que deja libre la franja
	# del marcador.
	"A_B_TOP": {
		&"b": Vector2(1280.0 - 258.0, 87.0),
		&"a": Vector2(1280.0 - 132.0, 87.0),
	},
}

var _bad: int = 0
var _seen: Array[int] = []
var _done: bool = false


func _ready() -> void:
	Engine.set_meta(&"force_menu_pad", true)
	# Un fondo liso para que el PNG se vea: el mando es gris teñido y sobre negro se pierde
	# lo oscuro de cada boton. Con el tamaño puesto A MANO: colgando de un Node2D, los
	# anclajes de un Control no tienen contra que anclarse y salia de 0x0 -o sea, negro-.
	var bg := ColorRect.new()
	bg.size = get_viewport().get_visible_rect().size
	bg.color = Color(0.42, 0.40, 0.48)
	add_child(bg)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.is_echo():
		_seen.append(key.keycode)


func _process(_delta: float) -> void:
	if _done:
		return
	_done = true
	_run()


func _run() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var k: float = minf(size.x / 1280.0, size.y / 720.0)
	print("OUT pantalla %s, escala %.3f, boton %dx%d" % [str(size), k,
		int(132.0 * k), int(127.0 * k)])

	for spec: Array in CASES:
		var pad := MenuVirtualPad.new()
		pad.dpad = spec[0] as String
		pad.action = spec[1] as String
		add_child(pad)
		await get_tree().process_frame
		print("OUT ── %s + %s   (%s)" % [spec[0], spec[1], spec[2]])

		# Los que TIENE contra los que TOCA.
		var want: Dictionary = {}
		for id: StringName in (REF[spec[0]] as Dictionary):
			want[id] = (REF[spec[0]] as Dictionary)[id]
		for id: StringName in (REF[spec[1]] as Dictionary):
			want[id] = (REF[spec[1]] as Dictionary)[id]
		var have: Array = pad._rects.keys()
		_check(have.size() == want.size(), "botones: %s" % str(have))

		for id: StringName in want:
			var rect: Rect2 = pad._rects.get(id, Rect2()) as Rect2
			var at: Vector2 = (want[id] as Vector2) * k
			var off: float = rect.position.distance_to(at)
			_check(off < 0.51, "%-6s en %s, tocaba %s" % [id, str(rect.position), str(at)])

		for id: StringName in pad._rects:
			var mine: Rect2 = pad._rects[id] as Rect2
			var got: StringName = pad._hit(mine.get_center())
			_check(got == id, "%-6s su centro da en %s" % [id, got])

			_seen.clear()
			_tap(mine.get_center(), true)
			await get_tree().process_frame
			_check(_seen.has(MenuVirtualPad.KEYS[id]),
				"%-6s manda %s, esperaba %d" % [id, str(_seen), MenuVirtualPad.KEYS[id]])
			_tap(mine.get_center(), false)
			await get_tree().process_frame

		await RenderingServer.frame_post_draw
		var path: String = "user://pad_%s_%s.png" % [spec[0], spec[1]]
		get_viewport().get_texture().get_image().save_png(path)
		print("OUT %s" % ProjectSettings.globalize_path(path))
		pad.queue_free()
		await get_tree().process_frame

	print("OUT fallos=%d" % _bad)
	get_tree().quit()


func _tap(at: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = at
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _check(ok: bool, detail: String) -> void:
	if not ok:
		_bad += 1
	print("OUT   %-52s %s" % [detail, "OK" if ok else "FALLO"])
