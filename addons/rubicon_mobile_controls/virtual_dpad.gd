@tool
extends Control
class_name RubiconVirtualDPad

## Cloud-gaming/emulator style D-pad: a structured cross with four
## rectangular directional arms (RetroArch/PSP overlay look), each with an
## outward-pointing chevron. Pressing/holding/releasing an arm presses/
## holds/releases the matching ui_up/ui_down/ui_left/ui_right action
## directly, exactly like a held keyboard key - so any menu that already
## navigates via focus_neighbor + those actions works with this with zero
## changes. Sibling to RubiconVirtualJoystick (used for 3D camera look);
## this one is for UI focus navigation instead of analog look/movement.
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

@export var radius: float = 100.0:
	set(value):
		radius = value
		queue_redraw()
@export var anchor_position: Vector2 = Vector2(140, -140):
	set(value):
		anchor_position = value
		queue_redraw()
@export var base_color: Color = Color(0.09, 0.09, 0.12, 0.55):
	set(value):
		base_color = value
		queue_redraw()
@export var pressed_color: Color = Color(0.95, 0.85, 0.25, 0.75):
	set(value):
		pressed_color = value
		queue_redraw()
@export var divider_color: Color = Color(1, 1, 1, 0.85):
	set(value):
		divider_color = value
		queue_redraw()

var _active_zone: int = -1
var _touch_index: int = -1
var _in_dead_zone: bool = true
var _zone_held_since: float = 0.0

func _get_origin() -> Vector2:
	var p: Vector2 = anchor_position
	if p.x < 0.0:
		p.x += size.x
	if p.y < 0.0:
		p.y += size.y
	return p

## Local-space (relative to origin) rectangle for one arm of the plus/cross,
## as a 4-point polygon: from the hub edge (w) out to the tip (radius),
## width 2*w. dir is one of the 4 cardinal unit vectors (up/right/down/left).
func _arm_rect(dir: Vector2, w: float) -> PackedVector2Array:
	var perp: Vector2 = dir.rotated(PI / 2.0) * w
	var inner: Vector2 = dir * w
	var outer: Vector2 = dir * radius
	return PackedVector2Array([
		inner + perp, outer + perp, outer - perp, inner - perp,
	])

## A small outward-pointing chevron/triangle centered at `center`, in the
## direction `dir`, used as the arrow glyph inside each arm.
func _chevron(center: Vector2, dir: Vector2, s: float) -> PackedVector2Array:
	var perp: Vector2 = dir.rotated(PI / 2.0)
	var apex: Vector2 = center + dir * s * 0.6
	var base1: Vector2 = center - dir * s * 0.4 + perp * s * 0.55
	var base2: Vector2 = center - dir * s * 0.4 - perp * s * 0.55
	return PackedVector2Array([apex, base1, base2])

func _draw() -> void:
	var origin: Vector2 = _get_origin()
	var w: float = radius * 0.38
	var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

	# Hub (center square) backing the whole cross.
	var hub := PackedVector2Array([
		origin + Vector2(-w, -w), origin + Vector2(w, -w),
		origin + Vector2(w, w), origin + Vector2(-w, w),
	])
	draw_colored_polygon(hub, base_color)

	# Four arms, each its own button so the pressed zone lights up alone.
	for zone in range(4):
		var dir: Vector2 = dirs[zone]
		var color: Color = pressed_color if zone == _active_zone else base_color
		var arm: PackedVector2Array = _arm_rect(dir, w)
		var world_arm := PackedVector2Array()
		for p in arm:
			world_arm.append(origin + p)
		draw_colored_polygon(world_arm, color)

		# Outward chevron glyph, centered between the hub edge and the tip.
		var mid: Vector2 = origin + dir * ((w + radius) * 0.5)
		draw_colored_polygon(_chevron(mid, dir, w * 1.1), divider_color)

	# Structural outline: the outer silhouette of the plus shape (12 points,
	# traced clockwise), so the whole D-pad reads as one solid molded piece.
	var l: float = radius
	var outline := PackedVector2Array([
		Vector2(-w, -l), Vector2(w, -l), Vector2(w, -w),
		Vector2(l, -w), Vector2(l, w), Vector2(w, w),
		Vector2(w, l), Vector2(-w, l), Vector2(-w, w),
		Vector2(-l, w), Vector2(-l, -w), Vector2(-w, -w),
	])
	var world_outline := PackedVector2Array()
	for p in outline:
		world_outline.append(origin + p)
	world_outline.append(world_outline[0])
	draw_polyline(world_outline, divider_color, 2.5, true)

	# Seams between each arm and the hub, so the arms read as distinct
	# physical buttons rather than one blob.
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

func _set_zone(zone: int) -> void:
	_in_dead_zone = zone == -1

	if zone == _active_zone:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _zone_held_since < MIN_ZONE_HOLD_SEC:
		return
	_zone_held_since = now

	if _active_zone != -1:
		Input.action_release(ACTIONS[_active_zone])
	if zone != -1:
		Input.action_press(ACTIONS[zone])

	_active_zone = zone
	queue_redraw()

func _release() -> void:
	_touch_index = -1
	_in_dead_zone = true
	_set_zone(-1)
