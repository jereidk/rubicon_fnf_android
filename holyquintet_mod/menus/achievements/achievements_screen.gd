extends Control
## HQ Achievements — grid of 19 achievements, selector, preview, progress tracker.
## Ports the mod's HQAchievements state. GameJolt sync is offline in this port.

const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "FCInitium",        "name": "FC Initium",         "desc": "Full Combo Initium on Hard",          "diff": 1, "img": "fc_initium",         "tracker": 0},
	{"id": "FCResonance",      "name": "FC Resonance",       "desc": "Full Combo Resonance on Hard",        "diff": 1, "img": "fc_resonance",       "tracker": 0},
	{"id": "FCPartea",         "name": "FC Partea",          "desc": "Full Combo Partea on Hard",           "diff": 1, "img": "fc_partea",          "tracker": 0},
	{"id": "FCEternalStar",    "name": "FC Eternal Star",    "desc": "Full Combo Eternal Star on Hard",     "diff": 1, "img": "fc_eternalstar",     "tracker": 0},
	{"id": "FCVexation",       "name": "FC Vexation",        "desc": "Full Combo Vexation on Hard",         "diff": 1, "img": "fc_vexation",        "tracker": 0},
	{"id": "FCOutOfTime",      "name": "FC Out-of-Time",     "desc": "Full Combo Out-of-Time on Hard",      "diff": 1, "img": "fc_outoftime",       "tracker": 0},
	{"id": "CompleteAct1",     "name": "Hope",               "desc": "Complete Act 1 (Out-of-Time story)",  "diff": 1, "img": "clear_part1",        "tracker": 0},
	{"id": "FCMeguca",         "name": "FC Meguca",          "desc": "Full Combo Meguca on Hard",           "diff": 1, "img": "fc_meguca",          "tracker": 0},
	{"id": "FCReconnect",      "name": "FC Reconnect",       "desc": "Full Combo Reconnect on Hard",        "diff": 1, "img": "fc_reconnect",       "tracker": 0},
	{"id": "FCStardom",        "name": "FC Stardom",         "desc": "Full Combo Stardom on Hard",          "diff": 1, "img": "fc_stardom",         "tracker": 0},
	{"id": "ResOutheal",       "name": "Outheal the Healer", "desc": "Complete Resonance without health below 60%", "diff": 0, "img": "resonance_outheal", "tracker": 0},
	{"id": "VexYikes",         "name": "Yikes!",             "desc": "Take no sustained damage in Vexation", "diff": 0, "img": "vexation_dodgeall",   "tracker": 0},
	{"id": "YoureOnMyTime",    "name": "You're on my Time",  "desc": "Out-of-Time without timestop or bullet note miss", "diff": 0, "img": "outoftime_dodgeall", "tracker": 0},
	{"id": "TimeWaitsForMe",   "name": "Time waits for ME!", "desc": "Pause during Out-of-Time",             "diff": 0, "img": "outoftime_pause",     "tracker": 0},
	{"id": "Tenacious",        "name": "Tenacious",          "desc": "Die 15 or more times in a single session", "diff": 0, "img": "general_restart",     "tracker": 0},
	{"id": "ThanksForPlaying", "name": "Thanks For Playing", "desc": "Visit the Credits screen",              "diff": 0, "img": "general_visitcredits", "tracker": 0},
	{"id": "ChamberOfLight",   "name": "Chamber of Light",   "desc": "Visit the Gallery",                    "diff": 0, "img": "general_visitgallery", "tracker": 0},
	{"id": "PinpointAccuracy", "name": "Pinpoint Accuracy",  "desc": "Land 5000 Perfect hits",               "diff": 1, "img": "general_pinpoint",    "tracker": 5000},
	{"id": "Devoted",          "name": "Devoted",            "desc": "Play 25 songs",                        "diff": 1, "img": "general_devoted",     "tracker": 25},
]

const FRAME_PATHS := {0: "bronze", 1: "silver", 2: "gold", 3: "platinum"}
const COLS := 6
const GRID_X := 545
const GRID_Y := 105
const COL_W := 215
const ROW_H := 205

var cur_sel: int = 0
var can_control: bool = true

@onready var preview_frame: TextureRect = $PreviewFrame
@onready var preview_icon: TextureRect = $PreviewIcon
@onready var name_label: Label = $NameLabel
@onready var desc_label: Label = $DescLabel
@onready var tracker_label: Label = $TrackerLabel
@onready var selector: TextureRect = $Selector
@onready var fade_rect: ColorRect = $FadeRect

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	var sel_tw = create_tween().set_loops()
	sel_tw.tween_property(selector, "scale", Vector2(1.06, 1.06), 0.5).set_ease(Tween.EASE_IN_OUT)
	sel_tw.tween_property(selector, "scale", Vector2(1.0, 1.0), 0.5).set_ease(Tween.EASE_IN_OUT)
	_update_selection()

func _process(_delta: float) -> void:
	if not can_control:
		return
	if Input.is_action_just_pressed("ui_up"):
		_change_sel(-COLS)
	elif Input.is_action_just_pressed("ui_down"):
		_change_sel(COLS)
	elif Input.is_action_just_pressed("ui_left"):
		_change_sel(-1)
	elif Input.is_action_just_pressed("ui_right"):
		_change_sel(1)
	elif Input.is_action_just_pressed("ui_cancel"):
		_on_back()

func _change_sel(delta: int) -> void:
	if delta == 0:
		return
	cur_sel = wrapi(cur_sel + delta, 0, ACHIEVEMENTS.size())
	_update_selection()

func _update_selection() -> void:
	var ach := ACHIEVEMENTS[cur_sel]
	var unlocked := not HQSaves.is_achievement_locked(ach["id"])
	var frame_name: String = FRAME_PATHS.get(ach["diff"], "bronze")
	var frame_tex: Texture2D = load("res://holyquintet_mod/source/images/ui/accolades/frames/%s.png" % frame_name)
	var icon_tex: Texture2D = load("res://holyquintet_mod/source/images/ui/accolades/achievements/%s.png" % ach["img"])
	preview_frame.texture = frame_tex
	preview_icon.texture = icon_tex
	preview_frame.modulate.a = 1.0 if unlocked else 0.4
	preview_icon.modulate.a = 1.0 if unlocked else 0.1
	name_label.text = ach["name"] if unlocked else "???"
	desc_label.text = ach["desc"] if unlocked else "Locked"
	var col := cur_sel % COLS
	var row := cur_sel / COLS
	selector.position = Vector2(GRID_X + col * COL_W, GRID_Y + row * ROW_H)
	if ach["tracker"] > 0 and not unlocked:
		var progress: int = HQSaves.achievement_progress(ach["id"])
		tracker_label.visible = true
		tracker_label.text = "%d / %d" % [progress, ach["tracker"]]
	else:
		tracker_label.visible = false

func _on_back() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))
