extends Control
## HQ Gauntlet — mod selection gauntlet mode. Ports the mod's HQGauntlet:
## background tiers (peaceful/stressed/hopeless) by multiplier, scrollable
## mod selector, Start button, local best score. Leaderboards are local-only.

const GAUNTLET_MODS: Array[Dictionary] = [
	{"id": "PerformanceRegen",         "name": "Performance Regen",           "mult": 0.75, "multi": true,  "conflicts": []},
	{"id": "NoMechanics",              "name": "No Mechanics",                "mult": 0.5,  "multi": true,  "conflicts": ["HarderMechanics", "InstantKillMechanics"]},
	{"id": "BiggerJudgementWindows",   "name": "Bigger Judgement Windows",    "mult": 0.75, "multi": true,  "conflicts": ["SmallerJudgementWindows"]},
	{"id": "IncreasedPerformanceLoss", "name": "Increased Performance Loss",  "mult": 0.5,  "multi": false, "conflicts": []},
	{"id": "SmallerJudgementWindows",  "name": "Smaller Judgement Windows",   "mult": 0.5,  "multi": false, "conflicts": ["BiggerJudgementWindows"]},
	{"id": "ComboCountRequirement",    "name": "Combo Count Requirement",     "mult": 0.75, "multi": false, "conflicts": []},
	{"id": "OpponentPerformanceDrain", "name": "Opponent Performance Drain",  "mult": 0.75, "multi": false, "conflicts": []},
	{"id": "HarderMechanics",          "name": "Harder Mechanics",            "mult": 1.5,  "multi": false, "conflicts": ["NoMechanics"]},
	{"id": "InstantKillMechanics",     "name": "Instant Kill Mechanics",      "mult": 1.5,  "multi": false, "conflicts": ["NoMechanics"]},
	{"id": "HigherScoreRequirement",   "name": "Higher Score Requirement",    "mult": 1.0,  "multi": false, "conflicts": []},
	{"id": "StealthNotes",             "name": "Stealth Notes",               "mult": 0.75, "multi": false, "conflicts": []},
	{"id": "ZoomingNotes",             "name": "Zooming Notes",               "mult": 0.75, "multi": false, "conflicts": []},
]

const THRESHOLDS: Array[float] = [4.0, 8.0]
const SONGS: Array[Dictionary] = [
	{"name": "resonance"}, {"name": "partea"}, {"name": "vexation"},
	{"name": "out-of-time"}, {"name": "meguca"}, {"name": "reconnect"},
]
const SONG_SCENES := {
	"resonance": "res://songs/resonance/resonance.tscn",
	"partea": "res://songs/partea/partea.tscn",
	"vexation": "res://songs/vexation/vexation.tscn",
	"out-of-time": "res://songs/out-of-time/out_of_time.tscn",
	"meguca": "res://songs/meguca/meguca.tscn",
	"reconnect": "res://songs/reconnect/reconnect.tscn",
}

const BGS := {
	"peaceful": "res://holyquintet_mod/source/images/ui/gauntlet/bgs/peaceful/bg.png",
	"stressed": "res://holyquintet_mod/source/images/ui/gauntlet/bgs/stressed/bg.png",
	"hopeless": "res://holyquintet_mod/source/images/ui/gauntlet/bgs/hopeless/bg.png",
}

var enabled_mods: Dictionary = {}
var _enabled_list: Array[String] = []
var multiplier: float = 1.0
var cur_bg: String = "peaceful"
var cur_sel: int = 0
var can_control: bool = true
var _starting: bool = false
var _bar_target: float = 1.0

@onready var bg_tex: TextureRect = $BG
@onready var fog_tex: TextureRect = $Fog
@onready var mod_list: VBoxContainer = $RightPanel/ModList
@onready var mult_label: Label = $StatDisplay/MultLabel
@onready var best_label: Label = $StatDisplay/BestLabel
@onready var meter_bar: TextureProgressBar = $MeterBar
@onready var start_label: Label = $StartLabel
@onready var fade_rect: ColorRect = $FadeRect

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	for mod in GAUNTLET_MODS:
		enabled_mods[mod["id"]] = false
	_build_mod_rows()
	_recompute()
	_update_sel()
	HQSaves.cur_gauntlet_mods = []
	HQSaves.cur_gauntlet_multiplier = 1.0
	HQSaves.is_gauntlet_mode = true

func _build_mod_rows() -> void:
	for i in GAUNTLET_MODS.size():
		var mod := GAUNTLET_MODS[i]
		var lbl := Label.new()
		lbl.name = "Mod%d" % i
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mod_list.add_child(lbl)

func _process(delta: float) -> void:
	# Scroll fog
	if fog_tex != null:
		fog_tex.position.x = fposmod(fog_tex.position.x + 50.0 * delta, 1200.0)
	if _starting or not can_control:
		return
	if Input.is_action_just_pressed("ui_up"):
		cur_sel = wrapi(cur_sel - 1, 0, GAUNTLET_MODS.size() + 1)
		_update_sel()
	elif Input.is_action_just_pressed("ui_down"):
		cur_sel = wrapi(cur_sel + 1, 0, GAUNTLET_MODS.size() + 1)
		_update_sel()
	elif Input.is_action_just_pressed("ui_accept"):
		_confirm()
	elif Input.is_action_just_pressed("ui_cancel"):
		_go_back()
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		_toggle_current()

func _go_back() -> void:
	HQSaves.is_gauntlet_mode = false
	can_control = false
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))

func _update_sel() -> void:
	# Mode selector row
	for i in range(mod_list.get_child_count()):
		var lbl := mod_list.get_child(i) as Label
		if lbl == null:
			continue
		var mod: Dictionary = GAUNTLET_MODS[i] if i < GAUNTLET_MODS.size() else {}
		if mod == null:
			continue
		var active: bool = enabled_mods.get(mod["id"], false)
		var prefix := ">  " if cur_sel == i + 1 else "   "
		var locked := _is_locked(mod)
		if locked:
			lbl.text = "%s[LOCKED] %s" % [prefix, mod["name"]]
			lbl.modulate = Color(0.5, 0.5, 0.5)
		else:
			lbl.text = "%s%s %s" % [prefix, "[x] " if active else "[ ] ", mod["name"]]
			lbl.modulate = Color.WHITE if cur_sel == i + 1 else Color(0.75, 0.75, 0.75)
	start_label.text = ">  Start" if cur_sel == GAUNTLET_MODS.size() + 1 else "   Start"
	start_label.modulate = Color.WHITE if cur_sel == GAUNTLET_MODS.size() + 1 else Color(0.75, 0.75, 0.75)

func _is_locked(mod: Dictionary) -> bool:
	for c in mod["conflicts"]:
		if enabled_mods.get(c, false):
			return true
	return false

func _toggle_current() -> void:
	if cur_sel == 0 or cur_sel > GAUNTLET_MODS.size():
		return
	var mod := GAUNTLET_MODS[cur_sel - 1]
	var locked := false
	for c in mod["conflicts"]:
		if enabled_mods.get(c, false):
			locked = true
			break
	if locked:
		return
	enabled_mods[mod["id"]] = not enabled_mods.get(mod["id"], false)
	# Clear conflicts on other mods
	for other in GAUNTLET_MODS:
		if other["conflicts"].has(mod["id"]):
			enabled_mods[other["id"]] = false
	_recompute()
	_update_sel()

func _recompute() -> void:
	_enabled_list = []
	for mod in GAUNTLET_MODS:
		if enabled_mods.get(mod["id"], false):
			_enabled_list.append(mod["id"])
	multiplier = 1.0
	for mod in GAUNTLET_MODS:
		if enabled_mods.get(mod["id"], false) and not mod["multi"]:
			multiplier += float(mod["mult"])
	# Pair bonus: HarderMechanics + InstantKillMechanics
	if enabled_mods.get("HarderMechanics", false) and enabled_mods.get("InstantKillMechanics", false):
		multiplier += 1.0
	for mod in GAUNTLET_MODS:
		if enabled_mods.get(mod["id"], false) and mod["multi"]:
			multiplier *= float(mod["mult"])
	mult_label.text = "x%.2f" % multiplier
	meter_bar.value = clampf(multiplier / 10.0, 0.0, 1.0)
	HQSaves.cur_gauntlet_multiplier = multiplier
	HQSaves.cur_gauntlet_mods = _enabled_list
	_update_bg()

func _update_bg() -> void:
	var target: String = "peaceful"
	if multiplier >= THRESHOLDS[1]:
		target = "hopeless"
	elif multiplier >= THRESHOLDS[0]:
		target = "stressed"
	if target == cur_bg:
		return
	cur_bg = target
	var p: String = BGS[cur_bg]
	if ResourceLoader.exists(p):
		var tw := create_tween()
		tw.tween_property(bg_tex, "modulate:a", 0.2, 0.4).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func():
			bg_tex.texture = load(p)
			var tw2 := create_tween()
			tw2.tween_property(bg_tex, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_IN_OUT)
		)

func _confirm() -> void:
	if cur_sel == 0:
		pass  # Mode button (Standard only)
	elif cur_sel == GAUNTLET_MODS.size() + 1:
		_begin()
	else:
		_toggle_current()

func _begin() -> void:
	_starting = true
	can_control = false
	HQSaves.reset_run_state()
	HQSaves.is_gauntlet_mode = true
	HQSaves.cur_gauntlet_mods = _enabled_list
	HQSaves.campaign_score = 0
	HQSaves.campaign_misses = 0
	var songs := SONGS.duplicate()
	songs.shuffle()
	var scenes: Array[String] = []
	for s in songs:
		scenes.append(SONG_SCENES[s["name"]])
	HQSaves.campaign_songs_left = scenes
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		get_tree().change_scene_to_file(HQSaves.campaign_songs_left[0])
	)
