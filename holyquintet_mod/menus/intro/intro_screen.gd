extends Control
## HQ Intro — ports HQIntro.hx exactly: real intro_start/yes/no videos
## (converted to Ogg Theora — Godot has no native MP4/HEVC decoder), the
## real wish-prompt art (selector glow + two counter-rotating rings, yes.png/
## no.png calligraphy), and cinematic borders. Videos are muted; separate
## .ogg tracks play in sync, exactly like FlxVideoSprite + FlxG.sound.play
## in the source (hxvlc's own audio wasn't relied on there either).

const VIDEO_DIR := "res://holyquintet_mod/source/videos/"
const SOUND_DIR := "res://holyquintet_mod/source/sounds/videos/"
const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

var can_control: bool = false
var selecting_yes: bool = false
var has_moved: bool = false
var _leaving: bool = false

@onready var intro_video: VideoStreamPlayer = $IntroVideo
@onready var yes_video: VideoStreamPlayer = $YesVideo
@onready var no_video: VideoStreamPlayer = $NoVideo
@onready var question_text: Label = $QuestionText
@onready var selector_glow: TextureRect = $SelectorGlow
@onready var selector_ring_a: TextureRect = $SelectorRingA
@onready var selector_ring_b: TextureRect = $SelectorRingB
@onready var yes_sprite: TextureRect = $YesSprite
@onready var no_sprite: TextureRect = $NoSprite
@onready var subtitle_text: Label = $SubtitleText
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

# HQIntro.hx: selector.setPosition(710, 600); moves to x=375 (No) / x=1075
# (Yes) on selection. Rings always follow selector's position.
const SELECTOR_Y := 600.0
const SELECTOR_X_NEUTRAL := 710.0
const SELECTOR_X_NO := 375.0
const SELECTOR_X_YES := 1075.0

var _selector_tween: Tween


func _ready() -> void:
	selector_glow.position = Vector2(SELECTOR_X_NEUTRAL, SELECTOR_Y)
	_update_ring_positions()

	intro_video.stream = load(VIDEO_DIR + "intro_start.ogv")
	intro_video.finished.connect(_on_intro_video_finished)
	intro_video.play()
	_play_synced_audio("intro_start")


func _process(delta: float) -> void:
	# HQIntro.hx update(): rings continuously chase the glow's position,
	# spin opposite directions at 15deg/s, and fade with (glow_alpha / 5).
	selector_ring_a.position = selector_glow.position
	selector_ring_b.position = selector_glow.position
	selector_ring_a.rotation -= deg_to_rad(15.0) * delta
	selector_ring_b.rotation += deg_to_rad(15.0) * delta
	selector_ring_a.modulate.a = selector_glow.modulate.a / 5.0
	selector_ring_b.modulate.a = selector_glow.modulate.a / 5.0

	if yes_video.visible and yes_video.is_playing():
		_update_subtitle(yes_video.stream_position)


func _unhandled_input(event: InputEvent) -> void:
	# Event-driven rather than polling is_action_just_pressed() in _process():
	# with 3 VideoStreamPlayers decoding, this scene's render frame pacing is
	# uneven enough that a poll-once-per-_process() check can miss the single
	# frame is_action_just_pressed() is true on. Reacting to the event itself
	# has no such window to miss, on this screen or any other frame rate.
	if not can_control or _leaving:
		return
	if event.is_action_pressed("ui_left") and (selecting_yes or not has_moved):
		_select(false)
	elif event.is_action_pressed("ui_right") and (not selecting_yes or not has_moved):
		_select(true)
	elif event.is_action_pressed("ui_accept") and has_moved:
		_confirm()


func _update_ring_positions() -> void:
	selector_ring_a.position = selector_glow.position
	selector_ring_b.position = selector_glow.position


func _update_subtitle(t: float) -> void:
	# HQIntro.hx update(): yesVideo.bitmap.time windows, in ms there -> s here.
	if t >= 0.300 and t <= 1.218:
		subtitle_text.text = "A wish..."
	elif t >= 9.350 and t <= 10.043:
		subtitle_text.text = "I..."
	elif t >= 12.346 and t <= 13.864:
		subtitle_text.text = "I wanna be just like him."
	else:
		subtitle_text.text = ""


func _play_synced_audio(name: String) -> void:
	audio_player.stream = load(SOUND_DIR + name + ".ogg")
	audio_player.play()


func _on_intro_video_finished() -> void:
	# HQIntro.hx introVideo.onEndReached: fade in question + Yes/No, then
	# allow control once faded in (canControl = true onComplete).
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(question_text, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(no_sprite, "modulate:a", 0.5, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(yes_sprite, "modulate:a", 0.5, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func(): can_control = true)


func _select(yes: bool) -> void:
	selecting_yes = yes
	has_moved = true
	GenUtil.play_ui_sound(self, "move")

	var no_alpha := 1.0 if not yes else 0.5
	var yes_alpha := 1.0 if yes else 0.5
	var no_scale := 1.15 if not yes else 1.0
	var yes_scale := 1.15 if yes else 1.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(no_sprite, "modulate:a", no_alpha, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(no_sprite, "scale", Vector2(no_scale, no_scale), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(yes_sprite, "modulate:a", yes_alpha, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(yes_sprite, "scale", Vector2(yes_scale, yes_scale), 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	if _selector_tween:
		_selector_tween.kill()
	_selector_tween = create_tween()
	_selector_tween.set_parallel(true)
	_selector_tween.tween_property(selector_glow, "position:x", SELECTOR_X_YES if yes else SELECTOR_X_NO, 0.5) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_selector_tween.tween_property(selector_glow, "modulate:a", 0.5, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _confirm() -> void:
	can_control = false
	if selecting_yes:
		GenUtil.play_ui_sound(self, "confirm")
	else:
		GenUtil.play_ui_sound(self, "confirmbad")

	var tw := create_tween()
	tw.set_parallel(true)
	var win_target := yes_sprite if selecting_yes else no_sprite
	tw.tween_property(win_target, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(win_target, "scale", Vector2(1.25, 1.25), 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	for spr in [yes_sprite, no_sprite, question_text, selector_glow]:
		var fade := create_tween()
		fade.tween_interval(1.25)
		fade.tween_property(spr, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(1.5).timeout
	_leaving = true
	if selecting_yes:
		await get_tree().create_timer(1.0).timeout
		_play_yes_video()
	else:
		await get_tree().create_timer(2.0).timeout
		_play_no_video()


func _play_yes_video() -> void:
	yes_video.visible = true
	yes_video.stream = load(VIDEO_DIR + "intro_yes.ogv")
	yes_video.finished.connect(_on_yes_video_finished)
	yes_video.play()
	_play_synced_audio("intro_yes")


func _on_yes_video_finished() -> void:
	# HQIntro.hx yesVideo.onEndReached(): seeIntro = false -> HQDisclaimer.
	HQSaves.see_intro = false
	HQSaves.save_data()
	get_tree().change_scene_to_file("res://holyquintet_mod/menus/disclaimer/disclaimer.tscn")


func _play_no_video() -> void:
	no_video.visible = true
	no_video.stream = load(VIDEO_DIR + "intro_no.ogv")
	no_video.finished.connect(_on_no_video_finished)
	no_video.play()
	_play_synced_audio("intro_no")


func _on_no_video_finished() -> void:
	# HQIntro.hx noVideo.onEndReached(): resets setup/intro flags and
	# Sys.exit()s the whole game outright — a deliberate "goodbye" troll,
	# not a bug. get_tree().quit() is the Godot equivalent of Sys.exit().
	HQSaves.first_time_setup_done = false
	HQSaves.see_intro = true
	HQSaves.save_data()
	get_tree().quit()
