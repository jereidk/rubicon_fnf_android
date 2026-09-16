extends Control
## Ports funkin.editors.EditorPicker (real controls.DEV_ACCESS keybind — see
## dev_console_button.gd for how this port reaches it on mobile instead).
## Real options: Chart/Character/Stage/Alphabet Editor + Wiki (a "UI Debug
## State" 6th entry is #if debug-only in the real source, skipped here too).
##
## Simplified from the real version: real EditorPickerOption tracks the
## mouse continuously (curSelected follows cursor Y, not a discrete list
## cursor), slides each row's icon off-screen to the left when unselected
## and only back into view on selection, gives it a slow idle rotation
## wobble, and parallax-scrolls unselected rows via scrollFactor as you
## move through the list — all real, but a lot of bespoke motion to spend
## on a hidden dev menu nobody but the developer sees. This is a plain
## always-visible icon+label list with a selection highlight, discrete
## up/down (or tap) navigation, and the same real confirm flicker — same
## entry point and destinations, less choreography.
##
## Only Wiki actually goes anywhere (OS.shell_open, matching real
## CoolUtil.openURL(Flags.URL_WIKI)). Chart/Character/Stage/Alphabet Editor
## are each entire standalone editor applications in the real engine —
## genuinely out of scope for this menu port — so confirming one plays the
## real flicker+SFX, then logs a stub warning instead of opening anything.

signal closed

const OPTIONS := [
	{"id": "chart", "name": "Chart Editor"},
	{"id": "character", "name": "Character Editor"},
	{"id": "stage", "name": "Stage Editor"},
	{"id": "alphabet", "name": "Alphabet Editor"},
	{"id": "wiki", "name": "Wiki"},
]
const WIKI_URL := "https://codename-engine.com/"

const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

var _cur_sel: int = 0
var _rows: Array = []
var _confirmed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var row_h := 1080.0 / OPTIONS.size()
	for i in OPTIONS.size():
		var row := _build_row(OPTIONS[i], i, row_h)
		add_child(row)
		_rows.append(row)

	_refresh_selection()


func _build_row(option: Dictionary, index: int, row_h: float) -> Control:
	var row := Control.new()
	row.position = Vector2(0.0, index * row_h)
	row.size = Vector2(1920.0, row_h)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_gui_input.bind(index))

	var highlight := ColorRect.new()
	highlight.name = "Highlight"
	highlight.color = Color(1, 1, 1, 0.12)
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.visible = false
	row.add_child(highlight)

	var icon_path := "res://holyquintet_mod/source/images/editors/icons/%s.png" % option["id"]
	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.position = Vector2(25.0, (row_h - 110.0) * 0.5)
		icon.size = Vector2(110.0, 110.0)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(25.0 + 110.0 + 25.0, 0.0)
	label.size = Vector2(1600.0, row_h)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0.0509804, 0.0352941, 0.0509804, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.text = option["name"]
	row.add_child(label)

	return row


func _refresh_selection() -> void:
	for i in _rows.size():
		var selected := i == _cur_sel
		var label: Label = _rows[i].get_node("Label")
		label.add_theme_color_override("font_color", Color.WHITE if selected else Color(0.7, 0.7, 0.7))
		_rows[i].get_node("Highlight").visible = selected


func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if _confirmed:
		return
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if not tapped:
		return
	if index == _cur_sel:
		_confirm()
	else:
		_cur_sel = index
		GenUtil.play_ui_sound(self, "move")
		_refresh_selection()


## Real: this is a Flixel substate (openSubState()), which fully owns input
## while active — the parent HQMainMenu's own update() simply doesn't run
## underneath it, so a keypress that closes the substate can't also reach
## the parent's own update() that same frame. This Control is a plain child
## in the same tree instead (see main_menu.gd's _on_dev_code_submitted()),
## and Godot delivers _unhandled_input to a child *before* its parent, so
## without set_input_as_handled() the same ui_cancel keypress that closes
## this picker would then keep propagating into HQMainMenu's own
## _unhandled_input() right after — confirmed directly: Escape correctly
## closed the picker, then (in that same frame, with _can_control already
## true again) also triggered the menu's own ui_cancel case, switching to
## the Title screen. Calling this on every branch here reproduces the real
## "substate owns the whole input event" behavior.
func _unhandled_input(event: InputEvent) -> void:
	if _confirmed:
		return
	if event.is_action_pressed("ui_up"):
		_cur_sel = wrapi(_cur_sel - 1, 0, OPTIONS.size())
		GenUtil.play_ui_sound(self, "move")
		_refresh_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_cur_sel = wrapi(_cur_sel + 1, 0, OPTIONS.size())
		GenUtil.play_ui_sound(self, "move")
		_refresh_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


## Real: CoolUtil.playMenuSFX(CONFIRM) then sprites[curSelected].flicker(...)
## then a real camera fade before switching state. Ported as the same
## flicker + SFX; the destination is either a real URL (Wiki) or a
## documented stub (the four real editors, out of scope here).
func _confirm() -> void:
	_confirmed = true
	GenUtil.play_ui_sound(self, "confirm")

	var label: Label = _rows[_cur_sel].get_node("Label")
	var flicker_tw := create_tween()
	for i in 6:
		flicker_tw.tween_property(label, "visible", i % 2 == 0, 0.0)
		flicker_tw.tween_interval(0.06)
	flicker_tw.tween_callback(func():
		label.visible = true
		_on_option_confirmed()
	)


func _on_option_confirmed() -> void:
	var option: Dictionary = OPTIONS[_cur_sel]
	if option["id"] == "wiki":
		OS.shell_open(WIKI_URL)
		_confirmed = false
	else:
		push_warning("EditorPicker: %s reached — not built in this port (a full standalone engine editor, out of scope for this menu)." % option["name"])
		_confirmed = false


func _close() -> void:
	closed.emit()
	queue_free()
