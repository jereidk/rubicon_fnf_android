extends SceneTree

## A/B for the drawn keyboard: renders the old Button-based
## RubiconOnScreenKeyboard and the new painted RubiconPaintedKeyboard under
## the same conditions and reports what each costs in draw calls, plus a PNG
## of each so the layout can be compared by eye rather than by assertion.
##
## Run with:
##   xvfb-run -a --server-args="-screen 0 1280x800x24" \
##     godot --path . --script tools/render_keyboard_ab.gd
##
## RENDER_TOTAL_DRAW_CALLS_IN_FRAME is a count, not a duration. The number
## that matters is the difference between the two, not either on its own.

const OUT_DIR := "user://kbd_ab"
const KEY_SIZE := Vector2(96, 96)
const KEY_GAP := 10.0
const SPACE_WIDTH := 460.0
const KEY_COLOR := Color("2f2f36")
const LABEL_COLOR := Color("e8e8ee")
const FONT_SIZE := 34
const FLASH_COLOR := Color("d8c24a")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Autoloads are not compile-time identifiers this early, and the first
	# frame has not been drawn yet either.
	await process_frame
	await process_frame

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("touchscreen=", DisplayServer.is_touchscreen_available(),
		" viewport=", root.get_visible_rect().size)

	var baseline: int = await _measure("baseline", null)
	var old_calls: int = await _measure("old_buttons", _make_old())
	var new_calls: int = await _measure("new_painted", _make_new())

	print("")
	print("empty viewport      draw=%d" % baseline)
	print("Button keyboard     draw=%d  (+%d)" % [old_calls, old_calls - baseline])
	print("painted keyboard    draw=%d  (+%d)" % [new_calls, new_calls - baseline])
	quit()

func _make_old() -> Control:
	var kbd := RubiconOnScreenKeyboard.new()
	kbd.key_size = KEY_SIZE
	kbd.key_gap = KEY_GAP
	kbd.space_width = SPACE_WIDTH
	return kbd

func _make_new() -> Control:
	var kbd := RubiconPaintedKeyboard.new()
	kbd.key_size = KEY_SIZE
	kbd.key_gap = KEY_GAP
	kbd.space_width = SPACE_WIDTH
	kbd.key_color = KEY_COLOR
	kbd.label_color = LABEL_COLOR
	kbd.font_size = FONT_SIZE
	kbd.flash_color = FLASH_COLOR
	return kbd

## Styles the old keyboard's buttons exactly the way the shipped Monochrome
## script did, so the comparison is against what was really on screen and not
## against Godot's bare default theme.
func _style_old(kbd: Control) -> void:
	for button in _find_buttons(kbd):
		var box := StyleBoxFlat.new()
		box.bg_color = KEY_COLOR
		box.set_corner_radius_all(10)
		box.border_width_bottom = 4
		box.border_color = KEY_COLOR.darkened(0.35)
		button.add_theme_stylebox_override("normal", box)
		button.add_theme_stylebox_override("hover", box)
		button.add_theme_stylebox_override("pressed", box)
		button.add_theme_stylebox_override("disabled", box)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.add_theme_color_override("font_color", LABEL_COLOR)
		button.add_theme_font_size_override("font_size", FONT_SIZE)

func _find_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		var button := child as Button
		if button != null:
			out.append(button)
		out.append_array(_find_buttons(child))
	return out

func _measure(label: String, keyboard: Control) -> int:
	var backdrop := ColorRect.new()
	backdrop.color = Color("101014")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	if keyboard != null:
		root.add_child(keyboard)
		await process_frame

		if keyboard is RubiconOnScreenKeyboard:
			# It refuses to build its keys without a touchscreen, and this
			# desktop run has none. Forced here rather than by turning on
			# touch emulation project-wide, which would change what the other
			# half of the comparison sees too.
			if keyboard.get_child_count() == 0:
				keyboard.visible = true
				keyboard._build_keys()
				await process_frame

			_style_old(keyboard)
			var rows: Control = keyboard.get_child(0) as Control
			var wanted: Vector2 = rows.get_combined_minimum_size()
			rows.size = wanted
			rows.position = Vector2.ZERO
			keyboard.size = wanted
		else:
			# One lit key, so the flash path is exercised in the capture too.
			keyboard.flash("H")

		var block: Vector2 = keyboard.size
		var area: Vector2 = root.get_visible_rect().size
		keyboard.position = Vector2(
			roundf((area.x - block.x) * 0.5), roundf(area.y - block.y - 56.0))

	# Several frames: the draw-call counter reports the frame just rendered,
	# and containers need a layout pass before they report a real size.
	for i in 6:
		await process_frame

	var calls: int = int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, label])
	print("%-14s draw=%d prims=%d" % [label, calls,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])

	backdrop.queue_free()
	if keyboard != null:
		keyboard.queue_free()
	await process_frame
	return calls
