extends Control
## HQ Freeplay — song selection with portrait backgrounds per song.

var song_list: Array[Dictionary] = [
	{"name": "initium",      "display": "Initium",       "portrait": "madoka",  "bg": "initium",      "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "resonance",    "display": "Resonance",     "portrait": "sayaka",  "bg": "resonance",    "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "eternalstar",  "display": "Eternal Star",  "portrait": "madoka",  "bg": "eternalstar",  "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "vexation",     "display": "Vexation",      "portrait": "kyoko",   "bg": "vexation",     "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "partea",       "display": "Partea",        "portrait": "mami",    "bg": "Partea",       "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "out-of-time",  "display": "Out-of-Time",   "portrait": "homura",  "bg": "out-of-time",  "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "meguca",       "display": "Meguca",        "portrait": "madoka",  "bg": "meguca",       "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "reconnect",    "display": "Reconnect",     "portrait": "mami",    "bg": "reconnect",    "week": 1, "difficulties": ["easy", "hard"]},
	{"name": "stardom",      "display": "Stardom",       "portrait": "madoka",  "bg": "stardom",      "week": 1, "difficulties": ["easy", "hard"]},
]

var cur_sel: int = 0
var cur_diff: int = 1  # 0=easy, 1=hard
var can_control: bool = true

@onready var bg_tex: TextureRect = $BG
@onready var portrait_tex: TextureRect = $Portrait
@onready var song_label: Label = $SongLabel
@onready var diff_label: Label = $DiffLabel
@onready var fade_rect: ColorRect = $FadeRect

var diff_names: Array[String] = ["easy", "hard"]

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN_OUT)
	_update_display()

func _process(_delta: float) -> void:
	if not can_control:
		return
	if Input.is_action_just_pressed("ui_up"):
		cur_sel = (cur_sel - 1 + song_list.size()) % song_list.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_down"):
		cur_sel = (cur_sel + 1) % song_list.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_left"):
		cur_diff = (cur_diff - 1 + diff_names.size()) % diff_names.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_right"):
		cur_diff = (cur_diff + 1) % diff_names.size()
		_update_display()
	elif Input.is_action_just_pressed("ui_accept"):
		_play_song()
	elif Input.is_action_just_pressed("ui_cancel"):
		_go_back()

func _update_display() -> void:
	var song = song_list[cur_sel]
	# Background
	var bg_path = "res://holyquintet_mod/source/images/ui/freeplay/backgrounds/" + song["bg"] + ".png"
	if ResourceLoader.exists(bg_path):
		bg_tex.texture = load(bg_path)
	# Portrait
	var port_path = "res://holyquintet_mod/source/images/ui/freeplay/portraits/" + song["portrait"] + ".png"
	if ResourceLoader.exists(port_path):
		portrait_tex.texture = load(port_path)
	# Labels
	song_label.text = song["display"]
	diff_label.text = diff_names[cur_diff].capitalize()

func _play_song() -> void:
	can_control = false
	var song = song_list[cur_sel]
	var scene_path = "res://songs/" + song["name"] + "/" + song["name"].replace("-", "_") + ".tscn"
	if not ResourceLoader.exists(scene_path):
		can_control = true
		return
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene_path))

func _go_back() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))
