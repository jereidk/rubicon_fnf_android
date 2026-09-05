extends Control
## HQ Results — shows score, accuracy, grade after song completion

@onready var song_label: Label = $VBox/SongLabel
@onready var score_label: Label = $VBox/ScoreLabel
@onready var acc_label: Label = $VBox/AccLabel
@onready var grade_label: Label = $VBox/GradeLabel
@onready var retry_label: Label = $RetryLabel
@onready var fade_rect: ColorRect = $FadeRect

var can_control: bool = false


func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): can_control = true)

	song_label.text = ResultsData.song_name if ResultsData.song_name != "" else "Song Complete!"
	score_label.text = "Score: %d" % ResultsData.score
	acc_label.text = "Accuracy: %.1f%%" % ResultsData.accuracy
	grade_label.text = _calc_grade(ResultsData.accuracy)


func _process(_delta: float) -> void:
	if can_control and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel")):
		can_control = false
		var tw = create_tween()
		tw.tween_property(fade_rect, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn"))


func _calc_grade(acc: float) -> String:
	if acc >= 99.0:
		return "S+"
	elif acc >= 95.0:
		return "S"
	elif acc >= 90.0:
		return "A"
	elif acc >= 80.0:
		return "B"
	elif acc >= 70.0:
		return "C"
	elif acc >= 60.0:
		return "D"
	else:
		return "F"
