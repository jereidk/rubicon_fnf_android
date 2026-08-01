extends Button
class_name RubiconPauseIconButton

## Round black "pause" button (two white bars) for song gameplay screens,
## top-right corner. Draws the bars itself instead of relying on a font
## glyph, so the icon looks the same regardless of what font is active.
## The StyleBox background (solid black, fully round) is set here in code
## rather than per-scene theme overrides, so every song's pause button
## stays visually identical without needing to duplicate StyleBoxFlat
## resources three times.

const BAR_COLOR := Color(1, 1, 1, 0.9)
const BG_COLOR := Color(0, 0, 0, 0.55)

## Fractions of the button's own size, rather than fixed pixel values, so
## the bars stay proportional if this button is ever resized again.
@export_range(0.0, 0.5) var bar_width_ratio: float = 0.09
@export_range(0.0, 1.0) var bar_height_ratio: float = 0.34
@export_range(0.0, 0.5) var bar_gap_ratio: float = 0.12

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = ""

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.set_corner_radius_all(int(max(size.x, size.y)))
	add_theme_stylebox_override(&"normal", style)
	add_theme_stylebox_override(&"hover", style)
	add_theme_stylebox_override(&"pressed", style)
	add_theme_stylebox_override(&"focus", style)

func _draw() -> void:
	var shortest_side: float = min(size.x, size.y)
	var bar_width: float = shortest_side * bar_width_ratio
	var bar_height: float = shortest_side * bar_height_ratio
	var bar_gap: float = shortest_side * bar_gap_ratio

	var center: Vector2 = size * 0.5
	var half_gap: float = bar_gap * 0.5
	var top: float = center.y - bar_height * 0.5

	draw_rect(Rect2(center.x - half_gap - bar_width, top, bar_width, bar_height), BAR_COLOR)
	draw_rect(Rect2(center.x + half_gap, top, bar_width, bar_height), BAR_COLOR)
