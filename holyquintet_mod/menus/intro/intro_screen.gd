extends Control
## HQ Intro — the initial cutscene sequence with the wish prompt.
## Ports the mod's HQIntro. Videos are replaced with a stylised title-card
## sequence since hxvlc videos aren't available in the port; the Yes/No wish
## prompt and the flow into Disclaimer are preserved.

var can_control: bool = false
var selecting_yes: bool = false
var has_moved: bool = false
var _phase: int = 0
var _elapsed: float = 0.0
var _leaving: bool = false

@onready var title_card: TextureRect = $TitleCard
@onready var question_label: Label = $QuestionLabel
@onready var yes_label: Label = $YesLabel
@onready var no_label: Label = $NoLabel
@onready var selector: TextureRect = $Selector
@onready var subtitle_label: Label = $SubtitleLabel
@onready var fade_rect: ColorRect = $FadeRect

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(1.5)
	tw.tween_callback(_show_prompt)

func _show_prompt() -> void:
	_phase = 1
	question_label.visible = true
	yes_label.visible = true
	no_label.visible = true
	selector.visible = true
	selector.alpha = 0.0
	selector.position = Vector2(1075, 600)
	yes_label.modulate.a = 0.5
	no_label.modulate.a = 0.5
	_can_control = true
	var stw := create_tween()
	stw.tween_property(selector, "modulate:a", 0.5, 0.5)

var _can_control: bool = false

func _process(_delta: float) -> void:
	if _leaving or _phase != 1 or not _can_control:
		return
	if Input.is_action_just_pressed("ui_left") and (selecting_yes or not has_moved):
		selecting_yes = false
		has_moved = true
		_highlight(false)
		var tw := create_tween()
		tw.tween_property(selector, "position:x", 375.0, 0.5).set_ease(Tween.EASE_OUT)
	elif Input.is_action_just_pressed("ui_right") and (not selecting_yes or not has_moved):
		selecting_yes = true
		has_moved = true
		_highlight(true)
		var tw := create_tween()
		tw.tween_property(selector, "position:x", 1075.0, 0.5).set_ease(Tween.EASE_OUT)
	elif Input.is_action_just_pressed("ui_accept") and has_moved:
		_confirm()

func _highlight(yes: bool) -> void:
	yes_label.scale = Vector2(1.15, 1.15) if yes else Vector2.ONE
	no_label.scale = Vector2(1.15, 1.15) if not yes else Vector2.ONE
	yes_label.modulate.a = 1.0 if yes else 0.5
	no_label.modulate.a = 1.0 if not yes else 0.5

func _confirm() -> void:
	_can_control = false
	_leaving = true
	if selecting_yes:
		subtitle_label.text = "Make a wish..."
	else:
		subtitle_label.text = "Goodbye..."
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(fade_rect, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN)
	tw.tween_callback(_leave)

func _leave() -> void:
	HQSaves.see_intro = false
	HQSaves.save_data()
	get_tree().change_scene_to_file("res://holyquintet_mod/menus/disclaimer/disclaimer.tscn")
