@tool
extends Control
class_name RubiconVirtualDPad

## Two visual styles sharing one input pipeline: a continuous-feeling
## joystick (base ring + knob that follows the finger) for camera drag,
## and a structured 4-arrow D-pad for discrete menu selection. Whichever
## style is showing, direction is still resolved into one of 4 discrete
## zones (up/right/down/left) and presses/holds/releases the matching
## ui_up/ui_down/ui_left/ui_right action directly, exactly like a held
## keyboard key - so any menu that already navigates via focus_neighbor +
## those actions works with this with zero changes, and MouseController's
## Input.get_axis(ui_right, ui_left) camera pan works with the same zones
## regardless of which style is on screen. Host scenes switch
## visual_style at runtime (see RubiconMenuTouchControls.style_source) -
## joystick while free-look camera dragging is the natural motion,
## arrows once the player is picking between fixed menu options instead.
##
## Hardened against jitter spam: a finger resting near a zone boundary
## (or the dead zone edge) shouldn't rapid-fire action_press/release as
## the angle/radius wobbles by a degree or two between frames. Switching
## zones needs the angle to clear the boundary by ZONE_HYSTERESIS_DEG in
## favor of the *new* zone, and entering/leaving the dead zone uses two
## different radii (exit needs to travel further out than re-entry), both
## classic hysteresis so the active zone only changes on a deliberate
## movement, never a wobble. A minimum hold time before a zone can switch
## again is an extra backstop against spamming the underlying action.

enum VisualStyle { JOYSTICK, ARROWS }

const ACTIONS := {
	0: &"ui_up",
	1: &"ui_right",
	2: &"ui_down",
	3: &"ui_left",
}

const ZONE_HYSTERESIS_DEG: float = 10.0
const DEAD_ZONE_ENTER_PERCENT: float = 0.15
const DEAD_ZONE_EXIT_PERCENT: float = 0.22
const MIN_ZONE_HOLD_SEC: float = 0.05

## The joystick reads as a smooth, continuous drag - it never flashes or
## recolors on press (that read as jittery for something meant to feel
## like an analog stick); it always stays the same white/gray. Only the
## ARROWS style flashes and highlights the pressed arm, since each press
## there is a discrete, separate action worth calling out.
@export var visual_style: VisualStyle = VisualStyle.JOYSTICK:
	set(value):
		if value == visual_style:
			return
		visual_style = value
		queue_redraw()
@export var radius: float = 100.0:
	set(value):
		radius = value
		queue_redraw()
@export var anchor_position: Vector2 = Vector2(140, -140):
	set(value):
		anchor_position = value
		queue_redraw()
@export var base_color: Color = Color(0.09, 0.09, 0.12, 0.35):
	set(value):
		base_color = value
		queue_redraw()
@export var pressed_color: Color = Color(0.95, 0.85, 0.25, 0.65):
	set(value):
		pressed_color = value
		queue_redraw()
@export var divider_color: Color = Color(1, 1, 1, 0.6):
	set(value):
		divider_color = value
		queue_redraw()
@export var knob_color: Color = Color(0.85, 0.85, 0.9, 0.5):
	set(value):
		knob_color = value
		queue_redraw()

var _active_zone: int = -1
var _touch_index: int = -1
var _in_dead_zone: bool = true
var _zone_held_since: float = 0.0
## Visual-only: how far the knob is drawn from center. Purely cosmetic -
## it tracks the raw finger offset (clamped to the base ring) so the
## joystick reads as responsive, but the 4-zone hysteresis above is what
## actually decides which action fires.
var _knob_offset: Vector2 = Vector2.ZERO
## Visual-only: quick bright pulse on the knob whenever a new direction
## is pressed, decaying back to 0 - the same "the touch registered"
## feedback the Accept/Cancel/F buttons get from their own flash.
var _flash_amount: float = 0.0

func _get_origin() -> Vector2:
	var p: Vector2 = anchor_position
	if p.x < 0.0:
		p.x += size.x
	if p.y < 0.0:
		p.y += size.y
	return p

func _draw() -> void:
	match visual_style:
		VisualStyle.ARROWS:
			_draw_arrows()
		_:
			_draw_joystick()

## Continuous-drag look: a base ring with a small knob that follows the
## finger. Deliberately never changes color or flashes on press - it
## always reads as the same plain white/gray stick, since a per-zone
## highlight would fight the "one continuous drag" feel this style is
## for.
func _draw_joystick() -> void:
	var origin: Vector2 = _get_origin()

	draw_circle(origin, radius, base_color)
	draw_arc(origin, radius, 0.0, TAU, 48, divider_color, 2.5, true)

	var knob_radius: float = radius * 0.28
	var knob_pos: Vector2 = origin + _knob_offset
	draw_circle(knob_pos, knob_radius, knob_color)
	draw_arc(knob_pos, knob_radius, 0.0, TAU, 32, divider_color, 2.0, true)

## Discrete-selection look: a structured cross with 4 rectangular arms,
## a center hub, and outward chevron arrows - the pressed arm lights up
## and flashes, since each press here is one separate, discrete choice
## worth calling out (unlike the joystick's single continuous drag).
func _draw_arrows() -> void:
	var origin: Vector2 = _get_origin()
	var w: float = radius * 0.38
	var l: float = radius
	var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

	var hub := PackedVector2Array([
		origin + Vector2(-w, -w), origin + Vector2(w, -w),
		origin + Vector2(w, w), origin + Vector2(-w, w),
	])
	draw_colored_polygon(hub, base_color)

	for zone in range(4):
		var dir: Vector2 = dirs[zone]
		var perp: Vector2 = dir.rotated(PI / 2.0) * w
		var inner: Vector2 = dir * w
		var outer: Vector2 = dir * l
		var color: Color = base_color
		if zone == _active_zone:
			color = pressed_color.lerp(Color(1.0, 1.0, 1.0, pressed_color.a), _flash_amount * 0.7)
		var world_arm := PackedVector2Array([
			origin + inner + perp, origin + outer + perp,
			origin + outer - perp, origin + inner - perp,
		])
		draw_colored_polygon(world_arm, color)

		var mid: Vector2 = origin + dir * ((w + l) * 0.5)
		var chevron_s: float = w * 1.1
		var chev_perp: Vector2 = dir.rotated(PI / 2.0)
		var apex: Vector2 = mid + dir * chevron_s * 0.6
		var base1: Vector2 = mid - dir * chevron_s * 0.4 + chev_perp * chevron_s * 0.55
		var base2: Vector2 = mid - dir * chevron_s * 0.4 - chev_perp * chevron_s * 0.55
		draw_colored_polygon(PackedVector2Array([apex, base1, base2]), divider_color)

	var outline := PackedVector2Array([
		origin + Vector2(-w, -l), origin + Vector2(w, -l), origin + Vector2(w, -w),
		origin + Vector2(l, -w), origin + Vector2(l, w), origin + Vector2(w, w),
		origin + Vector2(w, l), origin + Vector2(-w, l), origin + Vector2(-w, w),
		origin + Vector2(-l, w), origin + Vector2(-l, -w), origin + Vector2(-w, -w),
	])
	outline.append(outline[0])
	draw_polyline(outline, divider_color, 2.5, true)

	draw_line(origin + Vector2(-w, -w), origin + Vector2(w, -w), divider_color, 1.5, true)
	draw_line(origin + Vector2(w, -w), origin + Vector2(w, w), divider_color, 1.5, true)
	draw_line(origin + Vector2(w, w), origin + Vector2(-w, w), divider_color, 1.5, true)
	draw_line(origin + Vector2(-w, w), origin + Vector2(-w, -w), divider_color, 1.5, true)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release()

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_try_start(event.index, event.position)
		elif event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_zone(event.position)

func _try_start(index: int, pos: Vector2) -> void:
	if _touch_index != -1:
		return

	var origin: Vector2 = _get_origin()
	if pos.distance_to(origin) > radius * 1.4:
		return

	_touch_index = index
	_in_dead_zone = true
	_zone_held_since = 0.0
	_update_zone(pos)

## Hysteresis on the radius (separate enter/exit thresholds) and on the
## angle (a zone switch has to clear the boundary by ZONE_HYSTERESIS_DEG,
## and can't happen again within MIN_ZONE_HOLD_SEC of the last one) so a
## finger resting near either kind of boundary can't spam action_press/
## release every frame.
func _update_zone(pos: Vector2) -> void:
	var origin: Vector2 = _get_origin()
	var offset: Vector2 = pos - origin
	var dist: float = offset.length()

	_knob_offset = offset.limit_length(radius * 0.7)
	queue_redraw()

	var exit_radius: float = radius * DEAD_ZONE_EXIT_PERCENT
	var enter_radius: float = radius * DEAD_ZONE_ENTER_PERCENT
	if _in_dead_zone:
		if dist < exit_radius:
			_set_zone(-1)
			return
	else:
		if dist < enter_radius:
			_set_zone(-1)
			return
	_in_dead_zone = false

	# atan2 is 0=right, 90=down (Godot's Y-down screen space); rotate so
	# zone 0 (up) starts at -45deg and each zone spans 90deg going clockwise.
	var angle_deg: float = rad_to_deg(offset.angle()) + 90.0 + 45.0
	if angle_deg < 0.0:
		angle_deg += 360.0
	var raw_zone: int = int(angle_deg / 90.0) % 4

	if raw_zone == _active_zone or _active_zone == -1:
		_set_zone(raw_zone)
		return

	# Only switch away from the current zone once the angle has moved
	# solidly into the new zone - past its boundary by the hysteresis
	# margin, not just barely across it. distance_into_zone is the signed
	# offset from the new zone's center (±45deg at its edges); requiring
	# it to be within ±(45 - margin) means the boundary itself has a dead
	# band no single zone claims, so a wobbling finger can't flicker back
	# and forth across it.
	var zone_center: float = raw_zone * 90.0
	var distance_into_zone: float = angle_deg - zone_center
	if distance_into_zone > 180.0:
		distance_into_zone -= 360.0

	if absf(distance_into_zone) > 45.0 - ZONE_HYSTERESIS_DEG:
		return

	_set_zone(raw_zone)

## Dispatches via Input.parse_input_event (real InputEventAction), not
## Input.action_press/action_release. action_press only updates the Input
## singleton's polled action-strength state - per Godot's own docs it
## "will not cause any Node._input calls." Godot's own Control focus
## navigation (grab_focus/focus_neighbor_* moving on ui_up/down/left/
## right, ui_accept activating a button) is driven entirely by real
## InputEvents flowing through _input/_gui_input, so action_press alone
## silently never moves focus anywhere - confirmed empirically. Every
## menu here (Console, Kollectadex, Settings, Categories...) is built on
## that same default focus system, so this one call is what makes the
## D-pad actually navigate any of it, not just poll-based consumers like
## MouseController's Input.get_axis(ui_right, ui_left).
func _dispatch_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _set_zone(zone: int) -> void:
	_in_dead_zone = zone == -1

	if zone == _active_zone:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _zone_held_since < MIN_ZONE_HOLD_SEC:
		return
	_zone_held_since = now

	if _active_zone != -1:
		_dispatch_action(ACTIONS[_active_zone], false)
	if zone != -1:
		_dispatch_action(ACTIONS[zone], true)
		if visual_style == VisualStyle.ARROWS:
			_flash()

	_active_zone = zone
	queue_redraw()

func _flash() -> void:
	_flash_amount = 1.0
	var tween := create_tween()
	tween.tween_method(_set_flash_amount, 1.0, 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_flash_amount(v: float) -> void:
	_flash_amount = v
	queue_redraw()

## Unconditional release: touch ended, focus lost, or the overlay itself
## went inactive. This bypasses _set_zone's MIN_ZONE_HOLD_SEC debounce on
## purpose - that debounce exists to stop a wobbling finger from spamming
## action_press/release during normal zone-to-zone transitions, but a real
## release must never be swallowed by it. If it were, the held action
## (e.g. ui_left) would stay pressed forever with no further touch event
## ever arriving to clear it - which read as the 3D camera spinning
## indefinitely on its own with no finger anywhere near the pad.
func _release() -> void:
	_touch_index = -1
	_in_dead_zone = true
	_knob_offset = Vector2.ZERO
	if _active_zone != -1:
		_dispatch_action(ACTIONS[_active_zone], false)
	_active_zone = -1
	_zone_held_since = 0.0
	queue_redraw()
