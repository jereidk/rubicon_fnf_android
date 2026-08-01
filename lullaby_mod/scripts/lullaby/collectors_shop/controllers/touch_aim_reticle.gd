extends Control

## Touch has no cursor, so without this the player has no way to see where
## MouseController's screen-center raycast is actually aiming during
## FREE_LOOK (see mouse_controller.gd's _physics_process()), nor any
## equivalent to the CURSOR_POINTING_HAND feedback a desktop mouse gets
## when hovering something interactable. Hidden outside touch FREE_LOOK -
## once FOCUSED, MouseController aims from the raw touch position instead
## (the camera can't pan there to re-center a fixed crosshair on an
## off-center prop like the power button), so a fixed center reticle would
## be actively misleading; desktop mouse users already have a real cursor
## for this regardless of state.

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
		and mouse_controller.root != null
		and mouse_controller.root.state == CollectorShop.ShopStates.FREE_LOOK
	)

	if should_show != visible:
		visible = should_show

	if should_show:
		queue_redraw()

func _draw() -> void:
	var hovering: = mouse_controller.colliding and mouse_controller.can_click
	var color: Color = HOVER_COLOR if hovering else IDLE_COLOR
	var center: = size * 0.5

	draw_arc(center, RADIUS, 0.0, TAU, 24, color, RING_WIDTH, true)
	draw_circle(center, CENTER_DOT_RADIUS, color)
