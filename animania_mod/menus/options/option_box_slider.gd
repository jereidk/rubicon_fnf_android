class_name OptionBoxSlider
extends Node2D
## Slider option — faithful port of animania::states::OptionBoxSlider.
##
## Shows a label with the current value and handles left/right to change it.

# ─── Constants ─────────────────────────────────────────────────────────────

const FONT_SIZE := 26

# ─── Fields ───────────────────────────────────────────────────────────────

var option_name: String
var display_name: String
var cur_value: float = 0.0
var min_value: float = 0.0
var max_value: float = 1.0
var step_value: float = 0.05
var step_hold_mult: float = 1.0
var change_func: Callable
var label: Label
var value_label: Label
var scroll_bg: ColorRect
var scroll_line: ColorRect
var scroll_head: ColorRect
var _is_selected: bool = false
var _allow_change_sound: bool = true

# ─── Init ─────────────────────────────────────────────────────────────────

func setup(p_name: String, p_display: String, p_min: float, p_max: float,
		p_step: float, p_default: float, p_change: Callable = Callable()) -> void:
	option_name = p_name
	display_name = p_display
	min_value = p_min
	max_value = p_max
	step_value = p_step
	change_func = p_change
	cur_value = GameOptions.get_float(p_name) if p_name in GameOptions.defaults else p_default
	cur_value = clampf(cur_value, min_value, max_value)


func _ready() -> void:
	# Label
	label = Label.new()
	label.name = "Label"
	label.text = display_name
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.position = Vector2(0, -15)
	add_child(label)

	# Value display
	value_label = Label.new()
	value_label.name = "ValueLabel"
	value_label.add_theme_font_size_override("font_size", FONT_SIZE)
	value_label.position = Vector2(400, -15)
	add_child(value_label)

	# Scroll bar background
	scroll_bg = ColorRect.new()
	scroll_bg.name = "ScrollBg"
	scroll_bg.position = Vector2(350, -3)
	scroll_bg.size = Vector2(200, 6)
	scroll_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	add_child(scroll_bg)

	# Scroll line (filled portion)
	scroll_line = ColorRect.new()
	scroll_line.name = "ScrollLine"
	scroll_line.position = Vector2(350, -3)
	scroll_line.color = Color(1.0, 1.0, 1.0, 0.9)
	add_child(scroll_line)

	# Scroll head (indicator)
	scroll_head = ColorRect.new()
	scroll_head.name = "ScrollHead"
	scroll_head.position = Vector2(350, -6)
	scroll_head.size = Vector2(8, 12)
	scroll_head.color = Color.WHITE
	add_child(scroll_head)

	_refresh()


# ─── Change value ─────────────────────────────────────────────────────────

func change_value(dir: int) -> void:
	var new_val := cur_value + (step_value * dir * step_hold_mult)
	cur_value = clampf(new_val, min_value, max_value)
	GameOptions.set_value(option_name, cur_value)
	_refresh()
	if change_func.is_valid():
		change_func.call(cur_value)


func _refresh() -> void:
	if value_label:
		if max_value <= 1.0 and min_value >= 0.0:
			value_label.text = "%d%%" % int(cur_value * 100)
		else:
			value_label.text = str(int(cur_value))

	if scroll_line and scroll_head:
		var range_size := max_value - min_value
		var percent := 0.0
		if range_size > 0:
			percent = (cur_value - min_value) / range_size
		scroll_line.size.x = percent * 200
		scroll_head.position.x = 350 + percent * 200 - 4


# ─── Selection ────────────────────────────────────────────────────────────

func set_selected(selected: bool) -> void:
	_is_selected = selected
	if label:
		label.modulate = Color.WHITE if selected else Color(0.7, 0.7, 0.7)
	if selected:
		scale = Vector2(1.05, 1.05)
	else:
		scale = Vector2(1.0, 1.0)
