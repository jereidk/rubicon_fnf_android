extends CanvasLayer
## Ports HQTransition.hx — global.hx sets `MusicBeatTransition.script =
## 'data/scripts/HQTransition'`, so EVERY state switch in the real mod goes
## through this (black screen + Kyubey running across), not just one
## specific screen. Registered as an autoload so it survives
## change_scene_to_file() (a plain node in the outgoing scene would be
## freed with it) and plays continuously across the swap.
##
## Real flow per switch is two halves, both driven by the same 0.75s
## FlxTimer regardless of whether the tweens themselves have finished:
##  - transOut (leaving the old state): black fades in (alpha 0->1, 0.25s
##    sineIn) while Kyubey runs in from x-100 fading in (alpha 0->1, 0.5s
##    sineOut) — then change_scene fires.
##  - transIn (arriving at the new state): black fades out (alpha 1->0,
##    0.25s sineIn) while Kyubey runs off to x+250 fading out (alpha 1->0,
##    0.5s sineIn).
## kyubey_spr.setPosition((FlxG.width - width/2) * 0.90, (FlxG.height -
## height/2) * 0.90) with FlxG at 1920x1080 and the run animation's frame
## box at 214x108 (KYUBEYRUN.xml's frameWidth/frameHeight, constant across
## every subtexture despite each one trimming differently).

const KYUBEY_FRAMES := preload("res://holyquintet_mod/menus/transition/kyubey_frames.tres")
const KYUBEY_ANIM := &"kyubey run instance "
const REST_X := (1920.0 - 214.0 / 2.0) * 0.90
const REST_Y := (1080.0 - 108.0 / 2.0) * 0.90
const HOLD_TIME := 0.75

var _black: ColorRect
var _kyubey: AnimatedSprite2D


func _ready() -> void:
	layer = 4096
	process_mode = Node.PROCESS_MODE_ALWAYS

	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	add_child(_black)

	_kyubey = AnimatedSprite2D.new()
	_kyubey.sprite_frames = KYUBEY_FRAMES
	_kyubey.animation = KYUBEY_ANIM
	_kyubey.centered = false
	_kyubey.position = Vector2(REST_X, REST_Y)
	_kyubey.modulate.a = 0.0
	add_child(_kyubey)
	_kyubey.play(KYUBEY_ANIM)


## Real MusicBeatState.switchState(): outro transition, then the actual
## FlxG.switchState(), then an intro transition revealing the new state.
func switch_scene(path: String) -> void:
	await _play_outro()
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await _play_intro()


func _play_outro() -> void:
	_kyubey.position.x = REST_X - 100.0
	_kyubey.modulate.a = 0.0
	_black.modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_black, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_kyubey, "position:x", REST_X, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_kyubey, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(HOLD_TIME).timeout


func _play_intro() -> void:
	_kyubey.position.x = REST_X
	_kyubey.modulate.a = 1.0
	_black.modulate.a = 1.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_black, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_kyubey, "position:x", REST_X + 250.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(_kyubey, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(HOLD_TIME).timeout
