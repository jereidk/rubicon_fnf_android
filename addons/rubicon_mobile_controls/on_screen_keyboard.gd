extends Control
class_name RubiconOnScreenKeyboard

## Generic on-screen QWERTY keyboard for song mechanics that read raw
## keyboard letters on desktop (e.g. Monochrome's TypingChallenge, which
## reads InputEventKey.as_text_key_label() character by character). Android
## has no physical keyboard, so this exposes the same "one letter at a time"
## interface as a row of tap targets instead. Callers connect to
## [signal key_pressed] and forward the character to whatever expects it -
## this control has no knowledge of what it's typing into.

signal key_pressed(character: String)

const ROWS: Array[String] = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

@export var key_size: Vector2 = Vector2(72, 72)
@export var key_gap: float = 6.0
@export var space_width: float = 320.0

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_keys()

func _build_keys() -> void:
	var rows_container := VBoxContainer.new()
	rows_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows_container.add_theme_constant_override("separation", key_gap)
	add_child(rows_container)

	for row: String in ROWS:
		var row_container := HBoxContainer.new()
		row_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_container.alignment = BoxContainer.ALIGNMENT_CENTER
		row_container.add_theme_constant_override("separation", key_gap)
		rows_container.add_child(row_container)

		for letter: String in row:
			row_container.add_child(_make_key(letter, key_size))

	var space_row := HBoxContainer.new()
	space_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rows_container.add_child(space_row)
	space_row.add_child(_make_key(" ", Vector2(space_width, key_size.y), "SPACE"))

func _make_key(character: String, size: Vector2, label_text: String = "") -> Button:
	var button := Button.new()
	button.text = label_text if not label_text.is_empty() else character.to_upper()
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): key_pressed.emit(character))
	return button
