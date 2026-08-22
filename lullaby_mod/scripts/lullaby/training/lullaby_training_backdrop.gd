class_name LullabyTrainingBackdrop extends Control

## What a drill runs on, in place of the test song's Funkin stage.
##
## One backdrop for all three mechanics, which is the constraint that decided
## everything here. Their palettes were sampled before anything was drawn:
##
##   pendulum   gold/brass #705010 (31% of its atlas), black, grey, a pale
##              cyan highlight
##   pulse      black and dark red #301010, with an ECG line that is #333333,
##              white on a hit and red on a miss
##   typing     unown red #f01010 (19%), a grey-violet Celebi, white letters
##
## So the backdrop has to be dark and COOL. Not red - that would kill both
## the unowns and the miss vignette. Not gold - that would flatten the
## pendulum. Not light - the letters and the ECG line are white. A navy is
## the one family that lets all three read.
##
## Which is also, conveniently, what the console already is: Training is
## launched from the Cabinet's console, and menus/console/Background.png is
## that console's own backdrop, a navy diagonal gradient. Reusing it means
## the drill reads as "still inside the console you clicked from" and costs
## one already-imported 0.37 MB texture.
##
## Over it goes a calibration grid, which is the half that says this is a
## practice rig rather than a song - and the beat marks along the bottom are
## a real metronome driven by the level clock, so all three drills get a
## visible pulse to time against whether or not their own mechanic shows one.

## The console's own backdrop. Same file console_bg.tscn puts behind its
## rotating shapes.
const BACKGROUND_TEXTURE := "res://lullaby_mod/assets/menus/console/Background.png"

## The two cell-shaded shapes console_bg spins in that navy, in the colours
## its own scene authors on shd_cell (Color(0.241, 0.102, 0.405) and
## Color(0.120, 0.126, 0.318)).
##
## Drawn here rather than instanced, deliberately. console_bg.tscn is a
## 720x540 SubViewport with own_world_3d, a WorldEnvironment with fog and a
## DirectionalLight3D - CLAUDE.md measures that family of node at about
## 1.2ms of the shop's frame - and it also carries a full-rect black
## ColorRect that the console's own startup choreography fades out, plus an
## AnimationPlayer with no autoplay. Reusing it would mean paying a 3D pass
## and reproducing console.gd's startup sequence to get a shape to move. Two
## rotating quads cost a transform update.
const SHAPE_NEAR := Color("3d1a67")
const SHAPE_FAR := Color("1f2051")

## Radians per second. Slow enough that it never pulls the eye off the
## mechanic - a full turn takes about three and a half minutes.
const SHAPE_SPIN := 0.03

## How much of the console's gradient and its shapes survive. See _ready().
const NAVY_DIM := 0.72

## The calibration grid. One cell is a ninth of the screen height, so the
## spacing is the same on any aspect ratio and the centre lines always land
## on a cell boundary.
const GRID_CELLS := 9.0
## Faint, but not invisible: it has to read over the navy gradient, which
## is lighter than the flat near-black this replaced.
const GRID_COLOR := Color(1, 1, 1, 0.075)

## Only the VERTICAL centre line is drawn as a guide.
##
## A horizontal one is the obvious companion and it is wrong here: the pulse
## drill's ECG line lies along y = centre, so the guide would run underneath
## it for the whole drill. The vertical one is the useful half anyway - it is
## where the pendulum is hittable, where the typing letters sit, and where
## the heartbeat lands.
const GUIDE_COLOR := Color(1, 1, 1, 0.10)

## The metronome. Cool blue so it cannot be confused with the miss vignette,
## which is the only red thing a drill ever shows.
const BEAT_COLOR := Color(0.55, 0.72, 1.0)
const BEAT_DIM := 0.10
const BEAT_LIT := 0.55
## The downbeat stays brighter than the rest of the bar even between beats.
const BEAT_DOWN_DIM := 0.22

const BEAT_WIDTH := 6.0
const BEAT_HEIGHT := 30.0
const BEAT_MARGIN := 46.0

## Fallback when the clock cannot say. 4/4 is what the test song is.
const DEFAULT_BEATS := 4

var _clock: Node
var _level: Node
var _shape_near: Control
var _shape_far: Control
var _beats: Control

func _init() -> void:
	name = "TrainingBackdrop"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## The level is what owns the clock and the time signature. Optional: with no
## clock the beat marks simply sit at their resting brightness, which is what
## a backdrop should do rather than disappear.
func setup(level: Node) -> void:
	_level = level
	if level != null and is_instance_valid(level):
		_clock = level.get(&"clock")

func _ready() -> void:
	var navy := TextureRect.new()
	navy.name = "Navy"
	# load_from_file rather than load(): this runs against the imported
	# texture in a real build, and load() is the right call there - but the
	# import is what carries the ASTC, so the path is the resource path.
	navy.texture = load(BACKGROUND_TEXTURE)
	navy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	navy.stretch_mode = TextureRect.STRETCH_SCALE
	navy.set_anchors_preset(Control.PRESET_FULL_RECT)
	navy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dimmed, because the gradient is lit from its top-right corner and that
	# is exactly where the drill's hit/miss readout sits. At full strength
	# the bright patch competes with the numbers on top of it.
	navy.modulate = Color(NAVY_DIM, NAVY_DIM, NAVY_DIM, 1.0)
	add_child(navy)

	_shape_far = _add_shape(SHAPE_FAR, Vector2(0.92, 0.17), 0.34, -0.42)
	_shape_near = _add_shape(SHAPE_NEAR, Vector2(0.21, 0.84), 0.32, 0.61)

	var grid := _Grid.new()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)

	_beats = _Beats.new()
	_beats.set_anchors_preset(Control.PRESET_FULL_RECT)
	_beats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_beats)

## A rotating quad. Its own Control with a one-off _draw, spun by setting
## `rotation` - so the draw commands are built once and every frame after is
## a transform update rather than a redraw.
func _add_shape(color: Color, anchor: Vector2, size_ratio: float, tilt: float) -> Control:
	var shape := _Shape.new()
	shape.color = color
	shape.anchor_ratio = anchor
	shape.size_ratio = size_ratio
	shape.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Started tilted. An axis-aligned quad reads as a flat rectangle stuck to
	# the screen edge; the console's own shapes are never square-on.
	shape.rotation = tilt
	# Same register as the gradient they belong to - they are background, and
	# the drill's own art is what the eye should land on.
	shape.modulate = Color(NAVY_DIM, NAVY_DIM, NAVY_DIM, 1.0)
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shape)
	return shape

func _process(delta: float) -> void:
	if _shape_near != null:
		_shape_near.rotation += SHAPE_SPIN * delta
	if _shape_far != null:
		_shape_far.rotation -= SHAPE_SPIN * 0.7 * delta

	if _beats == null:
		return
	var beats: int = _beats_per_measure()
	var position_in_bar: float = _beat_position()
	_beats.apply(beats, position_in_bar)

## Where the song is within its bar, as beats. Whole part = which beat,
## fraction = how far into it, which is what drives the decay.
func _beat_position() -> float:
	if _clock == null or not is_instance_valid(_clock):
		return -1.0
	var beat: float = _clock.get(&"time_beat")
	var beats: int = _beats_per_measure()
	if beats <= 0:
		return -1.0
	return fposmod(beat, float(beats))

## Read off the time change in force, not assumed: Monochrome and Safety
## Lullaby are 3/4, and this file's own history has a bug in it from taking
## 4/4 for granted (see rubicon_character.gd's dancing_measure_step).
func _beats_per_measure() -> int:
	if _level == null or not is_instance_valid(_level) or _clock == null:
		return DEFAULT_BEATS
	var metadata: Object = _level.get(&"metadata")
	if metadata == null:
		return DEFAULT_BEATS
	var changes: Array = metadata.get(&"time_changes")
	if changes == null or changes.is_empty():
		return DEFAULT_BEATS
	var change: Object = RubiconTimeChange.get_time_change_at_millisecond(
		changes, _clock.get(&"time_milliseconds"))
	if change == null:
		return DEFAULT_BEATS
	return maxi(int(change.get(&"time_signature_numerator")), 1)

class _Shape extends Control:
	var color: Color = Color.WHITE
	## Where the quad's centre sits, as a fraction of the screen.
	var anchor_ratio: Vector2 = Vector2(0.5, 0.5)
	## Its side, as a fraction of the screen height.
	var size_ratio: float = 0.3

	func _draw() -> void:
		var centre: Vector2 = size * anchor_ratio
		var half: float = size.y * size_ratio * 0.5
		# Drawn around the control's own origin so `rotation` spins it about
		# its centre rather than about the corner of the screen.
		var points := PackedVector2Array([
			centre + Vector2(-half, -half),
			centre + Vector2(half, -half),
			centre + Vector2(half, half),
			centre + Vector2(-half, half),
		])
		draw_colored_polygon(points, color)
		pivot_offset = centre

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

class _Grid extends Control:
	func _draw() -> void:
		var step: float = size.y / LullabyTrainingBackdrop.GRID_CELLS
		if step <= 0.0:
			return

		# Started from the centre outwards rather than from 0, so the middle
		# of the screen is always a line and the mechanic sits on it.
		var x: float = fposmod(size.x * 0.5, step)
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), LullabyTrainingBackdrop.GRID_COLOR, 1.0)
			x += step
		var y: float = fposmod(size.y * 0.5, step)
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), LullabyTrainingBackdrop.GRID_COLOR, 1.0)
			y += step

		draw_line(Vector2(size.x * 0.5, 0), Vector2(size.x * 0.5, size.y),
			LullabyTrainingBackdrop.GUIDE_COLOR, 2.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

## The only thing here that redraws per frame, and it is eight small rects.
## The grid and the shapes are built once; a shape moves by its transform.
class _Beats extends Control:
	var beats: int = LullabyTrainingBackdrop.DEFAULT_BEATS
	## Position within the bar in beats, or negative when there is no clock.
	var position_in_bar: float = -1.0

	func apply(bar_beats: int, position: float) -> void:
		if bar_beats == beats and is_equal_approx(position, position_in_bar):
			return
		beats = bar_beats
		position_in_bar = position
		queue_redraw()

	func _draw() -> void:
		if beats <= 0:
			return
		var current: int = floori(position_in_bar) if position_in_bar >= 0.0 else -1
		var into_beat: float = position_in_bar - floorf(position_in_bar) if position_in_bar >= 0.0 else 0.0

		for i in beats:
			var at: float = size.x * (float(i) + 0.5) / float(beats)
			var resting: float = LullabyTrainingBackdrop.BEAT_DOWN_DIM if i == 0 \
				else LullabyTrainingBackdrop.BEAT_DIM
			var alpha: float = resting
			if i == current:
				# Full on the beat, decaying back to resting across it.
				alpha = lerpf(LullabyTrainingBackdrop.BEAT_LIT, resting,
					clampf(into_beat * 1.6, 0.0, 1.0))

			var color: Color = LullabyTrainingBackdrop.BEAT_COLOR
			color.a = alpha
			draw_rect(Rect2(
				at - LullabyTrainingBackdrop.BEAT_WIDTH * 0.5,
				size.y - LullabyTrainingBackdrop.BEAT_MARGIN - LullabyTrainingBackdrop.BEAT_HEIGHT,
				LullabyTrainingBackdrop.BEAT_WIDTH,
				LullabyTrainingBackdrop.BEAT_HEIGHT), color)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
