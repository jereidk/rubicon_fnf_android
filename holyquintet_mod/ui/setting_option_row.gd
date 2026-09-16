extends Control
## Referenced via preload() in settings_screen.gd, not class_name: the
## global script class cache only updates after the editor rescans the
## project, which headless test runs don't trigger, causing "Could not
## find type" false negatives (same reasoning as gen_util.gd's own header).
## Ports ui/SettingOptionUI.hx. One real row in a Settings category list:
## a background strip (optionback.png), a name label, and (except for
## separators) a right-aligned value label — ON/OFF, a number, a bound key
## name, "Selected"/"" for a language, or nothing for the delete-data entry.
##
## option_Desc in the real class is built, formatted, and then immediately
## overwritten to '' (`option_Desc.text = '';` right after the constructor's
## own switch) for every single option — data.descriptionKey is real data
## ('Placeholder Text' on almost every entry) that never actually reaches
## the screen. Not ported at all: there's nothing to verify a rendered
## description against, since the real game never shows one either.

const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

## action: "select" (tap while not the current selection — just moves the
## cursor here, matching Up/Down), "confirm" (tap while already selected —
## matches Enter: toggles bool/language, opens the control rebind or
## delete-data flow), "dec"/"inc" (tap the left/right quarter of an
## already-selected int/float row — mobile stand-in for real Left/Right,
## which has no touch equivalent otherwise).
signal activated(action: String)

var data: Dictionary
var selected: bool = false:
	set(v):
		selected = v
		_refresh_colors()
var active: bool = false:
	set(v):
		active = v
		_refresh_alpha()

var bg: TextureRect
var name_label: Label
var value_label: Label
var flag_icon: TextureRect


func setup(row_data: Dictionary) -> void:
	data = row_data
	size = Vector2(1154.0, 114.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	bg = TextureRect.new()
	bg.texture = load("res://holyquintet_mod/source/images/ui/settings/optionback.png")
	# A plain (non-Container) TextureRect doesn't size itself from its own
	# texture — without this it silently stays (0,0) and never draws at all,
	# same class of bug already hit once elsewhere in this port.
	bg.size = Vector2(1154.0, 114.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var name_x := 65.0
	if data.get("type") == "language":
		flag_icon = TextureRect.new()
		flag_icon.texture = load("res://holyquintet_mod/source/images/ui/settings/%s.png" % data["name"].to_lower())
		flag_icon.size = Vector2(300.0, 156.0)
		flag_icon.position = Vector2(-18.75, -18.75)
		flag_icon.scale = Vector2(0.75, 0.75)
		flag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flag_icon)
		name_x += 150.0

	name_label = Label.new()
	name_label.position = Vector2(name_x, 31.0)
	name_label.size = Vector2(1154.0 - name_x, 50.0)
	name_label.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
	name_label.add_theme_font_size_override("font_size", 42)
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.add_theme_color_override("font_outline_color", Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = "" if data.get("type") == "separator" else data.get("name", "")
	add_child(name_label)

	value_label = Label.new()
	value_label.position = Vector2(65.0, 46.0)
	value_label.size = Vector2(1154.0 - 150.0 - 65.0, 40.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_override("font", load("res://holyquintet_mod/source/fonts/shingo.otf"))
	value_label.add_theme_font_size_override("font_size", 42)
	value_label.add_theme_constant_override("outline_size", 4)
	value_label.add_theme_color_override("font_outline_color", Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 1.0))
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(value_label)

	refresh_value()
	_refresh_colors()
	_refresh_alpha()


func refresh_value() -> void:
	if data.get("type") == "separator" or data.get("type") == "delete_data":
		value_label.text = ""
		return
	value_label.text = format_cur_option()


## Ports formatCurOption(). Reads HQOptions[data.parent_value] the same way
## the real one reads Reflect.field(Options, data.parentValue) — Godot's
## Object.get() is the same kind of by-name reflection Haxe's Reflect is.
## Never called for separator/delete_data rows (refresh_value() above
## short-circuits both — neither has a real parent_value to read).
func format_cur_option() -> String:
	var current = HQOptions.get(data.get("parent_value", ""))
	var text := ""
	match data.get("type"):
		"bool":
			text = "On" if current else "Off"
		"int", "float":
			text = str(current)
		"language":
			text = "Selected" if current == data.get("value") else ""
		"control":
			text = str(current)
	if data.get("suffix"):
		text += data["suffix"]
	return text


func _refresh_colors() -> void:
	if not is_instance_valid(bg):
		return
	var is_destroy: bool = data.get("name", "") == "Destroy Save Data"
	if selected:
		bg.modulate = Color.WHITE
		name_label.add_theme_color_override("font_color", Color.RED if is_destroy else Color.WHITE)
		value_label.add_theme_color_override("font_color", Color.WHITE)
		if is_instance_valid(flag_icon):
			flag_icon.modulate = Color.WHITE
	else:
		bg.modulate = Color.BLACK
		name_label.add_theme_color_override("font_color", Color(0.35, 0.0, 0.0) if is_destroy else Color(0.5, 0.5, 0.5))
		value_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		if is_instance_valid(flag_icon):
			flag_icon.modulate = Color(0.5, 0.5, 0.5)


func _refresh_alpha() -> void:
	if not is_instance_valid(bg):
		return
	var a := 1.0 if active else 0.5
	bg.modulate.a = a
	name_label.modulate.a = a
	value_label.modulate.a = a
	if is_instance_valid(flag_icon):
		flag_icon.modulate.a = a


func _on_gui_input(event: InputEvent) -> void:
	if data.get("type") == "separator" or not active:
		return
	var tapped := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		pos = event.position
	elif event is InputEventScreenTouch:
		tapped = event.pressed
		pos = event.position
	if not tapped:
		return

	if not selected:
		activated.emit("select")
		return

	var type: String = data.get("type", "")
	if type == "int" or type == "float":
		if pos.x < size.x * 0.25:
			activated.emit("dec")
			return
		elif pos.x > size.x * 0.75:
			activated.emit("inc")
			return
	activated.emit("confirm")
