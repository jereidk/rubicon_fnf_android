extends Button
class_name LullabyAimLockButton

## El candado del mando tactil: para el joystick y suelta el punto de mira.
##
## POR QUE HACE FALTA. En tactil, durante FREE_LOOK se apunta girando la camara
## con el joystick y el punto de mira es el centro de la pantalla. Pero el
## joystick solo gira en Y, asi que ese centro barre una FRANJA HORIZONTAL a la
## altura de los ojos: todo lo que este por encima o por debajo es visible,
## interactivo, e imposible de senalar. Los peluches de encima del pendulo y las
## fotos, el sombrero del Collector, la jarra.
##
## Con el candado puesto el joystick deja de girar la camara y el punto de mira
## pasa a ser donde toques - que es como ya funciona en FOCUSED. La camara no se
## mueve, asi que no se pierde el encuadre, y el estado sigue siendo FREE_LOOK
## para que la mascara del raycast no cambie (ver MouseController.aim_locked).
##
## EL ICONO SE DIBUJA, no se escribe. La fuente del juego es fnt_pokemon_bw.otf y
## un glifo de candado que no exista saldria como una caja vacia, que es peor que
## no poner icono. Dos primitivas - un arco para el arco del candado y un
## rectangulo para el cuerpo - se ven igual en cualquier resolucion y no dependen
## de nada.

@export var mouse_controller: MouseController

## El nodo cuyo `state` decide si esto pinta algo, y el valor de FREE_LOOK.
##
## Por propiedad y no por clase, igual que `RubiconActionButton.visible_source`:
## el boton no tiene por que saber nada de CollectorShop mas alla de que expone
## un `state`.
@export var state_source: Node
@export var state_property: StringName = &"state"
@export var free_look_state: int = 1

const LOCKED_COLOR := Color(1, 0.86, 0.45, 0.95)
const UNLOCKED_COLOR := Color(1, 1, 1, 0.65)

func _ready() -> void:
	# Misma razon que en RubiconActionButton: un Button con foco se come los
	# ui_left/ui_right del joystick virtual antes de que lleguen a la camara.
	focus_mode = Control.FOCUS_NONE
	pressed.connect(_toggle)

func _toggle() -> void:
	if mouse_controller == null:
		return

	mouse_controller.aim_locked = not mouse_controller.aim_locked
	queue_redraw()

func _process(_delta: float) -> void:
	visible = _should_show()

## Solo con mando tactil y solo en FREE_LOOK.
##
## En escritorio no pinta nada: hay un cursor de verdad que ya llega a cualquier
## punto de la pantalla, que es justo lo que le falta al tactil. Y fuera de
## FREE_LOOK el apuntado ya es por toque, asi que el candado no anadiria nada y
## solo taparia pantalla.
func _should_show() -> bool:
	if mouse_controller == null or not mouse_controller.is_touch_controls_active():
		return false

	if state_source == null or state_property.is_empty():
		return false

	return int(state_source.get(state_property)) == free_look_state

func _draw() -> void:
	var locked: bool = mouse_controller != null and mouse_controller.aim_locked
	var color: Color = LOCKED_COLOR if locked else UNLOCKED_COLOR

	var box: Vector2 = size
	var unit: float = minf(box.x, box.y)
	var body_w: float = unit * 0.46
	var body_h: float = unit * 0.34
	var body := Rect2(
		Vector2((box.x - body_w) * 0.5, box.y * 0.5 - body_h * 0.15),
		Vector2(body_w, body_h))

	draw_rect(body, color, true)

	# El arco. Cerrado y centrado cuando esta puesto; abierto y desplazado a la
	# derecha cuando no, que es como se dibuja un candado abierto y lo hace
	# legible de un vistazo sin leer ningun texto.
	var radius: float = body_w * 0.32
	var center := Vector2(
		body.position.x + body_w * (0.5 if locked else 0.72),
		body.position.y - radius * 0.1)
	var from: float = PI
	var to: float = TAU if locked else TAU * 0.85

	draw_arc(center, radius, from, to, 16, color, maxf(unit * 0.06, 2.0), true)
