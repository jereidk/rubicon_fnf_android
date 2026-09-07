class_name MenuVirtualPad
extends CanvasLayer
## El mando en pantalla para moverse por los menus en un movil.
##
## Esto NO sale del binario de Animania, y conviene decirlo antes que nada: el mod es una
## compilacion de escritorio y no tiene controles tactiles.
##
## Pero tampoco es invencion mia. La colocacion, los colores y la opacidad estan LEIDOS de
## `source/android/flixel/FlxVirtualPad.hx` de Indie Cross (jereidk/Indie-Cross-Public), que
## es el mando que se tomo de referencia, y sus numeros van copiados tal cual mas abajo. La
## primera version de este archivo se los invento -un margen, un hueco, una cruz puesta a
## ojo- y salio una cruz con el ABAJO en medio de la fila, que es justo lo que un pulgar no
## espera. Habiendo fuente, no hay por que adivinar.
##
## Por que hace falta si los menus YA responden al tacto: porque tocar el elemento no es lo
## mismo que navegar, y hay pantallas donde no hay elemento que tocar -las listas de
## opciones, el selector de semana, los creditos, la pausa-. Ahi el mando es la unica forma
## de moverse sin teclado. Donde SI hay rectangulos con su `_touch` no se pone: el menu
## principal esta pensado para tocarlo -sus placas y el disco de la OST responden al dedo- y
## freeplay igual, con sus discos y sus tres flechas. En los dos, un mando encima repetiria
## con botones lo que la pantalla ya hace mejor, y ademas taparia el arte.
##
## Como llega la pulsacion al menu: sintetizando un InputEventKey con
## `Input.parse_input_event`. Los menus de este puerto leen `InputEventKey` con su `keycode`
## a pelo -KEY_UP, KEY_ENTER, KEY_ESCAPE...- y las opciones leen las acciones `ui_*`; a las
## dos cosas les vale una tecla sintetica, asi que no hay que tocar ni un menu para que esto
## funcione. Lo comprueba `tools/animania/harness/menu_pad_probe.gd`.
##
## El arte es el `virtualpad` de ese mismo repo, que alli viaja ya comprimido a ASTC; aqui
## va el PNG de antes de esa conversion. Son 16 botones de tres fotogramas -reposo y dos de
## pulsado- y el dibujo es GRIS: el color lo pone `modulate`, igual que el `button.color` de
## FlxVirtualPad.

# ─── Arte ──────────────────────────────────────────────────────────────────

const ATLAS := "res://animania_mod/source/images/virtualpad/virtualpad.png"
## El sparrow del atlas. Los recortes se leen de AQUI y no de una tabla escrita a mano:
## `createButton` los pide por nombre (`left`, `a`...) y los fotogramas se llaman
## `<id>_idle0`, `<id>_press1` y `<id>_press2`. Una tabla de filas y columnas paralela al
## XML es una copia que se puede desincronizar sin avisar.
const ATLAS_XML := "res://animania_mod/source/images/virtualpad/virtualpad.xml"

# ─── Los numeros de FlxVirtualPad.hx ───────────────────────────────────────
#
# Su juego mide 1280x720 (Project.xml, `<window width="1280" height="720">`) y las esquinas
# van escritas contra `FlxG.width` / `FlxG.height`, o sea contra los bordes. Se guardan aqui
# igual: la cruz medida desde la esquina de ABAJO A LA IZQUIERDA y los botones de accion
# desde la de ABAJO A LA DERECHA, que es como sobreviven a cualquier proporcion de pantalla.
#
#   case LEFT_FULL:
#     up    (105, H-345)   left  (0, H-243)   right (207, H-243)   down  (105, H-135)
#   case UP_DOWN:
#     up    (0, H-255)     down  (0, H-135)
#   case LEFT_RIGHT:
#     left  (0, H-135)     right (127, H-135)
#   case A_B:
#     b     (W-258, H-135) a     (W-132, H-135)
#
# La cruz de LEFT_FULL es una cruz DE VERDAD: arriba encima, izquierda y derecha en la fila
# de en medio, abajo debajo. Los tres de la fila de en medio se solapan 27 px con el de
# arriba y el de abajo -132 de ancho con pasos de 105-, que en el dibujo no se nota porque
# el fotograma trae aire de sobra alrededor del glifo.
const REF_SCREEN := Vector2(1280.0, 720.0)
const REF_BUTTON := Vector2(132.0, 127.0)

## Cruz -> boton -> esquina, en el espacio de 1280x720 y contra la esquina de abajo a la
## izquierda: la x tal cual y la y como "tantos pixeles POR ENCIMA del borde de abajo".
const DPADS := {
	"NONE": {},
	"UP_DOWN": {&"up": Vector2(0.0, 255.0), &"down": Vector2(0.0, 135.0)},
	"LEFT_RIGHT": {&"left": Vector2(0.0, 135.0), &"right": Vector2(127.0, 135.0)},
	"LEFT_FULL": {
		&"up": Vector2(105.0, 345.0), &"left": Vector2(0.0, 243.0),
		&"right": Vector2(207.0, 243.0), &"down": Vector2(105.0, 135.0),
	},
}
## Acciones -> boton -> esquina, contra la de abajo a la DERECHA: "tantos pixeles a la
## izquierda del borde derecho" y "tantos por encima del de abajo".
const ACTIONS := {
	"NONE": {},
	"A": {&"a": Vector2(132.0, 135.0)},
	"B": {&"b": Vector2(132.0, 135.0)},
	"A_B": {&"b": Vector2(258.0, 135.0), &"a": Vector2(132.0, 135.0)},
	# Tampoco sale de alli: la misma fila, pero colgada de ARRIBA a la derecha.
	#
	# Abajo a la derecha es donde la referencia las pone y donde mejor cae el pulgar, pero
	# en esta pantalla es justo donde vive el cartel de la dificultad, y no de refilon:
	# story_touch_probe.gd lo midio en pixeles -la B pisaba 20196 px2 del cartel, la A 2065
	# mas 1262 de la flecha derecha-. Y no era solo taparlo: la caja de la A se comia el
	# toque de la flecha, asi que tocar la flecha para cambiar de dificultad ENTRABA en la
	# semana. Lo pillo el arnes, no la vista.
	#
	# El 633 es 720-87: 87 px por debajo del borde de arriba en el espacio de la
	# referencia, que a 1920x1080 son 130 y dejan libre la franja negra del marcador -76 de
	# alto, 114 en pantalla-.
	"A_B_TOP": {&"b": Vector2(258.0, 633.0), &"a": Vector2(132.0, 633.0)},
}

## Los `button.color` de createButton, en el mismo orden en que salen alli. No son los que
## yo habia puesto a ojo: el de la izquierda es MAGENTA puro y el de abajo CIAN puro, que
## son los colores de las notas de Funkin, no un morado y un azul cualesquiera.
const TINTS := {
	&"up": Color8(0x00, 0xFF, 0x00), &"left": Color8(0xFF, 0x00, 0xFF),
	&"right": Color8(0xFF, 0x00, 0x00), &"down": Color8(0x00, 0xFF, 0xFF),
	&"a": Color8(0xFF, 0x00, 0x00), &"b": Color8(0xFF, 0xCB, 0x00),
	&"c": Color8(0x44, 0xFF, 0x00), &"d": Color8(0x00, 0x78, 0xFF),
}

## La tecla que sintetiza cada boton. Son las que ya leen los menus.
const KEYS := {
	&"up": KEY_UP, &"down": KEY_DOWN, &"left": KEY_LEFT, &"right": KEY_RIGHT,
	&"a": KEY_ENTER, &"b": KEY_ESCAPE, &"c": KEY_SPACE, &"d": KEY_SHIFT,
}

# ─── Que lleva cada pantalla ───────────────────────────────────────────────
#
# Los nombres son los del enum de FlxVirtualPad para que se puedan comparar de un vistazo
# con lo que hace cada pantalla alli. Lo que decide cual va en cada sitio no es la moda: es
# que teclas LEE ese menu. Un boton que no hace nada estorba mas que ayuda.

@export_enum("NONE", "UP_DOWN", "LEFT_RIGHT", "LEFT_FULL") var dpad: String = "UP_DOWN"
@export_enum("NONE", "A", "B", "A_B", "A_B_TOP") var action: String = "A_B_TOP"
## Alli `AndroidControls.getOpacity(false)` devuelve 0.6. Aqui va a 0.5: el arte de estos
## menus llega hasta los bordes y el mando esta encima de el, no sobre un fondo liso.
@export_range(0.1, 1.0, 0.05) var opacity: float = 0.5
## Se apaga solo donde no hay dedos. Un mando dibujado sobre un monitor sobra, y en el
## editor estorba para colocar lo demas.
@export var only_on_touch: bool = true

var _buttons: Dictionary = {}      ## StringName -> TextureRect
var _rects: Dictionary = {}        ## StringName -> Rect2 (la caja del dedo)
var _held: Dictionary = {}         ## indice de dedo -> StringName
var _root: Control = null
var _atlas: Texture2D = null
var _regions: Dictionary = {}      ## "left_idle0" -> Rect2, leido del XML


func _ready() -> void:
	if only_on_touch and not _is_touch_device():
		hide()
		set_process_input(false)
		return

	layer = 80  # por encima de los menus, por debajo de las transiciones
	_follow_parent()
	_atlas = load(ATLAS)
	_read_atlas()
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


func _read_atlas() -> void:
	var xml := XMLParser.new()
	if xml.open(ATLAS_XML) != OK:
		push_error("virtualpad: no se puede leer %s" % ATLAS_XML)
		return
	while xml.read() == OK:
		if xml.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if xml.get_node_name() != "SubTexture":
			continue
		_regions[xml.get_named_attribute_value("name")] = Rect2(
			float(xml.get_named_attribute_value("x")),
			float(xml.get_named_attribute_value("y")),
			float(xml.get_named_attribute_value("width")),
			float(xml.get_named_attribute_value("height")))


func _build() -> void:
	for id: StringName in _places():
		var button := TextureRect.new()
		button.name = String(id).to_upper()
		button.texture = _frame(id, "idle0")
		button.modulate = TINTS[id]
		button.modulate.a = opacity
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Sin esto un TextureRect se queda al tamaño de su textura y `size` no hace nada,
		# asi que el mando salia siempre a 132 px daba igual la pantalla.
		button.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		button.stretch_mode = TextureRect.STRETCH_SCALE
		_root.add_child(button)
		_buttons[id] = button


## Boton -> esquina, ya juntas la cruz y las acciones. El segundo valor dice desde que borde
## se mide la x: los de accion cuelgan del derecho.
func _places() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in DPADS.get(dpad, {}):
		out[id] = [DPADS[dpad][id], false]
	for id: StringName in ACTIONS.get(action, {}):
		out[id] = [ACTIONS[action][id], true]
	return out


func _frame(id: StringName, state: String) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = _atlas
	tex.region = _regions.get("%s_%s" % [id, state], Rect2()) as Rect2
	# Sin esto los botones de al lado se cuelan por el borde al escalar.
	tex.filter_clip = true
	return tex


## De 1280x720 a la pantalla que haya. La escala sale del lado que MENOS da de si, asi que
## en una pantalla mas ancha el mando no crece: se separan las dos esquinas y ya, que es lo
## que se quiere de un mando anclado a los bordes.
func _layout() -> void:
	if _root == null:
		return
	var size: Vector2 = _root.size
	if size == Vector2.ZERO:
		size = get_viewport().get_visible_rect().size
	var k: float = minf(size.x / REF_SCREEN.x, size.y / REF_SCREEN.y)
	var button: Vector2 = REF_BUTTON * k

	_rects.clear()
	var places: Dictionary = _places()
	for id: StringName in _buttons:
		var spec: Array = places[id]
		var corner: Vector2 = spec[0] as Vector2
		var from_right: bool = spec[1] as bool
		var at := Vector2(
			size.x - corner.x * k if from_right else corner.x * k,
			size.y - corner.y * k)
		var node := _buttons[id] as TextureRect
		node.position = at
		node.size = button
		# La caja del dedo es EXACTAMENTE lo que se dibuja. La primera version la crecia un
		# 30% "para el pulgar" y lo que conseguia era que las cajas de la cruz se pisaran
		# entre ellas: con los pasos de 105 sobre botones de 132 ya se solapan 27 px de por
		# si. A 1920x1080 el boton sale a 198x190, que es dedo de sobra.
		_rects[id] = Rect2(at, button)


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
		# El emulado desde el tacto se descarta: llega ademas del toque y con `device = -1`.
		# Sin esto, un dedo en un boton manda la tecla DOS veces. Es el mismo fallo que
		# tenian todos los menus del puerto; la explicacion larga esta en freeplay_screen.gd.
		if click.device == -1:
			return
		_press(-1, _hit(click.position) if click.pressed else &"")


## El boton mas cercano DE LOS QUE contienen el punto, no el primero que aparezca. Las cajas
## de la cruz se solapan 27 px por el paso de 105 sobre botones de 132, y con "el primero"
## el resultado dependia del orden del diccionario, que no es una razon.
func _hit(at: Vector2) -> StringName:
	var best: StringName = &""
	var best_d: float = INF
	for id: StringName in _rects:
		var rect: Rect2 = _rects[id] as Rect2
		if not rect.has_point(at):
			continue
		var d: float = at.distance_squared_to(rect.get_center())
		if d < best_d:
			best_d = d
			best = id
	return best


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
	button.texture = _frame(id, "press1" if down else "idle0")
	button.modulate.a = minf(opacity * 1.7, 1.0) if down else opacity


func _send(id: StringName, down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEYS[id]
	key.physical_keycode = KEYS[id]
	key.pressed = down
	Input.parse_input_event(key)
