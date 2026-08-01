extends Control
class_name RubiconMechanicHitbox

## Full-rect touch zone for a song's "special mechanic" input (e.g. Safety
## Lullaby's pendulum, bound to lullaby_special - see
## song_touch_controls.gd's own doc comment for the general pattern that
## button used). Meant to sit exactly in RubiconMobileControls' own
## hitbox_top_percent dead zone (the top strip that hitbox deliberately
## leaves untouched for HUD elements) - a song only ever has one mechanic
## active during gameplay, so unlike the 4-lane note hitbox there's no
## need to divide this into zones: the whole rect is one big, forgiving
## tap target, styled the same way (translucent fill + outline) but red to
## read as a different kind of input from the note lanes below it.
##
## Unlike RubiconMobileControls, this uses Control's own _gui_input()
## instead of raw _input() with manual position math - simpler, and fine
## here because a single zone has no per-lane state to track; ordinary GUI
## hit-testing already limits events to this control's own rect.

signal hit
signal released

@export var action: StringName = &"lullaby_special"

@export var show_outline: bool = true
@export var outline_color: Color = Color(1, 0, 0, 0.55)
@export var outline_width: float = 2.0
@export var fill_color: Color = Color(1, 0, 0, 0.08)
@export var pressed_fill_color: Color = Color(1, 0, 0, 0.28)

const NOTCH_NONE := 0
const NOTCH_TOP_LEFT := 1
const NOTCH_TOP_RIGHT := 2
const NOTCH_BOTTOM_LEFT := 3
const NOTCH_BOTTOM_RIGHT := 4

## Rectangular corner cut out of this zone so a button drawn in that corner
## (e.g. the pause button, top-right) doesn't sit on top of red tint that
## implies it's also part of the mechanic hitbox. _has_point() below also
## excludes it from hit-testing directly, so a tap there can't land on this
## zone even if the button's own z-order ever changes.
##
## Plain int (with an @export_enum hint) rather than a real enum type -
## Godot 4.7 chokes on a class_name script assigning its own nested enum
## to a same-named typed export ("Cannot assign a value of type X as X"),
## so this sidesteps that entirely.
@export_enum("None", "Top Left", "Top Right", "Bottom Left", "Bottom Right") var notch_corner: int = NOTCH_NONE
@export var notch_size: Vector2 = Vector2.ZERO

const MOUSE_TOUCH_INDEX := -1000

var _active_touches: Dictionary = {}

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		# _gui_input() only fires for a visible Control anyway, but also
		# stop consuming/blocking clicks meant for whatever's underneath.
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			queue_redraw()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release_all()

func _has_point(point: Vector2) -> bool:
	var notch: Rect2 = _notch_rect()
	if notch.size != Vector2.ZERO and notch.has_point(point):
		return false
	return Rect2(Vector2.ZERO, size).has_point(point)

func _notch_rect() -> Rect2:
	if notch_corner == NOTCH_NONE or notch_size.x <= 0.0 or notch_size.y <= 0.0:
		return Rect2()

	var x: float = 0.0 if notch_corner in [NOTCH_TOP_LEFT, NOTCH_BOTTOM_LEFT] else size.x - notch_size.x
	var y: float = 0.0 if notch_corner in [NOTCH_TOP_LEFT, NOTCH_TOP_RIGHT] else size.y - notch_size.y
	return Rect2(x, y, notch_size.x, notch_size.y)

func _draw() -> void:
	var is_pressed: bool = not _active_touches.is_empty()
	var fill: Color = pressed_fill_color if is_pressed else fill_color
	var notch: Rect2 = _notch_rect()

	if notch.size == Vector2.ZERO:
		if fill.a > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), fill, true)
		if show_outline:
			draw_rect(Rect2(Vector2.ZERO, size), outline_color, false, outline_width)
		return

	# L-shaped zone (full rect minus the notch corner): fill as two plain
	# rects (no per-rect border, or the shared inner edge would double up
	# as a stray line), then trace the six-point hexagon perimeter by hand
	# so the cut reads as intentional instead of the outline just stopping.
	if fill.a > 0.0:
		for fill_rect in _fill_rects(notch):
			draw_rect(fill_rect, fill, true)

	if show_outline:
		var points: PackedVector2Array = _hexagon_points(notch)
		points.append(points[0])
		draw_polyline(points, outline_color, outline_width, true)

## Two non-overlapping rects covering the full zone minus the notch corner.
func _fill_rects(notch: Rect2) -> Array[Rect2]:
	var w: float = size.x
	var h: float = size.y
	var nw: float = notch.size.x
	var nh: float = notch.size.y

	match notch_corner:
		NOTCH_TOP_RIGHT:
			return [Rect2(0, 0, w - nw, h), Rect2(w - nw, nh, nw, h - nh)]
		NOTCH_TOP_LEFT:
			return [Rect2(nw, 0, w - nw, h), Rect2(0, nh, nw, h - nh)]
		NOTCH_BOTTOM_RIGHT:
			return [Rect2(0, 0, w - nw, h), Rect2(w - nw, 0, nw, h - nh)]
		NOTCH_BOTTOM_LEFT:
			return [Rect2(nw, 0, w - nw, h), Rect2(0, 0, nw, h - nh)]
		_:
			return [Rect2(0, 0, w, h)]

## Six points tracing this zone's perimeter clockwise from (0,0), cutting
## across whichever corner notch is set.
func _hexagon_points(notch: Rect2) -> PackedVector2Array:
	var w: float = size.x
	var h: float = size.y

	match notch_corner:
		NOTCH_TOP_RIGHT:
			return PackedVector2Array([
				Vector2(0, 0), Vector2(notch.position.x, 0), Vector2(notch.position.x, notch.size.y),
				Vector2(w, notch.size.y), Vector2(w, h), Vector2(0, h),
			])
		NOTCH_TOP_LEFT:
			return PackedVector2Array([
				Vector2(notch.size.x, 0), Vector2(w, 0), Vector2(w, h),
				Vector2(0, h), Vector2(0, notch.size.y), Vector2(notch.size.x, notch.size.y),
			])
		NOTCH_BOTTOM_RIGHT:
			return PackedVector2Array([
				Vector2(0, 0), Vector2(w, 0), Vector2(w, notch.position.y),
				Vector2(notch.position.x, notch.position.y), Vector2(notch.position.x, h), Vector2(0, h),
			])
		NOTCH_BOTTOM_LEFT:
			return PackedVector2Array([
				Vector2(0, 0), Vector2(w, 0), Vector2(w, h),
				Vector2(notch.size.x, h), Vector2(notch.size.x, notch.position.y), Vector2(0, notch.position.y),
			])
		_:
			return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(MOUSE_TOUCH_INDEX, event.pressed)

func _handle_touch(index: int, pressed: bool) -> void:
	if pressed:
		if _active_touches.has(index):
			return
		_active_touches[index] = true
		if _active_touches.size() == 1:
			_dispatch(true)
			hit.emit()
	else:
		if not _active_touches.has(index):
			return
		_active_touches.erase(index)
		if _active_touches.is_empty():
			_dispatch(false)
			released.emit()

	queue_redraw()

func _dispatch(pressed: bool) -> void:
	var press_event := InputEventAction.new()
	press_event.action = action
	press_event.pressed = pressed
	Input.parse_input_event(press_event)

func _release_all() -> void:
	if _active_touches.is_empty():
		return

	_active_touches.clear()
	_dispatch(false)
	released.emit()
	queue_redraw()
