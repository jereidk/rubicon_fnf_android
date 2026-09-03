class_name OptionBoxChoice
extends Node2D
## Choice option — faithful port of animania::states::OptionBoxChoice.
##
## Shows a label and a value that cycles through available choices.

# ─── Constants ─────────────────────────────────────────────────────────────

const FONT_SIZE := 26

# ─── Fields ───────────────────────────────────────────────────────────────

var option_name: String
var display_name: String
var cur_value: int = 0
var available_choices: Array[String] = []
var change_func: Callable
var label: Label
var value_text: Label
var _is_selected: bool = false

# ─── Init ─────────────────────────────────────────────────────────────────

func setup(p_name: String, p_display: String, p_choices: Array,
		p_default_index: int = 0, p_change: Callable = Callable()) -> void:
	option_name = p_name
	display_name = p_display
	available_choices.assign(p_choices)
	change_func = p_change

	var saved := GameOptions.get_string(p_name) if p_name in GameOptions.defaults else ""
	cur_value = p_default_index
	for i in available_choices.size():
		if available_choices[i] == saved:
			cur_value = i
			break


func _ready() -> void:
	label = Label.new()
	label.name = "Label"
	label.text = display_name
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.position = Vector2(0, -15)
	add_child(label)

	value_text = Label.new()
	value_text.name = "ValueText"
	value_text.add_theme_font_size_override("font_size", FONT_SIZE)
	value_text.position = Vector2(400, -15)
	add_child(value_text)

	_refresh()


func change_value(dir: int) -> void:
	if available_choices.is_empty():
		return
	cur_value = (cur_value + dir) % available_choices.size()
	if cur_value < 0:
		cur_value = available_choices.size() - 1
	GameOptions.set_value(option_name, available_choices[cur_value])
	_refresh()
	if change_func.is_valid():
		change_func.call(available_choices[cur_value])


func _refresh() -> void:
	if value_text and cur_value < available_choices.size():
		value_text.text = available_choices[cur_value]


func set_selected(selected: bool) -> void:
	_is_selected = selected
	if label:
		label.modulate = Color.WHITE if selected else Color(0.7, 0.7, 0.7)
	if selected:
		scale = Vector2(1.05, 1.05)
	else:
		scale = Vector2(1.0, 1.0)
