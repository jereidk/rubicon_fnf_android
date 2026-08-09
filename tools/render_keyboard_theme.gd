extends SceneTree

## Renders the drawn keyboard exactly as Monochrome configures it, over the
## song's own black stage, at the size it appears in game.
##
## Deliberately built through MonochromeTypingTouchControls rather than by
## restating the palette here: a preview that carries its own copy of the
## colours stops being a preview of anything the moment one of them changes.
##
## Run with:
##   xvfb-run -a --server-args="-screen 0 1280x800x24" \
##     godot --path . --script tools/render_keyboard_theme.gd

const OUT := "user://kbd_theme"
const BOTTOM_MARGIN := 56.0
const CONTROLS_PATH := "res://lullaby_mod/songs/monochrome/scripts/monochrome_typing_touch_controls.gd"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame

	DirAccess.make_dir_recursive_absolute(OUT)

	var backdrop := ColorRect.new()
	# The stage is pure black; see the device capture.
	backdrop.color = Color.BLACK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	# Loaded by path rather than by class name: this has to stay runnable
	# while the project's UID cache is incomplete, which is exactly when a
	# global class name fails to resolve.
	var script: GDScript = load(CONTROLS_PATH)
	if script == null:
		push_error("no se pudo cargar %s" % CONTROLS_PATH)
		quit(1)
		return

	var controls: Control = script.new()
	root.add_child(controls)
	# _ready() hides itself on a machine with no touchscreen, which is every
	# machine this runs on. The keyboard is built directly below, so only the
	# hiding has to be undone.
	controls.visible = true
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	await process_frame

	controls._build_drawn_keyboard()
	var keyboard: RubiconPaintedKeyboard = controls._drawn_keyboard as RubiconPaintedKeyboard
	if keyboard == null:
		push_error("no se construyo el teclado")
		quit(1)
		return

	var block: Vector2 = keyboard.get_block_size()
	var area: Vector2 = root.get_visible_rect().size
	keyboard.position = Vector2(
		roundf((area.x - block.x) * 0.5),
		roundf(area.y - block.y - BOTTOM_MARGIN))

	print("bloque=%s  viewport=%s" % [block, area])
	print("cap=%s  outline=%s x%.1f  label=%s  flash=%s" % [
		keyboard.key_color.to_html(false), keyboard.outline_color.to_html(false),
		keyboard.outline_width, keyboard.label_color.to_html(false),
		keyboard.flash_color.to_html(false)])

	# Three keys caught at different points of the same fade, which is what
	# the eye actually sees during a word rather than one key at full red.
	keyboard.flash("H")
	await _wait(0.07)
	keyboard.flash("E")
	await _wait(0.07)
	keyboard.flash("L")

	# Two frames, no wait, so the last key is caught near full flash and the
	# capture shows the top of the fade as well as the tail of it.
	for i in 2:
		await process_frame

	print("draw=%d" % int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	root.get_texture().get_image().save_png("%s/monochrome.png" % OUT)
	quit()

## SceneTree.process_frame carries no arguments, so awaiting it yields null
## rather than a delta - accumulating that never advances and hangs.
func _wait(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
