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
		queue_redraw()

func _draw() -> void:
	var hovering: = mouse_controller.colliding and mouse_controller.can_click
	var color: Color = HOVER_COLOR if hovering else IDLE_COLOR
	var center: = size * 0.5

	draw_arc(center, RADIUS, 0.0, TAU, 24, color, RING_WIDTH, true)
	draw_circle(center, CENTER_DOT_RADIUS, color)
