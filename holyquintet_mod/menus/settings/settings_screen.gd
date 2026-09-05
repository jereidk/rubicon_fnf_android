extends Control
## HQ Settings — gameplay, visuals, controls options

var cur_sel: int = 0
var can_control: bool = true

@onready var options_label: Label = $OptionsLabel
@onready var value_label: Label = $ValueLabel
@onready var title_label: Label = $TitleLabel
@onready var fade_rect: ColorRect = $FadeRect

var options: Array[Dictionary] = [
	{"name": "Downscroll", "key": "downscroll", "type": "bool", "default": false},
	{"name": "Flashing Lights", "key": "flashing", "type": "bool", "default": true},
	{"name": "Ghost Tapping", "key": "ghost_tapping", "type": "bool", "default": true},
	{"name": "Botplay", "key": "botplay", "type": "bool", "default": false},
	{"name": "Middlescroll", "key": "middlescroll", "type": "bool", "default": false},
]

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN_OUT)
	_update_display()

func _process(_delta: float) -> void:
	if not can_control:
		return
	if Input.is_action_just_pressed("ui_up"):
		cur_sel = (cur_sel - 1 + options.size()) % options.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_down"):
		cur_sel = (cur_sel + 1) % options.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_accept"):
		_toggle_option()
	elif Input.is_action_just_pressed("ui_cancel"):
		_go_back()

func _update_display() -> void:
	var lines: PackedStringArray = []
	for i in options.size():
		var opt = options[i]
		var prefix = "► " if i == cur_sel else "   "
		var val = "ON" if ProjectSettings.get_setting("application/run/" + opt["key"], opt["default"]) else "OFF"
		lines.append(prefix + opt["name"])
	options_label.text = "\n".join(lines)
	var current = options[cur_sel]
	var val_str = "ON" if ProjectSettings.get_setting("application/run/" + current["key"], current["default"]) else "OFF"
	value_label.text = val_str

func _toggle_option() -> void:
	var opt = options[cur_sel]
	var key = "application/run/" + opt["key"]
	var current = ProjectSettings.get_setting(key, opt["default"])
	ProjectSettings.set_setting(key, not current)
	_update_display()

func _go_back() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))
