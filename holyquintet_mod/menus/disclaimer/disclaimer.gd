extends Control
## Ports HQDisclaimer.hx exactly: real disclaimer.png background, real
## translated warning text (shingo.otf, size 42, white, OUTLINE border —
## borderSize 2.5 matches MessageWindowUI's own 2.5, so outline_size=5
## reuses that same real-screenshot-calibrated mapping), a 1.0s fade in,
## a 2.0s minimum wait before ACCEPT does anything, then on accept: the
## real 'confirm' UI sound, a 1.0s fade to black, a further 1.0s pause
## (the real FlxTimer(1.0) after the fade's onComplete, not just the
## fade's own tail), then switching to HQTitle.
##
## FlxG.sound.music.stop() in the real create() is skipped: nothing plays
## music this early in the boot chain in this port, so it would be a no-op
## with no music system yet to call it on.

const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

@onready var bg: TextureRect = $BG
@onready var disc_text: Label = $DiscText
@onready var fade_rect: ColorRect = $FadeRect

var wait_timer: float = 2.0
var accepted: bool = false


func _ready() -> void:
	fade_rect.modulate.a = 1.0
	create_tween().tween_property(fade_rect, "modulate:a", 0.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	wait_timer -= delta


func _unhandled_input(event: InputEvent) -> void:
	# Event-driven rather than polling is_action_just_pressed() in _process():
	# established elsewhere in this port (hq_message_window.gd, intro_screen.gd)
	# as the fix for input silently getting missed under irregular frame pacing.
	if accepted or wait_timer > 0.0:
		return
	var tapped := event.is_action_pressed("ui_accept")
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	if tapped:
		_accept()


func _accept() -> void:
	accepted = true
	GenUtil.play_ui_sound(self, "confirm")
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(1.0)
	tw.tween_callback(func(): HQTransition.switch_scene("res://holyquintet_mod/menus/title/title_screen.tscn"))
