extends Control
## HQ Credits — team credits with scrollable list

var cur_sel: int = 0
var can_control: bool = true

@onready var credits_label: Label = $CreditsLabel
@onready var title_label: Label = $TitleLabel
@onready var fade_rect: ColorRect = $FadeRect

var credits: Array[Dictionary] = [
	{"name": "Kixel", "role": "Lead Director, Lead Art & Animation Director"},
	{"name": "Sector", "role": "Director, Lead Program Director"},
	{"name": "Sp0re", "role": "Co-Director, Lead Music Director"},
	{"name": "chum-bot", "role": "Co-Director, Musician"},
	{"name": "GamerPablito", "role": "Programmer, Translator (ES)"},
	{"name": "RevDev", "role": "Lead Witch Aesthetic Artist, BG Artist"},
	{"name": "Torresmmo", "role": "Artist and Animator"},
	{"name": "BlackMaskly", "role": "Charter"},
	{"name": "Flootena", "role": "Charter"},
	{"name": "Fade", "role": "Charter"},
	{"name": "Akira Gotoh", "role": "Voice Actor"},
	{"name": "RetroDetro", "role": "Composer"},
	{"name": "TAU", "role": "Composer"},
	{"name": "SinnMusic", "role": "Composer"},
	{"name": "EggOverlord", "role": "Composer"},
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
		cur_sel = (cur_sel - 1 + credits.size()) % credits.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_down"):
		cur_sel = (cur_sel + 1) % credits.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_cancel"):
		_go_back()

func _update_display() -> void:
	var lines: PackedStringArray = []
	for i in credits.size():
		var c = credits[i]
		var prefix = "► " if i == cur_sel else "   "
		lines.append(prefix + c["name"] + " — " + c["role"])
	credits_label.text = "\n".join(lines)

func _go_back() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))
