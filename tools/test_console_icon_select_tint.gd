extends SceneTree

## The console's home icons have to visibly react to being the focused tab.
## Two of them did not, for two different reasons, and both were invisible
## to every other check in this repo because nothing was actually *wired*
## wrong - see _check_no_dimmed_home_icon() for the Training half.
##
## The Codes (Hacks) half:
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

	_check_selected_colour_matches_the_group(select)
	_check_size_matches_the_group(text)
	_check_no_dimmed_home_icon()

	print("console icon select tint: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

## The keyboard icon, unlike the other five, gets its colour from a flat tint
## over its own texture rather than from a gradient texture swap - so what
## reaches the screen is tint x texture, and only that product can be
## compared against the others.
##
## Measured off five device screenshots, over the pixels of each selected
## icon: Credits #fc4242, Settings #fb4747, Gallery #fa4a4a, Training
## #fd5555 - a group mean of #fc4a4a at saturation 0.70-0.74. The Codes icon
## shipped at #dc767f, saturation 0.46, which is the washed pink the report
## was about.
##
## A hue-ratio check alone let that through: 1.1/0.6 is 1.83, comfortably
## over the 1.25 floor above, while still being visibly the wrong colour.
## Saturation is what actually separates them.
const GROUP_SELECTED := Color(0.988, 0.291, 0.291)
const KEYBOARD_TEXTURE := "res://lullaby_mod/assets/menus/keyboard_icon_hacks_button.png"

func _check_selected_colour_matches_the_group(select: Color) -> void:
	var mean: Color = _mean_opaque(KEYBOARD_TEXTURE)
	if mean.a < 0.0:
		_check(false, "the keyboard texture is readable")
		return

	var lit := Color(select.r * mean.r, select.g * mean.g, select.b * mean.b)
	_check(absf(lit.s - GROUP_SELECTED.s) <= 0.12,
		"the selected Codes icon is as saturated as the others (%.2f against %.2f)"
			% [lit.s, GROUP_SELECTED.s])

	var distance: float = Vector3(lit.r - GROUP_SELECTED.r, lit.g - GROUP_SELECTED.g,
		lit.b - GROUP_SELECTED.b).length()
	_check(distance <= 0.12,
		"...and lands on the group's measured red (got #%s, want #%s, distance %.3f)"
			% [lit.to_html(false), GROUP_SELECTED.to_html(false), distance])

## Mean colour of the texture's opaque pixels. Read raw rather than through
## the importer so this works whatever compression the texture is on.
func _mean_opaque(path: String) -> Color:
	var image: Image = Image.load_from_file(path)
	if image == null:
		return Color(0, 0, 0, -1.0)

	var total := Vector3.ZERO
	var count: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.8:
				continue
			total += Vector3(pixel.r, pixel.g, pixel.b)
			count += 1
	if count == 0:
		return Color(0, 0, 0, -1.0)
	total /= float(count)
	return Color(total.x, total.y, total.z, 1.0)

## And the size, which is the other half of the same report.
##
## The keyboard is a flat QuadMesh while the other five are ui_*.gltf models,
## so their node scales are not comparable - what is comparable is how wide
## the thing lands on screen. Measured on the device at scale 0.881: 223px
## wide against 92-100 for every other icon, on icons 109-116 tall. It
## overflowed the 419px select bubble and sat on its own label.
##
## Screen width is linear in the node scale, so the check is on the world
## width the quad ends up with. 1.2 x 0.446 = 0.535 units lands it at ~113px,
## which is the group's median longest dimension.
##
## An earlier pass set 0.881 by matching the ALPHA BOUNDING BOX of an
## isolated render against the other icons' - and that render had the
## ui_*.gltf materials failing to load, so those boxes were the untextured
## geometry rather than the drawn icon. The lesson is in CLAUDE.md: a missing
## texture does invalidate a size measurement, whatever a note here used to
## say.
const QUAD_WIDTH := 1.2
const MIN_WORLD_WIDTH := 0.42
const MAX_WORLD_WIDTH := 0.66

func _check_size_matches_the_group(text: String) -> void:
	var scale: float = _hacks_scale(text)
	_check(scale > 0.0, "ui_hacks declares a uniform scale")
	if scale <= 0.0:
		return

	var world: float = QUAD_WIDTH * scale
	_check(world >= MIN_WORLD_WIDTH and world <= MAX_WORLD_WIDTH,
		"the Codes icon is the same size class as the other five (%.3f units wide, want %.2f-%.2f)"
			% [world, MIN_WORLD_WIDTH, MAX_WORLD_WIDTH])

func _hacks_scale(text: String) -> float:
	var head: int = text.find("[node name=\"ui_hacks\"")
	if head < 0:
		return -1.0
	var at: int = text.find("transform = Transform3D(", head)
	if at < 0:
		return -1.0
	at += "transform = Transform3D(".length()
	var parts: PackedStringArray = text.substr(at, text.find(")", at) - at).split(",")
	return float(parts[0]) if parts.size() >= 12 else -1.0

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

## The second half of the same bug class, found the same day: Training's
## home icon looked permanently locked.
##
## Nothing was wrong with that button either - disabled = false, the same
## script, the same two gradient materials as Settings and Credits. The
## shop scene was overriding its mesh:
##
##     [node name="TRAINING" parent=".../ui_training/UI_Icons/Skeleton3D"]
##     material_override = ExtResource("189")   # mat_console_inactive.tres
##
## material_override beats surface_set_material(), which is what
## ConsoleHomeButton uses on focus - so that icon could never respond to
## anything. It was a leftover: lullaby_training.gd's own header records
## that the tab shipped "behind a Home icon shipping disabled = true", and
## when the feature was implemented the flag was flipped but the grey
## override was not removed. Functionally unlocked, visually still locked.
##
## Pinned as a shape rather than as one node name: no icon inside the
## console's IconSubViewport may carry a material_override at all. Every
## one of them is driven by the focus swap, and an override silently wins
## over it.
func _check_no_dimmed_home_icon() -> void:
	const SHOP_PATH := "res://lullaby_mod/rooms/env_collector_shop.tscn"
	var shop: String = FileAccess.get_file_as_string(SHOP_PATH)
	if shop.is_empty():
		_check(false, "env_collector_shop.tscn is readable")
		return

	var offenders: PackedStringArray = []
	var node_name: String = ""
	var inside_icons: bool = false
	for line: String in shop.split("\n"):
		if line.begins_with("[node "):
			inside_icons = line.contains("IconSubViewport")
			node_name = ""
			var at: int = line.find("name=\"")
			if at >= 0:
				at += 6
				node_name = line.substr(at, line.find("\"", at) - at)
		elif inside_icons and line.begins_with("material_override = "):
			offenders.append(node_name)

	_check(offenders.is_empty(),
		"no console home icon is pinned to a fixed material (offenders: %s)"
			% ("none" if offenders.is_empty() else ", ".join(offenders)))

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
