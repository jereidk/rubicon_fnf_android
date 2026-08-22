extends SceneTree

## The Codes (Hacks) home icon has to visibly change colour when it is the
## focused tab, like every other icon on that screen does.
##
## It did not, and the reason is the kind a screenshot catches and a test
## normally does not: the button was wired correctly - same script, same
## exports, a real MeshInstance3D - and it *did* swap materials on focus.
## The two materials just looked the same. Every other icon swaps between
## mat_console_idle.tres and mat_console_select.tres, which are two DIFFERENT
## gradient textures (grey-beige vs a white-to-red ramp). The keyboard icon
## is a flat quad with its own texture, so it cannot use those; its select
## material was the same texture at albedo_color 1.3 - a 30% brightness
## bump, no hue shift at all.
##
## Measured from the two real gradients, the select/idle shift the other
## icons undergo is roughly (1.1, 0.6, 0.66) over the red half of the ramp -
## red held, green and blue pulled down. That is what the keyboard's select
## albedo_color now reproduces.
##
## What this pins is the property that was broken: idle and select must
## differ by a real hue shift, not merely by brightness. A future edit that
## resets one of them to a neutral tint fails here instead of shipping an
## icon that looks dead when selected.
##
## Run with:
##   godot --headless --path . --script tools/test_console_icon_select_tint.gd

const SCENE_PATH := "res://lullaby_mod/resources/console/console.tscn"

## How much redder-than-neutral the select tint has to be. The measured
## shift is red/green = 1.1/0.6 = 1.83; anything at or below 1.0 is a pure
## brightness change, which is exactly the bug.
const MIN_RED_BIAS := 1.25

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	var text: String = FileAccess.get_file_as_string(SCENE_PATH)
	_check(not text.is_empty(), "console.tscn is readable")

	var idle: Color = _albedo_of(text, "StandardMaterial3D_hacks_idle")
	var select: Color = _albedo_of(text, "StandardMaterial3D_hacks_select")

	# An absent albedo_color line means Godot's default white, which is the
	# correct idle for this icon (it shows its own texture untinted).
	_check(_is_neutral(idle), "the Codes icon's idle tint stays neutral (got %s)" % idle)

	_check(select != idle, "idle and select tints differ at all (both %s)" % select)

	var red_bias: float = select.r / maxf(maxf(select.g, select.b), 0.0001)
	_check(red_bias >= MIN_RED_BIAS,
		"select tint is a real hue shift toward red, not just brightness (r/max(g,b) = %.2f, need >= %.2f)"
			% [red_bias, MIN_RED_BIAS])

	# The shared materials the other icons use must stay two distinct
	# resources - if someone ever points both at the same .tres, every icon
	# develops the bug this test exists for.
	_check(text.contains("mat_console_idle.tres") and text.contains("mat_console_select.tres"),
		"the other icons still reference both gradient materials")

	print("console icon select tint: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

## albedo_color of a named sub_resource, or white when the line is absent
## (Godot's default).
func _albedo_of(text: String, id: String) -> Color:
	var head: int = text.find("[sub_resource type=\"StandardMaterial3D\" id=\"%s\"]" % id)
	if head < 0:
		_check(false, "sub_resource %s exists" % id)
		return Color.WHITE
	var tail: int = text.find("[", head + 1)
	var block: String = text.substr(head, tail - head if tail > head else -1)

	var line_start: int = block.find("albedo_color = Color(")
	if line_start < 0:
		return Color.WHITE
	line_start += "albedo_color = Color(".length()
	var line_end: int = block.find(")", line_start)
	var parts: PackedStringArray = block.substr(line_start, line_end - line_start).split(",")
	if parts.size() < 3:
		_check(false, "albedo_color of %s parses" % id)
		return Color.WHITE
	return Color(float(parts[0]), float(parts[1]), float(parts[2]))

func _is_neutral(c: Color) -> bool:
	return absf(c.r - c.g) < 0.05 and absf(c.g - c.b) < 0.05

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
