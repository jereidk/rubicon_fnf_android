extends LullabyTouchNoteInput
class_name LullabyPadNoteInput

## Pad gameplay mode ("Gameplay Control: Pad" in the Mobile settings).
##
## Asked for directly: "the arrow d-pad, literally, and in the position it
## already has, usable as gameplay to hit notes". So this is deliberately not
## a new control design - it is Chimera's escape pad's look and placement,
## driving the four note lanes instead of the crawl mechanic.
##
## ## Why it extends the Touch overlay instead of standing alone
##
## Everything that makes a touch mode correct is already solved in
## LullabyTouchNoteInput and none of it is about where the tap zones are:
## the multitouch refcount, sliding a hold from one zone to another,
## dispatch through RubiconTouchInput (so judgment windows, scoring,
## splashes, character animations and lane_state behave exactly like a
## keyboard), the reserved-Button sweep, hiding for pause/gameover/HUD-fade,
## the pendulum's round red button and its Showcase flash.
##
## Only two things differ, and they are the only two things overridden here:
## _lane_at(), which resolves a point to an arm instead of to a receptor,
## and _draw(), because unlike the Touch overlay this mode has to be visible
## to be usable.
##
## ## Lane mapping
##
## RubiconCharacter.mania_directions is [left, down, up, right], so lane 0 is
## left and lane 2 is up. The arms map straight onto that, which is also
## exactly what ChimeraEscapeDPad.ZONE_ACTIONS already does - the two pads
## agree by construction rather than by a copied table.

## Arm indices, clockwise from up, matching ChimeraEscapeDPad and
## RubiconVirtualDPad's own convention.
const ARM_UP := 0
const ARM_RIGHT := 1
const ARM_DOWN := 2
const ARM_LEFT := 3

const ARM_LANES := {
	ARM_UP: 2,
	ARM_RIGHT: 3,
	ARM_DOWN: 1,
	ARM_LEFT: 0,
}

const ARM_DIRS := {
	ARM_UP: Vector2.UP,
	ARM_RIGHT: Vector2.RIGHT,
	ARM_DOWN: Vector2.DOWN,
	ARM_LEFT: Vector2.LEFT,
}

## Chimera's escape pad is 300x300 anchored 20px off the bottom edge with a
## radius of 130 - i.e. its centre sits 170px above the bottom. Reproduced
## as margin + radius rather than as a fixed 170 so the pad keeps that same
## gap from the edge at every size instead of hanging off the screen at the
## top of the range.
const PAD_RADIUS := 130.0
const PAD_MARGIN := 40.0

## The dead hub in the middle, as a fraction of the radius. Same 0.38 the
## escape pad uses, so the two are the same shape.
const HUB_RATIO := 0.38

## A little past the arm tips, so a finger that lands just off the end of an
## arrow still counts. Below this everything is a miss rather than the
## nearest arm - a pad that answers a tap in the corner of the screen is not
## a pad.
const REACH_RATIO := 1.05

## The pad scales with the same row that scales the Touch tap targets and
## the mechanic button. It is called "Touch Note Hitbox Size" because that
## is what it was added for; it is the size row for every tap-driven mode
## and this is one.
const SIZE_MIN := 0.5
const SIZE_MAX := 2.0

@export var base_color: Color = Color(0.09, 0.09, 0.12, 0.35)
@export var pressed_color: Color = Color(1, 1, 1, 0.65)
@export var divider_color: Color = Color(1, 1, 1, 0.6)

## Chimera's crawl sequence puts its own five-zone pad at this exact spot,
## and it owns the screen while it runs. Two pads stacked on one another is
## not a layering problem to solve with z-order - one of them has to not be
## there. The lane hitboxes already vanish for that stretch through
## hide_sources; this is the same rule for this overlay.
@export var escape_pad: Control

func _ready() -> void:
	super()
	note_pressed.connect(_on_lane_changed)
	note_released.connect(_on_lane_changed)

func _on_lane_changed(_lane: int) -> void:
	queue_redraw()

## Radius in pixels right now. Read per query rather than cached because the
## setting can move mid-song from the console, and the pad is redrawn
## whenever a lane changes anyway.
func _radius() -> float:
	return PAD_RADIUS * clampf(Settings.lullaby_touch_note_hitbox_size, SIZE_MIN, SIZE_MAX)

## Bottom-centre of the viewport, in this overlay's own coordinates. The
## overlay is authored full-rect under the song's CanvasLayer, so its rect
## is the viewport and local == global; going through size anyway keeps it
## correct if that ever stops being true.
func _origin() -> Vector2:
	var radius: float = _radius()
	return Vector2(size.x * 0.5, size.y - (PAD_MARGIN + radius))

## The lane whose arm contains `pos`, or -1.
##
## Overrides the receptor zones of the Touch overlay. The hub returns -1 on
## purpose: the pendulum is played through the round red button in this mode
## exactly as it is in Touch, so a centre zone would be a second control for
## one action, and a dead hub is what makes the four arms feel like a pad
## rather than a pie chart.
func _lane_at(pos: Vector2) -> int:
	var arm: int = _arm_at(pos)
	if arm < 0:
		return -1
	return ARM_LANES[arm]

func _arm_at(pos: Vector2) -> int:
	var radius: float = _radius()
	var offset: Vector2 = (pos - global_position) - _origin()
	var distance: float = offset.length()

	if distance <= radius * HUB_RATIO * 1.15:
		return -1
	if distance > radius * REACH_RATIO:
		return -1

	# atan2 is 0 = right and +90 = down in Godot's Y-down screen space, so
	# rotating by 90+45 puts arm 0 (up) at the start of the first quadrant
	# and each arm spans 90 degrees clockwise.
	var angle: float = rad_to_deg(offset.angle()) + 135.0
	if angle < 0.0:
		angle += 360.0
	return int(angle / 90.0) % 4

func _is_held(arm: int) -> bool:
	return _lane_active_count.get(ARM_LANES[arm], 0) > 0

func _draw() -> void:
	var origin: Vector2 = _origin()
	var radius: float = _radius()
	var hub: float = radius * HUB_RATIO

	draw_colored_polygon(PackedVector2Array([
		origin + Vector2(-hub, -hub), origin + Vector2(hub, -hub),
		origin + Vector2(hub, hub), origin + Vector2(-hub, hub),
	]), base_color)

	for arm: int in ARM_DIRS:
		var dir: Vector2 = ARM_DIRS[arm]
		var perp: Vector2 = dir.rotated(PI / 2.0) * hub
		var inner: Vector2 = dir * hub
		var outer: Vector2 = dir * radius
		var held: bool = _is_held(arm)

		draw_colored_polygon(PackedVector2Array([
			origin + inner + perp, origin + outer + perp,
			origin + outer - perp, origin + inner - perp,
		]), pressed_color if held else base_color)

		# The chevron, so an arm reads as a direction and not as a bar.
		var mid: Vector2 = origin + dir * ((hub + radius) * 0.5)
		var chevron: float = hub * 1.1
		var across: Vector2 = dir.rotated(PI / 2.0)
		draw_colored_polygon(PackedVector2Array([
			mid + dir * chevron * 0.6,
			mid - dir * chevron * 0.4 + across * chevron * 0.55,
			mid - dir * chevron * 0.4 - across * chevron * 0.55,
		]), divider_color)

	var outline := PackedVector2Array([
		origin + Vector2(-hub, -radius), origin + Vector2(hub, -radius),
		origin + Vector2(hub, -hub), origin + Vector2(radius, -hub),
		origin + Vector2(radius, hub), origin + Vector2(hub, hub),
		origin + Vector2(hub, radius), origin + Vector2(-hub, radius),
		origin + Vector2(-hub, hub), origin + Vector2(-radius, hub),
		origin + Vector2(-radius, -hub), origin + Vector2(-hub, -hub),
	])
	outline.append(outline[0])
	draw_polyline(outline, divider_color, 2.5, true)

## Everything the Touch overlay hides for, plus Chimera's crawl sequence.
func _update_visibility() -> void:
	super()
	if not visible:
		return
	if escape_pad != null and is_instance_valid(escape_pad) \
			and "mechanic_active" in escape_pad and bool(escape_pad.get("mechanic_active")):
		_hide_and_release()
		return
	queue_redraw()
