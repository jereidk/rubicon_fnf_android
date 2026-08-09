extends "res://addons/rubicon_mobile_controls/action_button.gd"
class_name LullabyMechanicActionButton

## Round red "special mechanic" button used by the Touch gameplay mode.
## Safety Lullaby's pendulum (and anything else bound to the same action)
## is normally played through the big full-width RubiconMechanicHitbox,
## which the Touch overlay has to hide - a full-width red zone would sit
## on top of the notes and swallow their taps. This replaces it with a
## compact round button in the same family as the pause button
## (RubiconPauseIconButton): same self-drawn style, same round StyleBox
## set in code, same FOCUS_NONE + press/release dispatch as
## RubiconActionButton, just red and bound to `action` (lullaby_special by
## default - set it like any other export).

const BG_COLOR := Color(0.78, 0.06, 0.06, 0.62)
const PRESSED_BG_COLOR := Color(0.95, 0.2, 0.2, 0.78)
const GLYPH_COLOR := Color(1, 1, 1, 0.92)

func _ready() -> void:
	# RubiconActionButton._ready() sets FOCUS_NONE and wires the
	# press+release dispatch (and the flash on button_down).
	# The glyph below already says what this button is for, so it takes the
	# key line only - a verb printed over the pendulum would just cover it.
	show_binding = true
	super()
	text = ""

	var normal := StyleBoxFlat.new()
	normal.bg_color = BG_COLOR
	# Larger than any real button; StyleBoxFlat clamps the radius to the
	# button's own shortest side, so this is "always fully round" without
	# depending on size being laid out yet (which _ready() does not
	# guarantee for a runtime-created, anchor-positioned button).
	normal.set_corner_radius_all(1000)
	add_theme_stylebox_override(&"normal", normal)
	add_theme_stylebox_override(&"hover", normal)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = PRESSED_BG_COLOR
	pressed.set_corner_radius_all(1000)
	add_theme_stylebox_override(&"pressed", pressed)
	add_theme_stylebox_override(&"focus", pressed)

func _draw() -> void:
	# A small pendulum glyph (pivot dot, arm, bob) so the button reads as
	# the pendulum mechanic without needing a texture. Sizes are fractions
	# of the button's shortest side so it scales with the control.
	var shortest: float = min(size.x, size.y)
	if shortest <= 0.0:
		return

	var center := size * 0.5
	var pivot := Vector2(center.x, center.y - shortest * 0.16)
	var bob := Vector2(center.x + shortest * 0.2, center.y + shortest * 0.24)
	var bob_radius: float = shortest * 0.14
	var arm_end: Vector2 = bob - (bob - pivot).normalized() * bob_radius

	draw_circle(pivot, shortest * 0.05, GLYPH_COLOR)
	draw_line(pivot, arm_end, GLYPH_COLOR, maxf(shortest * 0.045, 2.0))
	draw_circle(bob, bob_radius, GLYPH_COLOR)
