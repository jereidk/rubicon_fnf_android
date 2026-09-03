extends "res://animania_mod/scripts/song_events.gd"
## Phone-call specific chart events.
##
## Extends song_events.gd with the choreography unique to phone-call.
## All generic AnimaniaModule features live in the parent.

## ─── Phone-call constants ───────────────────────────────────────────────────
const STAGE_ZOOM := 0.65
const INTRO_FADE_SECONDS := 2.5
const INTRO_TEXT_SCALE := 0.8
const ENTRANCE_OUT := 380.0
const ENTRANCE_BACK := 350.0
const ENTRANCE_SECONDS := 1.45
const ENTRANCE_SETTLE_SECONDS := 0.5
const HUD_IN_SECONDS := 0.35
const HUD_IN_ZOOM := 1.1
const PULSE_FIRST_BEAT := 232
const PULSE_FROM := 0.95
const PULSE_TO_PLAYER := 1.05
const PULSE_TO_OPPONENT := 1.0
const LANE_SCALE_PLAYER := 1.0
const LANE_SCALE_OPPONENT := 0.95
const LANES_IN_SECONDS := 1.5
const LANES_IN_DELAY := 2.0
const LANES_HALF_ALPHA := 0.5
const HUD_TWEEN_DISTANCE := 250.0
const HUD_TWEEN_SECONDS := 1.75
const HUD_TWEEN_DELAY_UP := 0.25
const HUD_TWEEN_DELAY_DOWN := 0.5
const FLASH_SECONDS := 1.5
const SLIDE_DISTANCE := 800.0
const SLIDE_SECONDS := 1.35

## ─── Exports ────────────────────────────────────────────────────────────────
@export var stand_cast: Dictionary[StringName, Node] = {}
@export var stage: Node2D
@export var bumper: Node
@export var flash: ColorRect
@export var fade_rect: ColorRect
@export var cover: ColorRect
@export var intro_text: AnimatedSprite2D
@export var script_bars: CanvasItem


func _ready() -> void:
	super()
	setup_opening(cover, intro_text, INTRO_TEXT_SCALE)


func _get_stage_zoom() -> float:
	return STAGE_ZOOM


## ─── Per-frame ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	super(delta)
	# HUD scale decay is now handled by the base class.


## ─── Beat choreography ──────────────────────────────────────────────────────
func _on_beat() -> void:
	if dying or clock == null:
		return
	var beat: int = floori(clock.time_beat)
	if beat <= PULSE_FIRST_BEAT or beat % 2 != 0:
		return
	var changes: Array[RubiconTimeChange] = clock.get_time_changes()
	var seconds: float = (RubiconTimeChange.get_millisecond_at_beat(changes, beat + 1)
		- RubiconTimeChange.get_millisecond_at_beat(changes, beat)) / 1000.0
	if seconds <= 0.0:
		return
	pulse_strumlines(player_lanes, opponent_lanes, seconds,
		PULSE_TO_PLAYER, PULSE_TO_OPPONENT, PULSE_FROM)


## ─── Opening ────────────────────────────────────────────────────────────────
func opening() -> void:
	setup_opening(cover, intro_text, INTRO_TEXT_SCALE)
	if hud_root != null:
		hud_root.modulate.a = 0.0
	park_lanes_offscreen()
	set_keys_enabled(false)


## ─── Intro text ─────────────────────────────────────────────────────────────
func intro_show_text() -> void:
	if not first_time(&"intro_show_text") or intro_text == null:
		return
	intro_text.visible = true
	var frame: Texture2D = intro_text.sprite_frames.get_frame_texture(
		intro_text.animation, 0)
	centre_text_on_screen(intro_text, frame, INTRO_TEXT_SCALE)
	if _intro_tween != null:
		_intro_tween.kill()
	_intro_tween = create_tween()
	_intro_tween.tween_property(intro_text, "modulate:a", 1.0,
		INTRO_FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func intro_hide_text() -> void:
	if not first_time(&"intro_hide_text"):
		return
	hide_intro(intro_text, 0.6)


func intro_reveal() -> void:
	if not first_time(&"intro_reveal"):
		return
	fade_cover(cover, 1.25)


## ─── HUD ────────────────────────────────────────────────────────────────────
func hud_in() -> void:
	if not first_time(&"hud_in"):
		return
	_hud_tween = hud_zoom_in(hud, _hud_rest, HUD_IN_ZOOM, HUD_IN_SECONDS)
	fade_in_nodes([hud_root, player_lanes], HUD_IN_SECONDS)


func hud_out() -> void:
	if not first_time(&"hud_out"):
		return
	var distance: float = HUD_TWEEN_DISTANCE * FUNKIN_TO_RUBICON
	tween_hud_out(hud_up, -distance, HUD_TWEEN_DELAY_UP, HUD_TWEEN_SECONDS)
	tween_hud_out(hud_down, distance, HUD_TWEEN_DELAY_DOWN, HUD_TWEEN_SECONDS)


## ─── Stand-up swap ──────────────────────────────────────────────────────────
func stand_up() -> void:
	if not first_time(&"stand_up"):
		return
	swap_characters(stand_cast, stage)
	if hud_root != null:
		hud_root.visible = true


## ─── Opponent lanes in ──────────────────────────────────────────────────────
func opponent_lanes_in() -> void:
	if not first_time(&"opponent_lanes_in"):
		return
	if opponent_lanes == null or not _lane_homes.has(&"player"):
		return
	lanes_fly_in(opponent_lanes, _lane_homes[&"player"].x,
		LANES_IN_SECONDS, LANES_IN_DELAY, LANES_HALF_ALPHA)


## ─── Boyfriend slide ────────────────────────────────────────────────────────
func boyfriend_slide() -> void:
	if not first_time(&"boyfriend_slide"):
		return
	character_slide(&"boyfriend", SLIDE_DISTANCE, SLIDE_SECONDS)


## ─── Keys ───────────────────────────────────────────────────────────────────
func keys_on() -> void:
	set_keys_enabled(true)
	if script_bars != null:
		script_bars.visible = false


## ─── Fade ───────────────────────────────────────────────────────────────────
func fade_out(duration: float) -> void:
	fade_out_node(fade_rect, duration)
