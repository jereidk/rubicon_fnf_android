extends Control
class_name RubiconPaintedKeyboard

## An on-screen QWERTY keyboard that is painted, not built.
##
## RubiconOnScreenKeyboard makes one Button per key inside nested containers.
## That is the obvious way to do it and it is what Monochrome shipped with,
## but on device it costs a draw call per keycap and per label: the
## diagnostics log has two censuses with an identical scene population -
## 1088 nodes, notes=0, trees=14 - that differ only in whether the keyboard
## is up, and they read draw=13 against draw=268, with the GPU going 6.8ms ->
## 12.0ms. 255 of those calls are single quads that batch with nothing,
## because a StyleBoxFlat with rounded corners is a polygon command and every
## polygon command flushes the rect batch the glyphs would otherwise share.
##
## So this draws the whole keyboard from one _draw(): every keycap goes into
## a single triangle array (one polygon command, corners still rounded), and
## then every letter is drawn, so the glyphs batch among themselves against
## the one font atlas. Two or three draw calls for the entire keyboard.
##
## It is a Control with no children at all, which means the usual Button
## machinery - hover, focus, hit-testing, the pressed stylebox - does not
## exist here and is replaced by:
##
##   _has_point()   so taps that land in the gaps between keys fall through
##                  to whatever is behind, exactly as they did when the gaps
##                  were container padding rather than a Button
##   _gui_input()   which maps a tap position to a key rect
##   flash()        which the caller uses to light a key up, and which is the
##                  reason a painted keyboard was worth having in the first
##                  place: the system keyboard belongs to another app and
##                  cannot be animated at all
##
## Kept separate from on_screen_keyboard.gd rather than replacing it. That
## script is one of the ones carried over from the pck and is still the
## reference for what the layout is meant to be.

signal key_pressed(character: String)

const ROWS: Array[String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

## Quarter-circle subdivisions per corner. Four is indistinguishable from a
## StyleBoxFlat's own rounding at these key sizes and keeps the whole
## keyboard under a thousand triangles, which is nothing next to the 255
## draw calls it replaces.
const CORNER_SEGMENTS := 4

## Width of the feathered skirt around each cap, in this control's local
## units. Stands in for the antialiasing a StyleBoxFlat does for free.
const FEATHER := 1.0

## How much deeper than the flash colour a lit key's edge goes. Monochrome
## flashes at the unowns' #ff0000, and this lands its rim on #c60000 - which
## is the second most common red in tex_mch_unown.png, so the lit key ends up
## built out of the same two reds the unowns themselves are.
const EDGE_FLASH_DARKEN := 0.223

const SPACE_LABEL := "SPACE"

@export var key_size: Vector2 = Vector2(96, 96):
	set(value):
		key_size = value
		_dirty = true
		queue_redraw()

@export var key_gap: float = 10.0:
	set(value):
		key_gap = value
		_dirty = true
		queue_redraw()

@export var space_width: float = 460.0:
	set(value):
		space_width = value
		_dirty = true
		queue_redraw()

@export var corner_radius: float = 10.0

## The lip along the bottom of each cap. Drawn the way StyleBoxFlat draws a
## border: the darker shape underneath, the lighter face on top of it, inset
## by this much at the bottom only.
@export var key_lip: float = 4.0

## Border on all four sides, in the same shape as the lip. Zero leaves the
## cap with a bottom lip only, which is what every caller had before this
## existed. Above zero the cap reads as outlined rather than raised, which is
## what a song whose whole art style is heavy outlines wants.
@export var outline_width: float = 0.0

## Only used when outline_width is above zero. Below it the edge stays a
## darkened key_color, so a caller that sets no outline gets exactly the old
## raised keycap.
@export var outline_color: Color = Color("000000")

@export var key_color: Color = Color("2f2f36")
@export var label_color: Color = Color("e8e8ee")
@export var font_size: int = 34

## How long a key stays lit after flash(), and what colour it goes. This
## replaces the keycap's own colour rather than multiplying it - a near-black
## cap multiplied by anything is still near-black, which is how the first
## version of this flash came to be applied correctly and be invisible.
@export var flash_seconds: float = 0.22
@export var flash_color: Color = Color("d8c24a")

## Uppercase label -> the rect it occupies, in this control's local space.
## Insertion order is draw order, which is also the order the rows read in.
var _key_rects: Dictionary[String, Rect2] = {}
## Uppercase label -> the character to emit when it is tapped. Only the space
## bar differs from its own label.
var _key_chars: Dictionary[String, String] = {}
## Uppercase label -> the msec at which its flash started. Absent means unlit.
var _flash_started: Dictionary[String, int] = {}

var _dirty: bool = true
var _font: Font
var _block_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = get_theme_font(&"font", &"Button")
	if _font == null:
		_font = ThemeDB.fallback_font
	_rebuild()
	# Only ticks while something is lit; see _process.
	set_process(false)

## The size the keyboard wants to be. Callers position the control with it -
## nothing here anchors itself, because where the keyboard sits depends on
## the screen it is being put on.
func get_block_size() -> Vector2:
	if _dirty:
		_rebuild()
	return _block_size

func _rebuild() -> void:
	_dirty = false
	_key_rects.clear()
	_key_chars.clear()

	var row_widths: PackedFloat32Array = []
	for row: String in ROWS:
		row_widths.append(row.length() * key_size.x + maxf(row.length() - 1, 0) * key_gap)

	var widest: float = space_width
	for w in row_widths:
		widest = maxf(widest, w)

	var y: float = 0.0
	for r in ROWS.size():
		var x: float = roundf((widest - row_widths[r]) * 0.5)
		for letter: String in ROWS[r]:
			var label: String = letter.to_upper()
			_key_rects[label] = Rect2(Vector2(x, y), key_size)
			_key_chars[label] = letter
			x += key_size.x + key_gap
		y += key_size.y + key_gap

	_key_rects[SPACE_LABEL] = Rect2(
		Vector2(roundf((widest - space_width) * 0.5), y),
		Vector2(space_width, key_size.y))
	_key_chars[SPACE_LABEL] = " "

	_block_size = Vector2(widest, y + key_size.y)
	custom_minimum_size = _block_size
	size = _block_size

## Lights a key. Takes the label, so " " has to arrive as SPACE - the caller
## knows which it means and the two namespaces are deliberately not merged
## here, where a stray space would silently light the space bar.
func flash(label: String) -> void:
	if not _key_rects.has(label):
		return
	_flash_started[label] = Time.get_ticks_msec()
	set_process(true)
	queue_redraw()

func clear_flashes() -> void:
	_flash_started.clear()
	set_process(false)
	queue_redraw()

## Runs only while at least one key is lit, and stops itself again as soon as
## the last one has faded. A keyboard sitting idle on screen redraws never.
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var fade_ms: int = int(flash_seconds * 1000.0)
	for label in _flash_started.keys():
		if now - int(_flash_started[label]) >= fade_ms:
			_flash_started.erase(label)

	queue_redraw()
	if _flash_started.is_empty():
		set_process(false)

## How lit a key is right now, 0 to 1, on the same quadratic ease-out the
## tweened version used.
func _flash_amount(label: String) -> float:
	if not _flash_started.has(label):
		return 0.0
	if flash_seconds <= 0.0:
		return 0.0
	var elapsed: float = float(Time.get_ticks_msec() - int(_flash_started[label])) / 1000.0
	var t: float = clampf(elapsed / flash_seconds, 0.0, 1.0)
	# What is left of the flash under Tween.TRANS_QUAD/EASE_OUT, which
	# interpolates by 1-(1-t)^2 and therefore leaves (1-t)^2 of it.
	return (1.0 - t) * (1.0 - t)

func _draw() -> void:
	if _dirty:
		_rebuild()
	if _key_rects.is_empty():
		return

	# One triangle array for every cap on the keyboard. Two rounded rects per
	# key - the lip underneath and the face on top - which is what a
	# StyleBoxFlat bottom border is, and costs nothing extra here because it
	# is the same command either way.
	var points: PackedVector2Array = []
	var colors: PackedColorArray = []
	var indices: PackedInt32Array = []

	for label in _key_rects:
		var rect: Rect2 = _key_rects[label]
		var lit: float = _flash_amount(label)

		# Both the face and the edge light up, so a flash reads as the whole
		# key glowing rather than as its middle changing colour.
		#
		# The edge goes to a darkened flash colour rather than to the flash
		# colour itself, for two reasons: a lit key then has a bright core
		# inside a deeper rim, which is how a glow is shaped, and a pale
		# outline lerping straight to a saturated colour passes through a
		# washed-out tint on the way - chalk heading for red goes pink at
		# half fade, and pink is in nothing this is ever likely to theme.
		var face: Color = key_color.lerp(flash_color, lit)
		var edge_base: Color = outline_color if outline_width > 0.0 \
			else key_color.darkened(0.35)
		var edge: Color = edge_base.lerp(flash_color.darkened(EDGE_FLASH_DARKEN), lit)

		_append_round_rect(points, colors, indices, rect, corner_radius, edge)

		var face_rect: Rect2 = _face_rect(rect)
		if face_rect.size.x > 0.0 and face_rect.size.y > 0.0:
			_append_round_rect(points, colors, indices, face_rect,
				maxf(corner_radius - outline_width, 0.0), face)

	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), indices, points, colors)

	# Then every glyph, so they batch against the one font atlas instead of
	# being cut apart by the polygon command above.
	if _font == null:
		return
	var ascent: float = _font.get_ascent(font_size)
	var descent: float = _font.get_descent(font_size)
	for label in _key_rects:
		var face_rect: Rect2 = _face_rect(_key_rects[label])
		var baseline: float = face_rect.position.y \
			+ (face_rect.size.y + ascent - descent) * 0.5
		draw_string(_font, Vector2(face_rect.position.x, baseline), label,
			HORIZONTAL_ALIGNMENT_CENTER, face_rect.size.x, font_size, label_color)

## The lit part of a cap: the whole key less the outline on every side and
## the lip along the bottom. Shared so the glyph pass, which runs separately
## to keep the letters batching, cannot drift out of step with the shape it
## is centring on.
func _face_rect(rect: Rect2) -> Rect2:
	var inset := Vector2(outline_width, outline_width)
	return Rect2(rect.position + inset,
		rect.size - inset * 2.0 - Vector2(0.0, key_lip))

## Appends one rounded rectangle as a triangle fan around its centre, plus a
## one-pixel feathered skirt around the outside. Every call adds to the same
## three arrays so the whole keyboard still ends up in a single command.
##
## The skirt is what StyleBoxFlat's own corner antialiasing does and is worth
## keeping: without it the difference against the Button version is 58 hard
## pixels per key, all of them on the corners.
func _append_round_rect(points: PackedVector2Array, colors: PackedColorArray,
		indices: PackedInt32Array, rect: Rect2, radius: float,
		color: Color) -> void:
	var r: float = clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)

	var centre_index: int = points.size()
	points.append(rect.get_center())
	colors.append(color)

	# Corner centres and the angle each quarter-arc starts at, going
	# clockwise from the top-left in Godot's y-down space.
	var corners: Array[Vector2] = [
		rect.position + Vector2(r, r),
		Vector2(rect.end.x - r, rect.position.y + r),
		rect.end - Vector2(r, r),
		Vector2(rect.position.x + r, rect.end.y - r),
	]
	var starts: Array[float] = [PI, -PI * 0.5, 0.0, PI * 0.5]

	# Built once and reused for both rings, so the skirt cannot drift out of
	# step with the shape it is feathering.
	var ring: PackedVector2Array = []
	var normals: PackedVector2Array = []
	for c in 4:
		for s in CORNER_SEGMENTS + 1:
			var angle: float = starts[c] + (PI * 0.5) * (float(s) / float(CORNER_SEGMENTS))
			var normal := Vector2(cos(angle), sin(angle))
			ring.append(corners[c] + normal * r)
			normals.append(normal)

	# The skirt straddles the outline rather than hanging off it: half of it
	# inside, half outside. Hanging it entirely outside leaves the cap a
	# pixel larger than the StyleBoxFlat it replaces, whose own antialiasing
	# feathers inwards from the same edge.
	var half: float = FEATHER * 0.5
	var ring_start: int = points.size()
	for i in ring.size():
		points.append(ring[i] - normals[i] * half)
		colors.append(color)

	var ring_count: int = ring.size()
	for i in ring_count:
		indices.append(centre_index)
		indices.append(ring_start + i)
		indices.append(ring_start + (i + 1) % ring_count)

	if FEATHER <= 0.0:
		return

	# The two endpoints of a straight edge share a normal - the top edge's are
	# both (0, -1) - so pushing every ring point along its own normal offsets
	# the arcs and the flats alike.
	var skirt_start: int = points.size()
	var transparent := Color(color.r, color.g, color.b, 0.0)
	for i in ring_count:
		points.append(ring[i] + normals[i] * half)
		colors.append(transparent)

	for i in ring_count:
		var next: int = (i + 1) % ring_count
		indices.append(ring_start + i)
		indices.append(ring_start + next)
		indices.append(skirt_start + next)

		indices.append(ring_start + i)
		indices.append(skirt_start + next)
		indices.append(skirt_start + i)

## Taps in the gaps between keys are not ours. Returning false for them is
## what keeps this control from swallowing input that used to pass through
## the containers' padding.
func _has_point(point: Vector2) -> bool:
	return not _key_at(point).is_empty()

func _key_at(point: Vector2) -> String:
	for label in _key_rects:
		if (_key_rects[label] as Rect2).has_point(point):
			return label
	return ""

func _gui_input(event: InputEvent) -> void:
	var at: Vector2 = Vector2.INF

	if event is InputEventScreenTouch:
		if event.pressed:
			at = event.position
	elif event is InputEventMouseButton:
		# With emulate_mouse_from_touch on - Godot's default - every tap also
		# arrives as a mouse click with device -1. Taking both would type each
		# letter twice.
		if event.device != -1 and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			at = event.position

	if at == Vector2.INF:
		return

	var label: String = _key_at(at)
	if label.is_empty():
		return

	accept_event()
	flash(label)
	key_pressed.emit(_key_chars[label])
