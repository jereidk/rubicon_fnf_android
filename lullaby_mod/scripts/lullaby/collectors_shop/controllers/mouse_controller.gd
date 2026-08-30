class_name MouseController
extends Node

@export var can_click: bool = true
@export var ray_length: float = 35.0

@export_group("Reference")
@export var root: CollectorShop
@export var camera: Camera3D
@export var ray_cast: RayCast3D
@export var hand_animation_tree: AnimationTree

## The on-screen touch overlay, so a tap on one of its own controls is not
## mistaken for a tap on the world behind it - see _tap_on_overlay().
@export var touch_controls: Control


@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
var override_cursor_shape: Input.CursorShape = -1

const ROTATION_PAN_SPEED_DEGREES: = 120.0
const MIN_ROTATION_SPEED: = 4.0
const MAX_ROTATION_SPEED: = 12.0
const MAX_LEFT_ROTATION_DEGREES: = -90.0
const MAX_RIGHT_ROTATION_DEGREES: = 80.0
const EDGE_PERCENT: = 0.4

@export var should_cast_ray: bool:
	set(value):
		should_cast_ray = value
		if ray_cast:
			ray_cast.enabled = value

var colliding: = false

## Whether pressing the overlay's confirm button right now would do anything.
##
## The button is one control across every state, but not one job: the shop
## swaps its action between "RightClick" and "ui_accept" as the state changes
## (env_collector_shop.gd), and only the first of those goes through this
## raycast. So there are two answers and the raycast decides only one of them.
##
## Not casting means the confirm is a plain menu ui_accept - the console, the
## briefcase, the notepad, the Kollectadex - and every one of those owns its
## own confirm and always has something to do with it. Always available, and
## that is also the right answer if camera or ray_cast is somehow unset, which
## is a wiring mistake and not a reason to take the button away.
##
## Casting means the confirm is an aim-and-click at the 3D world, so it does
## something exactly when there is something under the aim. That is already on
## screen twice - the cursor turns into a pointing hand and the Collector's
## hand points - and the touch reticle draws off the same two fields; this
## just says it a third time, with the one control the player actually presses.
##
## Deliberately the same test _input() applies before triggering, down to not
## consulting can_interact: _input() does not either, so an area with it false
## still fires today. Saying "unavailable" about something that would in fact
## fire would be the button lying about the game rather than describing it.
var confirm_is_available: bool:
	get:
		if not _can_ray_cast():
			return true
		return colliding and can_click

## Where a touch confirm aims once the camera is locked (FOCUSED).
##
## The aim and the confirm are two separate taps on touch: the aim used to
## be read live from the emulated mouse position, and the confirm can only
## come from the OK button (see _is_confirm_event). Android's "emulate
## mouse from touch" moves that position on EVERY tap - including the one
## that presses OK - so by the time the confirm arrived the ray had already
## swung across to wherever the OK button sits, and whatever the player had
## actually tapped was never what got triggered.
##
## That made every FOCUSED-state raycast target in the shop unreachable on
## touch: the Collector, his hat, the Kollectadex, the board, the plush,
## the jar, the string, the photos. The one that always worked, the TV's
## Power button, works precisely because it bypasses the raycast
## (RubiconActionButton.direct_target).
##
## So latch it: a tap on the 3D world sets the aim and it stays there until
## the next one. Vector2.INF means "nothing tapped yet", which reads as the
## screen centre.
var touch_aim: Vector2 = Vector2.INF

var _hand_state: StringName = &""
var _last_shop_state: CollectorShop.ShopStates
var _hand_state_machine: AnimationNodeStateMachinePlayback

## Lo ultimo que se le escribio al raycast y al cursor, para no repetirlo.
##
## Las tres escrituras de `_physics_process` cuestan lo mismo cambie el valor o
## no: `target_position` y `collision_mask` marcan el RayCast3D sucio y lo
## re-registran en PhysicsServer3D, e `Input.set_default_cursor_shape()` es una
## llamada al SO. Se hacian las tres incondicionalmente cada paso de fisica.
##
## El log del dispositivo mide la tienda en `phys=5.16ms` con un solo nodo de
## fisica (`physn=1`), 10 objetos y 10 pares de colision. Diez pares de cajas y
## capsulas no cuestan cinco milisegundos, y lo unico que corre ahi dentro
## ademas del paso del servidor es este callback.
##
## Solo el raycast: el cursor NO se cachea, y `_set_cursor()` explica por que.
##
## Que sea seguro cachear estos dos se comprobo enumerando: nadie mas en el
## proyecto escribe `target_position` ni `collision_mask` de este RayCast3D.
var _last_ray_target: Vector3 = Vector3.INF
var _last_ray_mask: int = -1


func _ready() -> void :
	if hand_animation_tree:
		hand_animation_tree.active = true
		_hand_state_machine = hand_animation_tree.get("parameters/playback")

	if root != null:
		_last_shop_state = root.state

		if root.state == root.ShopStates.FREE_LOOK:
			_travel_hand(&"Activate")
		else:
			_travel_hand(&"Deactivate")
			if root.dialogue != null:
				root.dialogue.play_scale_out()

func _can_ray_cast() -> bool:
	return should_cast_ray and camera and ray_cast


func _is_free_look() -> bool:
	return root != null and root.state == root.ShopStates.FREE_LOOK


## Screen point the raycast aims at, in viewport coordinates.
##
## On touch during FREE_LOOK it is the screen centre - i.e. wherever the
## joystick has left the camera looking - because the raw touch position
## can't drive FREE_LOOK's big zone-entry areas the way a real mouse cursor
## does (see is_touch_controls_active()).
##
## That doesn't hold once FOCUSED: the camera is locked wherever the zoom-in
## animation left it (_process() below only pans during FREE_LOOK), so a
## fixed centre point can only ever reach whatever that animation happened
## to centre - the console screen, say, but not a separate prop like the
## power button sitting elsewhere on the same console. There is no joystick
## left to move a crosshair with either, so aiming is by tapping the thing,
## same as desktop's mouse - but from the latched [member touch_aim] rather
## than live, for the reason written on it.
##
## Public because touch_aim_reticle.gd draws the crosshair at this point.
func get_aim_position() -> Vector2:
	if not is_touch_controls_active():
		return get_viewport().get_mouse_position()

	if _is_free_look() or touch_aim == Vector2.INF:
		return get_viewport().get_visible_rect().size * 0.5

	return touch_aim


## _unhandled_input, not _input: a tap the GUI already took - OK, Back, the
## F button, the Power button - never reaches here, so pressing one of them
## leaves the aim pointing at whatever the player tapped before it, which is
## the whole point.
##
## RubiconVirtualDPad is the exception: it reads touches in _input() and
## does not mark them handled, so its taps do arrive here. _tap_on_overlay()
## covers it (and re-covers the buttons, harmlessly).
func _unhandled_input(event: InputEvent) -> void :
	if not is_touch_controls_active():
		return

	var touch: = event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return

	if _tap_on_overlay(touch.position):
		return

	touch_aim = touch.position


func _tap_on_overlay(point: Vector2) -> bool:
	if touch_controls == null or not touch_controls.visible:
		return false

	for child in touch_controls.get_children():
		var control: = child as Control
		if control == null or not control.visible:
			continue

		if control.get_global_rect().has_point(point):
			return true

	return false


func _physics_process(_delta: float) -> void :
	if not _can_ray_cast():
		colliding = false
		_set_cursor(override_cursor_shape if override_cursor_shape >= 0
			else Input.CURSOR_ARROW)
		return

	# Solo si de verdad cambia. Escribirlo igualmente re-registra el raycast en
	# PhysicsServer3D e invalida su consulta cacheada, y la mira solo se mueve
	# cuando el jugador mueve la camara - no treinta veces por segundo mientras
	# esta quieto mirando un estante.
	var target: Vector3 = camera.project_ray_normal(get_aim_position()) * ray_length
	if not target.is_equal_approx(_last_ray_target):
		_last_ray_target = target
		ray_cast.target_position = target

	if root and root.state != _last_ray_mask:
		_last_ray_mask = root.state
		ray_cast.collision_mask = root.state

	colliding = ray_cast.is_colliding()

	var collider: = ray_cast.get_collider()
	var clickable: = colliding and can_click
	if clickable and "can_interact" in collider:
		clickable = clickable and collider.can_interact

	_set_cursor(override_cursor_shape if override_cursor_shape >= 0
		else (Input.CURSOR_POINTING_HAND if clickable else Input.CURSOR_ARROW))


## El cursor. SIN cachear, y eso es deliberado.
##
## La primera version se saltaba la llamada cuando el valor no cambiaba, igual
## que con el raycast. No vale aqui: `cartridge_bag_handler.gd` tambien llama a
## `Input.set_default_cursor_shape()`, y una cache que solo conoce sus propias
## escrituras se desincroniza en cuanto el otro escribe. El fallo seria que este
## nodo quisiera volver a CURSOR_ARROW, la cache dijera "ya esta", y el cursor se
## quedara en la mano que puso el bolso.
##
## Cachear esto de verdad exige que los dos pasen por el mismo sitio, y no vale
## la pena: el ahorro es una llamada al SO por paso de fisica, contra las dos
## del raycast que si tocan PhysicsServer3D.
func _set_cursor(shape: int) -> void:
	Input.set_default_cursor_shape(shape)


func _process(delta: float) -> void :
	_update_hand_from_shop_state()

	if not _is_free_look():
		return

	if not get_window().has_focus():
		_travel_hand(&"Idle")
		return

	var direction: = _get_look_direction()

	_update_hand_animation(direction)

	if direction != 0.0:
		_update_camera_rotation(direction, delta)


func _update_hand_from_shop_state() -> void :
	if root == null:
		return

	if root.state == _last_shop_state:
		return

	_last_shop_state = root.state

	# A state change means a camera move, so the last tap now points at
	# something else entirely. Back to the centre until the player picks a
	# new target.
	touch_aim = Vector2.INF

	match root.state:
		root.ShopStates.FREE_LOOK:
			_travel_hand(&"Activate")

		root.ShopStates.BUSY, root.ShopStates.FOCUSED:
			_travel_hand(&"Deactivate")


## Rubicon addition: keyboard_direction also reflects the virtual
## joystick's left/right zones (it presses/releases ui_right/ui_left via
## real InputEvents - see RubiconVirtualDPad), so that branch already
## covers touch. The mouse-edge fallback below reads the raw cursor
## position, and Android's touch-emulates-mouse means ANY tap or drag
## updates that position too - including taps on the joystick or OK/
## Back/F buttons themselves, which sit within EDGE_PERCENT (40%) of
## the screen edges. Left unguarded, tapping a button near either edge
## would spuriously pan the camera on top of whatever the joystick was
## already doing. Skip the fallback entirely once touch controls are
## enabled, so only the joystick's zones ever drive camera pan on touch.
func _get_look_direction() -> float:
	var keyboard_direction: = Input.get_axis("ui_right", "ui_left")

	if keyboard_direction != 0.0:
		return keyboard_direction

	if is_touch_controls_active():
		return 0.0

	return _get_mouse_edge_direction()


## Android's "emulate mouse from touch" turns every screen tap into both a
## mouse-position update and a real InputEventMouseButton - there's no
## actual cursor, so neither can be trusted the way they would be with a
## real mouse. Shared by _get_look_direction() (mouse-edge camera pan
## fallback), _physics_process()/_is_confirm_event() (raycast aim +
## confirm-click), and touch_aim_reticle.gd (whether to show the crosshair
## at all), all of which need to ignore that emulated input on touch and
## defer to the joystick/OK button instead. Public (no leading underscore)
## because touch_aim_reticle.gd, a separate sibling node, calls it too.
func is_touch_controls_active() -> bool:
	return ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true) \
		and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"))


func _get_mouse_edge_direction() -> float:
	var viewport_width: = get_viewport().get_visible_rect().size.x
	var mouse_x: = get_viewport().get_mouse_position().x

	if mouse_x < 0.0 or mouse_x > viewport_width:
		return 0.0

	var edge_size: = viewport_width * EDGE_PERCENT

	if mouse_x < edge_size:
		return 1.0 - mouse_x / edge_size

	if mouse_x > viewport_width - edge_size:
		return - ((mouse_x - (viewport_width - edge_size)) / edge_size)

	return 0.0


func _update_camera_rotation(direction: float, delta: float) -> void :
	var strength = abs(direction)

	camera.rotation_interpolate_speed = lerp(
		MIN_ROTATION_SPEED, 
		MAX_ROTATION_SPEED, 
		strength
	)

	var rotation_speed = lerp(
		ROTATION_PAN_SPEED_DEGREES * 0.25, 
		ROTATION_PAN_SPEED_DEGREES, 
		strength
	)

	var rotation_target: Vector3 = camera.rotation_interpolate_target
	rotation_target.y += deg_to_rad(direction * rotation_speed) * delta






	camera.rotation_interpolate_target = rotation_target


func _update_hand_animation(direction: float) -> void :
	if _hand_state_machine == null:
		return

	var collider: = ray_cast.get_collider()

	if collider:
		if colliding and can_click and "can_interact" in collider:
			if collider.can_interact:
				_travel_hand(&"Point")
				return

	if direction > 0.0:
		if _hand_state != &"LeanLeft" and _hand_state != &"HoldLeft":
			_travel_hand(&"LeanLeft")
		return

	if direction < 0.0:
		if _hand_state != &"LeanRight" and _hand_state != &"HoldRight":
			_travel_hand(&"LeanRight")
		return

	_travel_hand(&"Idle")


func _travel_hand(state_name: StringName) -> void :
	if _hand_state_machine == null:
		return

	if _hand_state == state_name:
		return

	_hand_state = state_name
	_hand_state_machine.travel(String(state_name))


func _input(event: InputEvent) -> void :
	if not _is_confirm_event(event):
		return

	if not _can_ray_cast() or not colliding or not can_click:
		return

	var collider: = ray_cast.get_collider()

	if collider is not TriggerArea3D:
		print(collider)
		printerr("The selected Area3D is not interactable.")
		return

	collider.area_triggered.emit()
	collider.trigger()


## "RightClick" is bound to button_index=1 (left click, not right - a
## naming leftover from the original desktop-only mod). On Android,
## "emulate mouse from touch" fires that same left-click on every single
## screen tap, so without the touch-controls check below, just touching
## anywhere on the 3D view would instantly confirm/enter whatever's under
## the finger - bypassing the joystick-aims / OK-confirms flow entirely.
## On touch, only a real confirm - the OK button's synthetic
## InputEventAction (see RubiconActionButton._dispatch()), or a physical
## gamepad button - should count; the emulated InputEventMouseButton must
## not.
func _is_confirm_event(event: InputEvent) -> bool:
	if is_touch_controls_active():
		return (
			(event is InputEventAction or event is InputEventJoypadButton)
			and event.is_action_pressed("RightClick")
		)

	return (
		(event is InputEventMouseButton or event is InputEventJoypadButton)
		and event.is_action_pressed("RightClick")
	)


## Public alias of _is_confirm_event() - same reasoning as
## is_touch_controls_active() above: props with their own bespoke
## Area3D hover/confirm handling (e.g. prp_sign.gd's shop/talk chooser,
## which bypasses this class' raycast entirely) still need the same
## real-click-vs-synthetic-touch-confirm distinction, so they share this
## instead of re-deriving it.
func is_confirm_event(event: InputEvent) -> bool:
	return _is_confirm_event(event)
