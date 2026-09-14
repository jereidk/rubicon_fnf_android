extends Control

## Touch has no cursor, so without this the player has no way to see where
## MouseController's raycast is actually aiming, nor any equivalent to the
## CURSOR_POINTING_HAND feedback a desktop mouse gets when hovering
## something interactable. Desktop mouse users already have a real cursor
## for this, so it is touch-only.
##
## It follows MouseController.get_aim_position() rather than sitting at the
## screen centre: centred is right for FREE_LOOK, where the joystick aims by
## turning the camera, but once FOCUSED the aim is the player's last tap on
## the world and the crosshair has to be on it. It used to hide itself
## entirely in that state, back when the aim was read live from the emulated
## mouse and there was no stable point to draw - which left the one state
## where you have to aim at a small prop as the one state with no feedback
## at all.
##
## Hidden while BUSY, via should_cast_ray: no raycast is running then, so
## there is nothing to aim.

@export var mouse_controller: MouseController

const IDLE_COLOR := Color(1, 1, 1, 0.55)
const HOVER_COLOR := Color(1, 1, 1, 0.95)
const RADIUS := 10.0
const CENTER_DOT_RADIUS := 2.0
const RING_WIDTH := 2.0

## El estado de hover la ultima vez que se dibujo. -1 = sin dibujar todavia.
##
## Un entero y no un bool por el mismo motivo que la cache de
## `is_touch_controls_active()`: hace falta un tercer estado para "aun no".
var _drawn_hover: int = -1

func _ready() -> void:
	# `_draw()` mide desde `size`, asi que un cambio de tamaño si invalida lo
	# dibujado - y es el unico ademas del hover que lo hace.
	resized.connect(queue_redraw)

func _process(_delta: float) -> void:
	var should_show: = (
		mouse_controller != null
		and mouse_controller.should_cast_ray
		and mouse_controller.is_touch_controls_active()
	)

	if should_show != visible:
		visible = should_show

	if should_show:
		global_position = mouse_controller.get_aim_position() - size * 0.5

		# Redibujar SOLO cuando cambia lo dibujado, que aqui es el color.
		#
		# `queue_redraw()` incondicional rehacia el arco de 24 segmentos y el
		# circulo en cada fotograma. Moverse no lo pide: mover un CanvasItem
		# cambia su transformada, no su lista de comandos, y la lista se conserva
		# - por eso arrastrar un nodo no vuelve a llamar a `_draw()`. Y lo que
		# `_draw()` lee, ademas de `size`, es solo el color, que sale del par
		# `colliding`/`can_click`.
		#
		# Encima es el caso peor por como apunta el tactil: durante FREE_LOOK
		# `get_aim_position()` devuelve el centro de la pantalla, asi que la mira
		# esta QUIETA la mayor parte del tiempo y aun asi se redibujaba entera.
		var hovering: int = 1 if (mouse_controller.colliding
			and mouse_controller.can_click) else 0
		if hovering != _drawn_hover:
			_drawn_hover = hovering
			queue_redraw()

func _draw() -> void:
	var hovering: = mouse_controller.colliding and mouse_controller.can_click
	var color: Color = HOVER_COLOR if hovering else IDLE_COLOR
	var center: = size * 0.5

	draw_arc(center, RADIUS, 0.0, TAU, 24, color, RING_WIDTH, true)
	draw_circle(center, CENTER_DOT_RADIUS, color)
