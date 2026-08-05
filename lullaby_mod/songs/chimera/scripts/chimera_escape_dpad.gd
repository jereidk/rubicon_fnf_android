extends Control
class_name ChimeraEscapeDPad

## Touch control for Chimera's crawl/escape mechanic (CrawlTimingController,
## mch_crawling.gd) - a D-pad drawn the same way as the Collector's Shop's
## own menu navigation pad (RubiconVirtualDPad's ARROWS look: hand-drawn hub
## + 4 chevron arms, no texture assets), plus a 5th center zone for the
## mechanic's "special" (SPACE) input.
##
## Not built on RubiconVirtualDPad directly: that pad is one continuous drag
## surface resolved into 4 angle zones (right for "any direction is always
## valid, e.g. menu navigation"), while here there are 5 discrete targets
## and only one of them is ever "correct" (current_input) - so each zone is
## hit-tested as its own button instead, and the current_input zone is lit
## up while the other 4 stay dimmed (still visible, for the same reason a
## real D-pad's unlit arms stay visible - shows the shape/consistency
## without claiming every direction does something right now).
##
## Unlike ChimeraSpecialTouchControls' shared "TAP!" button (which only
## ever covered the mechanic's lullaby_special prompts), this covers all 5
## possible prompts CrawlTimingController actually asks for (SPACE + the 4
## note lanes - see its own input_display_names), and dispatches straight
## through its handle_input_pressed()/handle_input_released() rather than
## synthesizing InputEvents - the mania_lane* entries are resolved through
## RubiconLevelNoteInputMap.has_event_registered() there, not a plain
## project input action, so a fake InputEventAction wouldn't be recognized.

signal zone_pressed(zone: int)
signal zone_released(zone: int)

@export var crawl_timing: CrawlTimingController

## Chimera's own 4-lane note hitbox (MobileControls) has no default_hud/
## gameover_source wired up in sng_chimera.tscn, so it never hides itself
## during cutscenes (see rubicon_mobile_controls.gd _process()'s guard) -
## it would otherwise sit drawn underneath this pad for the whole escape
## sequence. Optional: left unset, this pad just doesn't touch it.
@export var lane_hitbox: Control

## Zone layout: up/right/down/left arms (matching CrawlTimingController's
## own input_display_names arrow mapping) plus a center zone for the
## special/SPACE input. Angle math below assigns 0=up, 1=right, 2=down,
## 3=left going clockwise, same convention RubiconVirtualDPad uses.
const ZONE_UP := 0
const ZONE_RIGHT := 1
const ZONE_DOWN := 2
const ZONE_LEFT := 3
const ZONE_CENTER := 4

const ZONE_ACTIONS := {
	ZONE_UP: &"mania_lane2",
	ZONE_RIGHT: &"mania_lane3",
	ZONE_DOWN: &"mania_lane1",
	ZONE_LEFT: &"mania_lane0",
	ZONE_CENTER: &"lullaby_special",
}
const ARM_DIRS := {
	ZONE_UP: Vector2.UP,
	ZONE_RIGHT: Vector2.RIGHT,
	ZONE_DOWN: Vector2.DOWN,
	ZONE_LEFT: Vector2.LEFT,
}

@export var radius: float = 130.0
@export var base_color: Color = Color(0.09, 0.09, 0.12, 0.35)
@export var pressed_color: Color = Color(1, 1, 1, 0.65)

## The escape mechanic already tells the player which way to crawl, but only
## through the key prompt - the D-pad itself gave no hint, so the direction
## you actually have to press is drawn in red instead of the neutral white.
## It stays lit with no finger on it, since the whole point is to be readable
## before you reach for it.
@export var required_color: Color = Color(0.85, 0.15, 0.15, 0.7)
@export var divider_color: Color = Color(1, 1, 1, 0.6)
## How much the 4 non-relevant zones fade out relative to base_color/
## divider_color, so the currently-asked-for zone reads as the obvious
## target without hiding the rest of the pad's shape.
@export_range(0.0, 1.0, 0.01) var dimmed_alpha_scale: float = 0.35

@export var haptic_feedback: bool = true
@export var haptic_duration_ms: int = 35

const MOUSE_TOUCH_INDEX := -1000

var _active_touches: Dictionary = {} # touch/mouse index -> zone
var _flash_amount: float = 0.0
var _flash_tween: Tween

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	# Needs to keep running through get_tree().paused = true so it can react
	# to that transition at all - same reasoning as RubiconMechanicHitbox/
	# RubiconMobileControls' identical process_mode override.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not crawl_timing:
		return

	var should_show: bool = _mechanic_wants_input() and not get_tree().paused

	if should_show != visible:
		visible = should_show
		mouse_filter = Control.MOUSE_FILTER_STOP if should_show else Control.MOUSE_FILTER_IGNORE
		if lane_hitbox:
			lane_hitbox.visible = not should_show
		if not should_show:
			_release_all()

	if visible:
		queue_redraw()

func _mechanic_wants_input() -> bool:
	if crawl_timing.autoplay:
		return false
	if not crawl_timing.attempt_active:
		return false
	match crawl_timing.mode:
		CrawlTimingController.CrawlingStatus.TRAVELING, CrawlTimingController.CrawlingStatus.OPENING:
			return true
		_:
			return false

func _get_origin() -> Vector2:
	return size * 0.5

func _current_zone() -> int:
	if not crawl_timing:
		return -1
	for zone in ZONE_ACTIONS:
		if ZONE_ACTIONS[zone] == crawl_timing.current_input:
			return zone
	return -1

func _draw() -> void:
	var origin: Vector2 = _get_origin()
	var w: float = radius * 0.38
	var l: float = radius
	var current_zone: int = _current_zone()

	var hub := PackedVector2Array([
		origin + Vector2(-w, -w), origin + Vector2(w, -w),
		origin + Vector2(w, w), origin + Vector2(-w, w),
	])
	draw_colored_polygon(hub, _zone_color(ZONE_CENTER, current_zone))
	if current_zone == ZONE_CENTER:
		draw_circle(origin, w * 0.5, divider_color)

	for zone in ARM_DIRS:
		var dir: Vector2 = ARM_DIRS[zone]
		var perp: Vector2 = dir.rotated(PI / 2.0) * w
		var inner: Vector2 = dir * w
		var outer: Vector2 = dir * l
		var color: Color = _zone_color(zone, current_zone)

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
		var chevron_color: Color = divider_color if zone == current_zone else _dimmed(divider_color)
		draw_colored_polygon(PackedVector2Array([apex, base1, base2]), chevron_color)

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

func _dimmed(color: Color) -> Color:
	var c: Color = color
	c.a *= dimmed_alpha_scale
	return c

func _zone_color(zone: int, current_zone: int) -> Color:
	var is_required: bool = _is_required_zone(zone)
	var tint: Color = required_color if is_required else pressed_color

	if zone != current_zone:
		# A required zone stays visible without a finger on it; every other
		# idle zone dims out the way it always did.
		return tint if is_required else _dimmed(base_color)

	var is_pressed: bool = _active_touches.values().has(zone)
	if is_pressed:
		return tint.lerp(Color(1.0, 1.0, 1.0, tint.a), _flash_amount * 0.7)
	return tint.lerp(base_color, 0.5)

## crawl_timing.current_input is the action the mechanic is waiting on right
## now, and ZONE_ACTIONS maps each zone to the action it fires - so matching
## the two is all it takes to know which zone to mark. Duck-typed and empty
## checked so this stays harmless if the mechanic is idle or unassigned.
func _is_required_zone(zone: int) -> bool:
	if crawl_timing == null or not "current_input" in crawl_timing:
		return false

	var required: StringName = crawl_timing.current_input
	if required.is_empty():
		return false

	return ZONE_ACTIONS.get(zone, &"") == required

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_all()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(MOUSE_TOUCH_INDEX, event.position, event.pressed)

func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _active_touches.has(index):
			return
		var zone: int = _zone_at(pos)
		if zone == -1:
			return
		_active_touches[index] = zone
		if crawl_timing:
			crawl_timing.handle_input_pressed(ZONE_ACTIONS[zone])
		zone_pressed.emit(zone)
		if zone == _current_zone():
			_flash()
			if haptic_feedback:
				Input.vibrate_handheld(haptic_duration_ms)
	else:
		if not _active_touches.has(index):
			return
		var zone: int = _active_touches[index]
		_active_touches.erase(index)
		if crawl_timing:
			crawl_timing.handle_input_released(ZONE_ACTIONS[zone])
		zone_released.emit(zone)

	queue_redraw()

func _zone_at(pos: Vector2) -> int:
	var origin: Vector2 = _get_origin()
	var offset: Vector2 = pos - origin
	var dist: float = offset.length()
	var w: float = radius * 0.38

	if dist <= w * 1.15:
		return ZONE_CENTER

	if dist > radius * 1.05:
		return -1

	# atan2 is 0=right, 90=down (Godot's Y-down screen space); rotate so
	# zone 0 (up) starts at -45deg and each zone spans 90deg going clockwise -
	# same convention as RubiconVirtualDPad._update_zone().
	var angle_deg: float = rad_to_deg(offset.angle()) + 90.0 + 45.0
	if angle_deg < 0.0:
		angle_deg += 360.0
	return int(angle_deg / 90.0) % 4

func _release_all() -> void:
	if _active_touches.is_empty():
		return

	for index in _active_touches.keys():
		var zone: int = _active_touches[index]
		if crawl_timing:
			crawl_timing.handle_input_released(ZONE_ACTIONS[zone])
		zone_released.emit(zone)

	_active_touches.clear()
	queue_redraw()

func _flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	_flash_amount = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash_amount, 1.0, 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_flash_amount(v: float) -> void:
	_flash_amount = v
	queue_redraw()
