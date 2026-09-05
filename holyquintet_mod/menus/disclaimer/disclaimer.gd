extends Control
## HQ Disclaimer screen — shows disclaimer image, waits for input, then goes to title.

@onready var bg: TextureRect = $BG
@onready var disc_text: RichTextLabel = $DiscText
@onready var fade_rect: ColorRect = $FadeRect

var wait_timer: float = 2.0
var accepted: bool = false
var elapsed: float = 0.0

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN_OUT)

func _process(delta: float) -> void:
	elapsed += delta
	wait_timer -= delta
	if Input.is_action_just_pressed("ui_accept") and wait_timer <= 0 and not accepted:
		accepted = true
		var tw = create_tween()
		tw.tween_property(fade_rect, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/title/title_screen.tscn"))
