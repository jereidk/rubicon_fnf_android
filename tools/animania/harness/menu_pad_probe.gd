# Comprueba el mando de menus: que cada boton manda la tecla que el menu lee.
#
# Lo que hay que demostrar son las dos puntas del camino, no que se dibuje: un dedo en el
# boton -> MenuVirtualPad sintetiza un InputEventKey -> el menu lo recibe por su `_input`
# de siempre. Por eso el arnes se planta encima de un menu DE VERDAD y no de un nodo vacio.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/menu_pad_probe.tscn
extends Node2D

## Por defecto el menu principal; se le puede pasar otra escena por `--`.
##
## Dos pantallas NO se pueden probar asi, y conviene saberlo antes de creerse un FALLO suyo:
## los creditos, porque aceptar o volver los saca de pantalla y el arnes se queda esperando
## a una escena que ya se fue; y la pausa, porque su `process_mode` es WHEN_PAUSED y aqui el
## arbol no esta pausado, asi que su mando se dibuja pero no recibe nada. Para la pausa lo
## que hay que mirar es otra cosa y la mira pad_leak_probe.gd: que su mando NO se vea
## mientras se juega.
const MENU := "res://animania_mod/menus/main/main_menu.tscn"
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
	var wanted := {
		&"up": KEY_UP, &"down": KEY_DOWN, &"left": KEY_LEFT, &"right": KEY_RIGHT,
		&"a": KEY_ENTER, &"b": KEY_ESCAPE,
	}
	var bad: int = 0
	for id: StringName in wanted:
		var rect: Rect2 = _pad._rects.get(id, Rect2()) as Rect2
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

	# Un dedo en dos botones a la vez, que es lo que rompe un mando mal hecho.
	_seen.clear()
	_tap((_pad._rects[&"up"] as Rect2).get_center(), true, 0)
	_tap((_pad._rects[&"a"] as Rect2).get_center(), true, 1)
	await get_tree().process_frame
	var both: bool = _seen.has(KEY_UP) and _seen.has(KEY_ENTER)
	print("OUT dos dedos a la vez: %s  %s" % [str(_seen), "OK" if both else "FALLO"])
	if not both:
		bad += 1
	_tap(Vector2.ZERO, false, 0)
	_tap(Vector2.ZERO, false, 1)
	await get_tree().process_frame

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
