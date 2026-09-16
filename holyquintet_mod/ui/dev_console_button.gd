extends Control
## Mobile-friendly stand-in for the real controls.DEV_ACCESS keybind and the
## NINE-key/Options.devMode shop shortcut (both checked in HQMainMenu.hx's
## own update()) — neither makes sense as a literal keyboard shortcut on a
## touch device with no keyboard. This is a small always-visible button
## (red keyboard glyph, black circular backing) that opens a one-line text
## field instead: type a code, submit, and known codes do what their real
## keyboard equivalent does. Not a real mod feature — a UI new to this port,
## by request, to keep those two real code paths reachable on mobile.
##
## Codes recognized (see main_menu.gd's _on_dev_code_submitted()):
##   "9"       -> real NINE-key shortcut (FlxG.switchState(new ModState("HQSHOP")))
##   "editors" -> real DEV_ACCESS (opens EditorPicker)

signal code_submitted(code: String)

const RADIUS := 32.0

var _popup: Control
var _input: LineEdit


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS, RADIUS) * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(RADIUS, RADIUS)
	draw_circle(center, RADIUS, Color(0, 0, 0, 0.75))
	draw_arc(center, RADIUS - 1.5, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 2.0)

	# A plain drawn keyboard glyph (rounded body + a few key dots/dashes) —
	# no icon asset exists for this anywhere in the mod, and this button
	# isn't a mod feature to begin with, so it's drawn rather than sourced.
	var red := Color(0.85, 0.16, 0.16, 1.0)
	var body := Rect2(center - Vector2(20.0, 13.0), Vector2(40.0, 26.0))
	draw_rect(body, red, false, 3.0)
	var key_w := 4.0
	var key_h := 4.0
	var xs := [-13.0, -6.0, 1.0, 8.0, 15.0]
	for x in xs:
		draw_rect(Rect2(center + Vector2(x - key_w * 0.5, -6.0), Vector2(key_w, key_h)), red)
	var space := Rect2(center + Vector2(-11.0, 3.0), Vector2(22.0, key_h))
	draw_rect(space, red)


func _on_gui_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if tapped:
		_open_popup()


## Closes on Escape/Android back rather than falling through to the main
## menu's own ui_cancel (switch to Title) while this popup still sits open
## on top of it. This button is a descendant of the menu scene (unlike the
## popup itself, parented straight to the tree root for the same full-rect-
## anchor reason as main_menu.gd's own root), and Godot delivers
## _unhandled_input to a descendant before an ancestor, so this alone is
## enough to beat the menu's own handling to the keypress.
func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_popup) and event.is_action_pressed("ui_cancel"):
		_close_popup()
		get_viewport().set_input_as_handled()


func _open_popup() -> void:
	if is_instance_valid(_popup):
		return

	_popup = Control.new()
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().root.add_child(_popup)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_close_popup()
	)
	_popup.add_child(backdrop)

	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.06, 0.09, 0.95)
	panel.position = Vector2(660.0, 480.0)
	panel.size = Vector2(600.0, 120.0)
	_popup.add_child(panel)

	_input = LineEdit.new()
	_input.position = panel.position + Vector2(20.0, 20.0)
	_input.size = Vector2(560.0, 40.0)
	_input.placeholder_text = "code"
	_input.add_theme_font_size_override("font_size", 24)
	_input.text_submitted.connect(func(t): _submit(t))
	_popup.add_child(_input)

	var hint := Label.new()
	hint.position = panel.position + Vector2(20.0, 70.0)
	hint.size = Vector2(560.0, 30.0)
	hint.text = "Enter a code and press Enter"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_popup.add_child(hint)

	_input.grab_focus()


func _submit(t: String) -> void:
	var code := t.strip_edges()
	_close_popup()
	if not code.is_empty():
		code_submitted.emit(code)


func _close_popup() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null
	_input = null
