extends "res://animania_mod/scripts/song_events.gd"
## Phone-call specific chart events.
##
## Extends song_events.gd with the choreography unique to phone-call:
## intro sequence, tadano entrance, stand-up swap, HUD in/out, opponent
## lanes fly-in, strumline pulse, boyfriend slide, and fade-out.
##
## All generic AnimaniaModule features (camera nudge, shake, character
## animation, key disable, etc.) live in the parent.

## ─── Phone-call constants ───────────────────────────────────────────────────
const STAGE_ZOOM := 0.65

## Intro (beats 0-31): cover, title card, HUD arrival.
const INTRO_FADE_SECONDS := 2.5
const INTRO_TEXT_SCALE := 0.8

## tadano entrance at beat 13.
const ENTRANCE_OUT := 380.0
const ENTRANCE_BACK := 350.0
const ENTRANCE_SECONDS := 1.45
const ENTRANCE_SETTLE_SECONDS := 0.5

## HUD zoom-in at beat 31.
const HUD_IN_SECONDS := 0.35
const HUD_IN_ZOOM := 1.1

## Strumline pulse every even beat after 232.
const PULSE_FIRST_BEAT := 232
const PULSE_FROM := 0.95
const PULSE_TO_PLAYER := 1.05
const PULSE_TO_OPPONENT := 1.0
const LANE_SCALE_PLAYER := 1.0
const LANE_SCALE_OPPONENT := 0.95

## Opponent lanes fly-in at beat 166.
const LANES_IN_SECONDS := 1.5
const LANES_IN_DELAY := 2.0
const LANES_HALF_ALPHA := 0.5

## HUD tween out at beat 332.
const HUD_TWEEN_DISTANCE := 250.0
const HUD_TWEEN_SECONDS := 1.75
const HUD_TWEEN_DELAY_UP := 0.25
const HUD_TWEEN_DELAY_DOWN := 0.5

## Flash.
const FLASH_SECONDS := 1.5

## boyfriend_slide.
const SLIDE_DISTANCE := 800.0
const SLIDE_SECONDS := 1.35

## ─── Exports (phone-call specific) ─────────────────────────────────────────
@export var stand_cast: Dictionary[StringName, Node] = {}
@export var stage: Node2D
@export var flash: ColorRect
@export var fade_rect: ColorRect
@export var hud_up: Array[Node] = []
@export var hud_down: Array[Node] = []
@export var cover: ColorRect
@export var intro_text: AnimatedSprite2D
@export var hud_root: Control
@export var script_bars: CanvasItem

## ─── State ──────────────────────────────────────────────────────────────────
var _hud_rest: Vector2 = Vector2.ONE
var _hud_tween: Tween
var _stood_up: bool = false
var _intro_tween: Tween


func _ready() -> void:
	super()
	if hud != null:
		_hud_rest = hud.scale
	# _first_time guard for opening — does NOT use first_time() because
	# opening() assigns absolutely off the homes read in _ready.
	opening()


func _get_stage_zoom() -> float:
	return STAGE_ZOOM


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
	for entry: Array in [
		[opponent_lanes, PULSE_TO_OPPONENT, LANE_SCALE_OPPONENT],
		[player_lanes, PULSE_TO_PLAYER, LANE_SCALE_PLAYER],
	]:
		var lanes: Control = entry[0]
		if lanes == null:
			continue
		var base: float = float(entry[2])
		lanes.scale = Vector2.ONE * base * PULSE_FROM
		create_tween().tween_property(lanes, "scale",
			Vector2.ONE * base * float(entry[1]),
			seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## ─── Per-frame ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	super(delta)
	if hud == null:
		return
	if _hud_tween != null and _hud_tween.is_running():
		centre_hud(hud)
		return
	if hud.scale.is_equal_approx(_hud_rest):
		return
	hud.scale = hud.scale.lerp(_hud_rest, minf(1.0, 3.0 * delta))
	centre_hud(hud)


## ─── Opening (onCreatePost) ────────────────────────────────────────────────
func opening() -> void:
	if cover != null:
		cover.color = Color(0.0, 0.0, 0.0, 1.0)
	if intro_text != null:
		intro_text.visible = false
		intro_text.modulate.a = 0.0
	if hud_root != null:
		hud_root.modulate.a = 0.0
	if player_lanes != null:
		player_lanes.position.x = _lane_homes[&"player"].x + SCREEN_WIDTH * FUNKIN_TO_RUBICON
		player_lanes.modulate.a = 0.0
	if opponent_lanes != null:
		opponent_lanes.position.x = _lane_homes[&"opponent"].x + SCREEN_WIDTH * FUNKIN_TO_RUBICON
		opponent_lanes.modulate.a = 0.0
	set_keys_enabled(false)


## ─── Intro text ─────────────────────────────────────────────────────────────
func intro_show_text() -> void:
	if not first_time(&"intro_show_text"):
		return
	if intro_text == null:
		return
	intro_text.visible = true
	intro_text.scale = Vector2.ONE * INTRO_TEXT_SCALE
	var frame: Texture2D = intro_text.sprite_frames.get_frame_texture(
		intro_text.animation, 0)
	if frame != null:
		intro_text.position = (Vector2(SCREEN_WIDTH, SCREEN_HEIGHT)
			- frame.get_size() * INTRO_TEXT_SCALE) * 0.5
	if _intro_tween != null:
		_intro_tween.kill()
	_intro_tween = create_tween()
	_intro_tween.tween_property(intro_text, "modulate:a", 1.0,
		INTRO_FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func intro_hide_text() -> void:
	if not first_time(&"intro_hide_text"):
		return
	if intro_text == null:
		return
	if _intro_tween != null:
		_intro_tween.kill()
	_intro_tween = create_tween()
	_intro_tween.tween_property(intro_text, "modulate:a", 0.0,
		0.6).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)


func intro_reveal() -> void:
	if not first_time(&"intro_reveal"):
		return
	if cover != null:
		create_tween().tween_property(cover, "color:a", 0.0,
			1.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## ─── HUD in/out ─────────────────────────────────────────────────────────────
func hud_in() -> void:
	if not first_time(&"hud_in"):
		return
	if hud != null:
		hud.scale = _hud_rest * HUD_IN_ZOOM
		centre_hud(hud)
		_hud_tween = create_tween()
		_hud_tween.tween_property(hud, "scale", _hud_rest, HUD_IN_SECONDS)
	for node: CanvasItem in [hud_root, player_lanes]:
		if node != null:
			create_tween().tween_property(node, "modulate:a", 1.0, HUD_IN_SECONDS)


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
	# Swap cast to standing pair.
	for key: StringName in stand_cast:
		cast[key] = stand_cast[key]
	# Swap stage props.
	if stage != null:
		_swap_props(stage)
	if hud_root != null:
		hud_root.visible = true


func _swap_props(node: Node) -> void:
	for child: Node in node.get_children():
		if child.name.begins_with("stand-"):
			child.visible = true
		elif child.name.begins_with("phone-") or child.name.begins_with("sitting-"):
			child.visible = false


## ─── Opponent lanes in ──────────────────────────────────────────────────────
func opponent_lanes_in() -> void:
	if not first_time(&"opponent_lanes_in"):
		return
	if opponent_lanes == null or not _lane_homes.has(&"player"):
		return
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(opponent_lanes, "position:x",
		_lane_homes[&"player"].x, LANES_IN_SECONDS).set_delay(LANES_IN_DELAY)
	tween.tween_property(opponent_lanes, "rotation_degrees", 0.0,
		LANES_IN_SECONDS).set_delay(LANES_IN_DELAY)
	tween.tween_property(opponent_lanes, "modulate:a", LANES_HALF_ALPHA,
		LANES_IN_SECONDS).set_delay(LANES_IN_DELAY)


## ─── Boyfriend slide ────────────────────────────────────────────────────────
func boyfriend_slide() -> void:
	if not first_time(&"boyfriend_slide"):
		return
	var tadano: Node2D = cast.get(&"boyfriend")
	if tadano == null:
		return
	create_tween().tween_property(tadano, "position:x",
		tadano.position.x + SLIDE_DISTANCE, SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## ─── Keys ───────────────────────────────────────────────────────────────────
func keys_on() -> void:
	set_keys_enabled(true)
	if script_bars != null:
		script_bars.visible = false


## ─── Fade ───────────────────────────────────────────────────────────────────
func fade_out(duration: float) -> void:
	fade_out_node(fade_rect, duration)
