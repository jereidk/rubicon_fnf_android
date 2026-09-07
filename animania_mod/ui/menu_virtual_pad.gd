class_name MenuVirtualPad
extends CanvasLayer
## El mando en pantalla para moverse por los menus en un movil.
##
## Esto NO sale del binario, y conviene decirlo antes que nada: el mod es una compilacion de
## escritorio y no tiene controles tactiles. Es una pieza del puerto, con sus decisiones
## tomadas aqui y no leidas de ningun sitio.
##
## Por que hace falta si los menus YA responden al tacto: porque tocar el elemento no es lo
## mismo que navegar, y hay media docena de pantallas donde no hay elemento que tocar -las
## listas de opciones, el selector de semana, los creditos, la pausa-. Ahi el mando es la
## unica forma de moverse sin teclado. Donde SI hay rectangulos con su `_touch` no se pone:
## el menu principal esta pensado para tocarlo -sus placas y el disco de la OST responden al
## dedo- y freeplay igual, con sus discos y sus tres flechas. En los dos, taparlo con un
## mando seria repetir con botones lo que la pantalla ya hace mejor, y ademas taparle el
## arte: la toma de freeplay con el mando encendido lo enseñaba encima del disco aleatorio,
## del de tutorial y de una esquina del mueble del televisor. Los `_touch` que ya existen se
## quedan como estan; esto es lo de al lado, para donde no los hay, no un sustituto.
##
## Como llega la pulsacion al menu: sintetizando un InputEventKey con
## `Input.parse_input_event`, igual que hacen los controles de la partida. Los menus de este
## puerto leen `InputEventKey` con su `keycode` a pelo -KEY_UP, KEY_ENTER, KEY_ESCAPE...-,
## no acciones con nombre, asi que una tecla sintetica les vale y no hay que tocar ni un
## menu para que esto funcione. Lo comprueba `tools/animania/harness/menu_pad_probe.gd`.
##
## El arte es el `virtualpad` de Indie Cross (jereidk/Indie-Cross-Public), que en su repo
## viaja ya comprimido a ASTC; aqui va el PNG de antes de esa conversion. Cada boton son
## tres fotogramas de 132x127 -reposo y dos de pulsado- y el dibujo es gris: el color lo
## pone `modulate`, que es como lo tinta el FlxVirtualPad del que viene.

# ─── Arte ──────────────────────────────────────────────────────────────────

const ATLAS := "res://animania_mod/source/images/virtualpad/virtualpad.png"
const FRAME := Vector2i(132, 127)
## Fila del atlas por boton, y columna 0/1/2 = reposo / pulsado / pulsado.
const ROWS := {
	&"left": 0, &"down": 0, &"up": 0, &"right": 0,
	&"a": 1, &"b": 1, &"c": 1, &"d": 1,
}
const COLS := {
	&"left": 0, &"down": 1, &"up": 2, &"right": 3,
	&"a": 0, &"b": 1, &"c": 2, &"d": 3,
}

# ─── Que hace cada boton ───────────────────────────────────────────────────

## La tecla que sintetiza cada boton. Son las que ya leen los menus.
const KEYS := {
	&"up": KEY_UP, &"down": KEY_DOWN, &"left": KEY_LEFT, &"right": KEY_RIGHT,
	&"a": KEY_ENTER, &"b": KEY_ESCAPE, &"c": KEY_SPACE, &"d": KEY_SHIFT,
}
## Los colores del mando de Indie Cross: verde arriba, azul abajo, y a la derecha
## rojo para aceptar y amarillo para volver.
const TINTS := {
	&"up": Color(0.20, 1.00, 0.35), &"down": Color(0.20, 0.72, 1.00),
	&"left": Color(0.85, 0.35, 1.00), &"right": Color(1.00, 0.42, 0.42),
	&"a": Color(1.00, 0.30, 0.30), &"b": Color(1.00, 0.85, 0.20),
	&"c": Color(0.35, 1.00, 0.35), &"d": Color(0.80, 0.80, 0.80),
}

# ─── Colocacion ────────────────────────────────────────────────────────────

## Lado de un boton en pantalla, en pixeles del viewport de 1920x1080.
const BUTTON := 132.0
## Separacion entre botones, de borde a borde.
const GAP := 18.0
## Margen desde el borde de la pantalla.
const MARGIN := Vector2(46.0, 46.0)
## La caja que responde al dedo es mayor que el dibujo: en un movil el pulgar no aterriza
## en el centro. Un 30% de mas por lado, que es lo que separa "le he dado" de "casi".
const TOUCH_GROW := 1.30

## Que botones lleva cada pantalla. `Vertical` es una lista de arriba a abajo -la pausa-;
## `Full` anade izquierda y derecha, que las semanas, los creditos y las opciones usan para
## moverse y para cambiar el valor.
@export_enum("Vertical", "Full") var layout: String = "Vertical"
@export_range(0.1, 1.0, 0.05) var opacity: float = 0.55
## Se apaga solo donde no hay dedos. Un mando dibujado sobre un monitor sobra, y en el
## editor estorba para colocar lo demas.
@export var only_on_touch: bool = true

var _buttons: Dictionary = {}      ## StringName -> TextureRect
var _rects: Dictionary = {}        ## StringName -> Rect2 (la caja del dedo)
var _held: Dictionary = {}         ## indice de dedo -> StringName
var _root: Control = null


func _ready() -> void:
	if only_on_touch and not _is_touch_device():
		hide()
		set_process_input(false)
		return

	layer = 80  # por encima de los menus, por debajo de las transiciones
	_follow_parent()
	_root = Control.new()
	_root.name = "PadRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.resized.connect(_layout)
	_build()
	_layout()


## Un CanvasLayer NO hereda la visibilidad de quien lo cuelga: para el servidor de render
## son capas hermanas, y `visible = false` en el padre no apaga al hijo. Con el menu de
## pausa eso se ve enseguida -nace oculto y el mando se quedaba pintado encima de la
## partida-, y lo mismo vale para cualquier menu que se esconda en vez de descargarse.
## Medido antes de arreglarlo con pad_leak_probe.gd: pausa visible=false, mando visible=true.
func _follow_parent() -> void:
	var parent: Node = get_parent()
	if parent == null or not (parent is CanvasLayer or parent is CanvasItem):
		return
	visible = bool(parent.get("visible"))
	parent.visibility_changed.connect(func() -> void:
		visible = bool(parent.get("visible")))


## En escritorio tambien vale el raton, que es como se prueba esto sin un telefono delante.
##
## El `force_menu_pad` de Engine es el interruptor para eso: los arneses lo ponen antes de
## instanciar el menu y asi pueden comprobar el mando en una maquina sin pantalla tactil.
## Sin el no habria forma de probar esto automaticamente, que es tanto como no probarlo.
func _is_touch_device() -> bool:
	if Engine.has_meta(&"force_menu_pad"):
		return bool(Engine.get_meta(&"force_menu_pad"))
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func _build() -> void:
	var names: Array[StringName] = [&"up", &"down", &"a", &"b"]
	if layout == "Full":
		names = [&"up", &"down", &"left", &"right", &"a", &"b"]
	var atlas: Texture2D = load(ATLAS)
	for id: StringName in names:
		var button := TextureRect.new()
		button.name = String(id).to_upper()
		button.texture = _frame(atlas, id, 0)
		button.modulate = TINTS[id]
		button.modulate.a = opacity
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.size = Vector2(BUTTON, BUTTON)
		_root.add_child(button)
		_buttons[id] = button


func _frame(atlas: Texture2D, id: StringName, state: int) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	tex.region = Rect2(
		float(COLS[id] * 3 + state) * float(FRAME.x),
		float(ROWS[id]) * float(FRAME.y),
		float(FRAME.x), float(FRAME.y))
	# Sin esto los botones de al lado se cuelan por el borde al escalar.
	tex.filter_clip = true
	return tex


## Los de moverse a la izquierda y los de actuar a la derecha, que es como se sujeta un
## movil en apaisado y como lo pone el mando de Indie Cross del que sale el arte.
func _layout() -> void:
	if _root == null:
		return
	var size: Vector2 = _root.size
	if size == Vector2.ZERO:
		size = get_viewport().get_visible_rect().size
	var step: float = BUTTON + GAP
	var bottom: float = size.y - MARGIN.y - BUTTON

	var places := {
		&"up": Vector2(MARGIN.x + step, bottom - step),
		&"down": Vector2(MARGIN.x + step, bottom),
		&"left": Vector2(MARGIN.x, bottom),
		&"right": Vector2(MARGIN.x + step * 2.0, bottom),
		&"b": Vector2(size.x - MARGIN.x - step * 2.0 + GAP, bottom),
		&"a": Vector2(size.x - MARGIN.x - BUTTON, bottom),
	}
	_rects.clear()
	for id: StringName in _buttons:
		var button := _buttons[id] as TextureRect
		button.position = places[id]
		var grow: float = BUTTON * (TOUCH_GROW - 1.0) * 0.5
		_rects[id] = Rect2(button.position - Vector2(grow, grow),
			Vector2(BUTTON + grow * 2.0, BUTTON + grow * 2.0))


# ─── Dedos ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_press(touch.index, _hit(touch.position))
		else:
			_press(touch.index, &"")
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		# Arrastrar de un boton a otro cambia de boton, no se queda pegado al primero.
		if _held.has(drag.index):
			_press(drag.index, _hit(drag.position))
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		_press(-1, _hit(click.position) if click.pressed else &"")


func _hit(at: Vector2) -> StringName:
	for id: StringName in _rects:
		if (_rects[id] as Rect2).has_point(at):
			return id
	return &""


func _press(finger: int, id: StringName) -> void:
	var before: StringName = _held.get(finger, &"") as StringName
	if before == id:
		return
	if before != &"":
		_held.erase(finger)
		if not _is_held(before):
			_send(before, false)
			_paint(before, false)
	if id == &"":
		return
	var already: bool = _is_held(id)
	_held[finger] = id
	if not already:
		_send(id, true)
		_paint(id, true)


func _is_held(id: StringName) -> bool:
	for other: StringName in _held.values():
		if other == id:
			return true
	return false


func _paint(id: StringName, down: bool) -> void:
	var button := _buttons.get(id) as TextureRect
	if button == null:
		return
	button.texture = _frame(load(ATLAS), id, 1 if down else 0)
	button.modulate.a = minf(opacity * 1.7, 1.0) if down else opacity


func _send(id: StringName, down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEYS[id]
	key.physical_keycode = KEYS[id]
	key.pressed = down
	Input.parse_input_event(key)
