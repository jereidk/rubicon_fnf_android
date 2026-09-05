extends Control
## HQ Game Over — retry/quit prompt after death

var can_control: bool = false
var elapsed: float = 0.0

@onready var quote_label: Label = $QuoteLabel
@onready var retry_label: Label = $RetryLabel
@onready var fade_rect: ColorRect = $FadeRect

var quotes: Array[String] = [
	"This isn\'t the end...",
	"Try again.",
	"Don\'t give up.",
	"You can do this.",
]

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	quote_label.text = quotes[randi() % quotes.size()]
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): can_control = true)

func _process(delta: float) -> void:
	elapsed += delta
	# Pulse the retry text
	if retry_label:
		retry_label.modulate.a = 0.5 + sin(elapsed * 3.0) * 0.5
	if can_control:
		if Input.is_action_just_pressed("ui_accept"):
			_retry()
		elif Input.is_action_just_pressed("ui_cancel"):
			_quit()

func _retry() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().reload_current_scene())

func _quit() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn"))
