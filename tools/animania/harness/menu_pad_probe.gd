# Comprueba el mando de menus: que cada boton manda la tecla que el menu lee.
#
# Lo que hay que demostrar son las dos puntas del camino, no que se dibuje: un dedo en el
# boton -> MenuVirtualPad sintetiza un InputEventKey -> el menu lo recibe por su `_input`
# de siempre. Por eso el arnes se planta encima de un menu DE VERDAD y no de un nodo vacio.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/menu_pad_probe.tscn
extends Node2D

## Por defecto las opciones; se le puede pasar otra escena por `--`.
##
## El menu PRINCIPAL ya no lleva mando -esa pantalla se toca-, asi que apuntarle aqui
## devolveria un FALLO que no lo es. Las que si lo llevan: semanas, creditos, opciones y
## pausa.
##
## Aqui se pulsa SOLO la cruz, nunca A ni B; ver el comentario de `_run`. La pausa ademas no
## se puede probar asi: su `process_mode` es WHEN_PAUSED y aqui el arbol no esta pausado, asi
## que su mando se dibuja pero no recibe nada. De la pausa lo que hay que mirar es otra cosa
## y la mira pad_leak_probe.gd: que su mando NO se vea mientras se juega.
const MENU := "res://animania_mod/menus/options/options_screen.tscn"
const PAD := "res://animania_mod/ui/menu_virtual_pad.tscn"
const SETTLE := 1.2

var _pad: MenuVirtualPad = null
var _seen: Array[int] = []
var _done: bool = false
var _t: float = 0.0
var _name: String = ""


func _ready() -> void:
	# Antes de instanciar el menu: el mando lo lee en su `_ready`.
	Engine.set_meta(&"force_menu_pad", true)
	var path: String = MENU
	for arg: String in OS.get_cmdline_user_args():
		if arg.ends_with(".tscn"):
			path = arg
	_name = path.get_file()
	var menu: Node = (load(path) as PackedScene).instantiate()
	add_child(menu)
	# El de la ESCENA, no uno suelto: lo que se comprueba es el cableado de verdad.
	_pad = menu.find_child("MenuVirtualPad", true, false) as MenuVirtualPad
	if _pad == null:
		print("OUT FALLO: el menu no trae MenuVirtualPad")
		get_tree().quit()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.is_echo():
		_seen.append(key.keycode)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < SETTLE:
		return
	_done = true
	_run()


func _run() -> void:
	# Los botones que TIENE, no una lista fija: cada pantalla lleva la cruz que le hace
	# falta -UP_DOWN en una lista, LEFT_FULL donde tambien se usan los lados- y exigir
	# izquierda y derecha a un menu que no las lee era inventarse un FALLO.
	#
	# Y SOLO la cruz. Pulsar A o B aqui es pegarse un tiro en el pie: son aceptar y volver,
	# el menu cambia de escena, y al cambiarla se libera la escena actual... que es ESTE
	# arnes. A partir de ahi `get_tree()` devuelve null, el `await get_tree().process_frame`
	# de la vuelta siguiente peta, y Godot se queda escupiendo
	# `Invalid access to property 'process_frame' on a null instance` hasta que lo mata el
	# timeout. Parecia que el menu de semanas "tardaba tres minutos en cargar"; lo que
	# pasaba es que el arnes se habia muerto en la quinta pulsacion. Cargarlo cuesta 138 ms
	# en headless y 1.3 s con pintura, medido aparte.
	#
	# La primera version se libraba por casualidad: recorria una lista fija que dejaba la B
	# la ULTIMA, justo antes de salir. Al pasar a recorrer los botones que el mando tiene de
	# verdad, el orden cambio, la B quedo en medio y el arnes empezo a colgarse.
	#
	# A y B se comprueban en pad_layout_probe.gd, que monta el mando sin menu detras y por
	# tanto no tiene a donde irse.
	var wanted := MenuVirtualPad.KEYS
	var bad: int = 0
	print("OUT %s: cruz %s, acciones %s -> %s" % [_name, _pad.dpad, _pad.action,
		str(_pad._rects.keys())])
	var dirs: Array[StringName] = []
	for id: StringName in _pad._rects:
		if id in [&"up", &"down", &"left", &"right"]:
			dirs.append(id)
	for id: StringName in dirs:
		var rect: Rect2 = _pad._rects[id] as Rect2
		if rect.size == Vector2.ZERO:
			print("OUT %-6s FALLO: no tiene caja" % id)
			bad += 1
			continue
		_seen.clear()
		_tap(rect.get_center(), true)
		await get_tree().process_frame
		var ok: bool = _seen.has(wanted[id])
		if not ok:
			bad += 1
		print("OUT %-6s caja %s  teclas=%s  esperada=%d  %s" % [id, str(rect.position),
			str(_seen), wanted[id], "OK" if ok else "FALLO"])
		_tap(rect.get_center(), false)
		await get_tree().process_frame

	# Dos dedos a la vez, que es lo que rompe un mando mal hecho. Arriba y abajo, que estan
	# en las dos cruces y ninguno se lleva el menu por delante.
	_seen.clear()
	_tap((_pad._rects[&"up"] as Rect2).get_center(), true, 0)
	_tap((_pad._rects[&"down"] as Rect2).get_center(), true, 1)
	await get_tree().process_frame
	var both: bool = _seen.has(KEY_UP) and _seen.has(KEY_DOWN)
	print("OUT dos dedos a la vez: %s  %s" % [str(_seen), "OK" if both else "FALLO"])
	if not both:
		bad += 1
	_tap(Vector2.ZERO, false, 0)
	_tap(Vector2.ZERO, false, 1)
	await get_tree().process_frame

	# Las cajas de la cruz se solapan 27 px por el paso de 105 sobre botones de 132. Que se
	# solapen no es el problema; el problema seria que el centro de un boton cayera dentro
	# de otro, porque entonces no hay forma de darle. Se comprueba a proposito.
	for id: StringName in dirs:
		var mine: Rect2 = _pad._rects[id] as Rect2
		var got: StringName = _pad._hit(mine.get_center())
		if got != id:
			print("OUT %-6s FALLO: su centro cae en %s" % [id, got])
			bad += 1

	await RenderingServer.frame_post_draw
	var path: String = "user://menu_pad_%s.png" % _name.get_basename()
	get_viewport().get_texture().get_image().save_png(path)
	print("OUT %s" % ProjectSettings.globalize_path(path))
	print("OUT %s fallos=%d" % [_name, bad])
	get_tree().quit()


func _tap(at: Vector2, pressed: bool, finger: int = 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = finger
	ev.position = at
	ev.pressed = pressed
	Input.parse_input_event(ev)
