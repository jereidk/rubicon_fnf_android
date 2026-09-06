extends Control
## HQ Gauntlet Transition — between-song interstitial and the end-of-gauntlet
## result screen. Ports the mod's HQGauntletTransition. Local scores only.

var is_end: bool = false
var failed: bool = false
var can_control: bool = false

@onready var result_label: Label = $ResultLabel
@onready var stats_label: Label = $StatsLabel
@onready var fade_rect: ColorRect = $FadeRect

func _setup(end_gauntlet: bool) -> void:
	is_end = end_gauntlet

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_end = HQSaves.gauntlet_ending
	HQSaves.gauntlet_ending = false
	fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.75).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_end:
			_show_end()
		else:
			_show_next()
	)

func _show_next() -> void:
	result_label.text = "Next Song"
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		if HQSaves.campaign_songs_left.is_empty():
			_go_gauntlet()
		else:
			get_tree().change_scene_to_file(HQSaves.campaign_songs_left[0])
	)

func _show_end() -> void:
	var score := HQSaves.campaign_score
	var misses := HQSaves.campaign_misses
	var best := HQSaves.best_gauntlet_score
	failed = score <= 0
	if score > best:
		HQSaves.best_gauntlet_score = score
		HQSaves.save_data()
	result_label.text = ("GAUNTLET FAILED" if failed else "GAUNTLET COMPLETE")
	stats_label.text = "Score: %d\nBreaks: %d\nBest: %d" % [score, misses, maxi(best, score)]
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func(): can_control = true)

func _process(_delta: float) -> void:
	if not is_end or not can_control:
		return
	if Input.is_action_just_pressed("ui_accept"):
		_go_gauntlet()

func _go_gauntlet() -> void:
	HQSaves.is_gauntlet_mode = false
	get_tree().change_scene_to_file("res://holyquintet_mod/menus/gauntlet/gauntlet_screen.tscn")
