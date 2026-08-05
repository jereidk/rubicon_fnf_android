extends Node2D
class_name ChimeraKeyPromptTouch

## Draws the escape mechanic's "press this" prompt as a D-pad direction
## instead of a keyboard keycap.
##
## The mechanic ships one generic keycap sprite (KeyNote.tres has exactly two
## animations, idle and press) with the direction written on a Label over it.
## There are no per-direction textures to swap to, so on touch the keycap and
## its label stop drawing and the shape below is drawn in their place.
##
## Everything uses the same action-to-direction mapping as the escape D-pad's
## ZONE_ACTIONS, so the prompt and the control underneath it cannot disagree -
## which was the whole complaint. Red matches the D-pad's own "this is the one
## to press" highlight, so the two read as one instruction shown twice.
##
## This node is a child of Key on purpose. Key is what the mechanic moves to a
## random position, fades in over appear_time, pops on success/fail and hides
## between attempts; inheriting its transform and modulate means all of that
## applies here for free instead of being re-implemented and drifting out of
## sync. That inheritance is also why the keycap is hidden with
## self_modulate rather than visible: self_modulate does not propagate to
## children, so it silences the sprite without taking this node down with it,
## and nothing in mch_crawling.gd writes self_modulate, whereas it sets
## key.visible = true on every single show_prompt().

const ACTION_DIRECTIONS := {
	&"mania_lane0": Vector2.LEFT,
	&"mania_lane1": Vector2.DOWN,
	&"mania_lane2": Vector2.UP,
	&"mania_lane3": Vector2.RIGHT,
}

## lullaby_special is the D-pad's centre zone, which has no direction - it is
## drawn as a filled disc instead of an arrow.
const ACTION_CENTER := &"lullaby_special"

@export var mechanic: Node

## Silenced while touch controls are in use, since this replaces them.
@export var keycap: CanvasItem
@export var keycap_label: CanvasItem

## Sized to sit inside the TimingKey ring (183x190 at full progress, so 91px
## of radius) rather than inside the keycap it replaces, since the ring is the
## one piece of the original prompt that stays on screen.
@export var radius: float = 70.0
@export var accent_color: Color = Color(0.85, 0.15, 0.15, 1.0)
@export var outline_color: Color = Color(1, 1, 1, 0.85)
@export var outline_width: float = 4.0

var _enabled: bool = false
var _current: StringName = &""

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_enabled = settings_enabled and has_touch

	# On a keyboard the original keycap is the correct thing to show, so this
	# takes itself out of the way entirely rather than drawing over it.
	if not _enabled:
		visible = false
		set_process(false)
		return

	if keycap:
		keycap.self_modulate.a = 0.0
	if keycap_label:
		keycap_label.self_modulate.a = 0.0

func _process(_delta: float) -> void:
	if mechanic == null or not "current_input" in mechanic:
		return

	var now: StringName = mechanic.current_input
	if now == _current:
		return

	_current = now
	queue_redraw()

## No filled backing disc, deliberately. Key.modulate is driven from WHITE to
## BLACK across the attempt as the "time is running out" cue
## (update_progress_visual), and modulate multiplies down into this node - so a
## dark disc would have swallowed the arrow drawn on it well before the timer
## expired. Drawing only the arrow and a thin ring means this darkens exactly
## the way the keycap it replaced did, which is the behaviour the cue was
## designed around, and it leaves the expanding TimingKey ring unobscured.
func _draw() -> void:
	if not _enabled or _current.is_empty():
		return

	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, outline_color, outline_width, true)

	if _current == ACTION_CENTER:
		draw_circle(Vector2.ZERO, radius * 0.42, accent_color)
		draw_arc(Vector2.ZERO, radius * 0.42, 0.0, TAU, 32, outline_color, outline_width * 0.6, true)
		return

	if not ACTION_DIRECTIONS.has(_current):
		return

	# An arrow built from the direction vector rather than four hardcoded
	# point sets, so adding a direction is a dictionary entry.
	var direction: Vector2 = ACTION_DIRECTIONS[_current]
	var side: Vector2 = Vector2(-direction.y, direction.x)
	var tip: Vector2 = direction * radius * 0.62
	var back: Vector2 = -direction * radius * 0.18

	var head := PackedVector2Array([
		tip,
		back + side * radius * 0.46,
		back - side * radius * 0.46,
	])
	draw_colored_polygon(head, accent_color)
	draw_polyline(PackedVector2Array([head[0], head[1], head[2], head[0]]), outline_color, outline_width * 0.6, true)

	# Short tail, so the shape reads as an arrow rather than a triangle.
	var tail_half: Vector2 = side * radius * 0.16
	draw_colored_polygon(PackedVector2Array([
		back + tail_half,
		back - tail_half,
		back - tail_half - direction * radius * 0.44,
		back + tail_half - direction * radius * 0.44,
	]), accent_color)
