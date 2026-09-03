extends "res://animania_mod/scripts/song_events.gd"
## Phone-call specific chart events.
##
## Extends song_events.gd (chart events) and uses AnimaniaModule (autoload)
## for global gameplay. This script only handles phone-call choreography.

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
const PULSE_TO_PLAYER := 1.05
const PULSE_TO_OPPONENT := 1.0
const PULSE_FROM := 0.95
const LANES_IN_SECONDS := 1.5
const LANES_IN_DELAY := 2.0
const LANES_HALF_ALPHA := 0.5
const HUD_TWEEN_DISTANCE := 250.0
const HUD_TWEEN_SECONDS := 1.75
const HUD_TWEEN_DELAY_UP := 0.25
const HUD_TWEEN_DELAY_DOWN := 0.5
const SLIDE_DISTANCE := 800.0
const SLIDE_SECONDS := 1.35

## ─── Exports ────────────────────────────────────────────────────────────────
@export var stand_cast: Dictionary[StringName, Node] = {}
@export var stage: Node2D
@export var bumper: Node
@export var cover: ColorRect
@export var intro_text: AnimatedSprite2D
@export var script_bars: CanvasItem
@export var hud_root_node: Control
@export var hud_up_nodes: Array[Node] = []
@export var hud_down_nodes: Array[Node] = []

var _intro_tween: Tween


func _ready() -> void:
	# Register with the global module.
	AnimaniaModule.setup(camera, hud, player_lanes, opponent_lanes, STAGE_ZOOM)
	AnimaniaModule.hud_root = hud_root_node
	AnimaniaModule.hud_up = hud_up_nodes
	AnimaniaModule.hud_down = hud_down_nodes
	AnimaniaModule.cast = cast
	AnimaniaModule.player_point = player_point
	AnimaniaModule.opponent_point = opponent_point
	# Setup opening.
	_setup_opening()
	# Connect beat.
	if clock != null and clock.has_signal(&"beat_change"):
		clock.beat_change.connect(_on_beat)


func _setup_opening() -> void:
	if cover != null:
		cover.color = Color(0.0, 0.0, 0.0, 1.0)
	if intro_text != null:
		intro_text.visible = false
		intro_text.modulate.a = 0.0
	if hud_root_node != null:
		hud_root_node.modulate.a = 0.0
	AnimaniaModule.park_lanes_offscreen()
	AnimaniaModule.set_keys_enabled(false)


## ─── Per-frame ──────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	# HUD decay is handled by AnimaniaModule._process.


## ─── Beat choreography ──────────────────────────────────────────────────────

func _on_beat() -> void:
	if AnimaniaModule.dying or clock == null:
		return
	var beat: int = floori(clock.time_beat)
	if beat <= PULSE_FIRST_BEAT or beat % 2 != 0:
		return
	var changes: Array[RubiconTimeChange] = clock.get_time_changes()
	var seconds: float = (RubiconTimeChange.get_millisecond_at_beat(changes, beat + 1)
		- RubiconTimeChange.get_millisecond_at_beat(changes, beat)) / 1000.0
	if seconds <= 0.0:
		return
	AnimaniaModule.pulse_strumlines(PULSE_TO_PLAYER, PULSE_TO_OPPONENT,
		PULSE_FROM, seconds)


## ─── Chart events (phone-call specific) ─────────────────────────────────────

func intro_show_text() -> void:
	if not AnimaniaModule.first_time(&"intro_show_text") or intro_text == null:
		return
	intro_text.visible = true
	var frame: Texture2D = intro_text.sprite_frames.get_frame_texture(
		intro_text.animation, 0)
	if frame != null:
		intro_text.scale = Vector2.ONE * INTRO_TEXT_SCALE
		intro_text.position = (Vector2(AnimaniaModule.SCREEN_WIDTH,
			AnimaniaModule.SCREEN_HEIGHT)
			- frame.get_size() * INTRO_TEXT_SCALE) * 0.5
	if _intro_tween != null:
		_intro_tween.kill()
	_intro_tween = create_tween()
	_intro_tween.tween_property(intro_text, "modulate:a", 1.0,
		INTRO_FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func intro_hide_text() -> void:
	if not AnimaniaModule.first_time(&"intro_hide_text"):
		return
	if intro_text != null:
		create_tween().tween_property(intro_text, "modulate:a", 0.0,
			0.6).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)


func intro_reveal() -> void:
	if not AnimaniaModule.first_time(&"intro_reveal"):
		return
	if cover != null:
		create_tween().tween_property(cover, "color:a", 0.0,
			1.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hud_in() -> void:
	if not AnimaniaModule.first_time(&"hud_in"):
		return
	AnimaniaModule.hud_zoom_in(HUD_IN_ZOOM, HUD_IN_SECONDS)
	AnimaniaModule.fade_in_nodes([hud_root_node, player_lanes], HUD_IN_SECONDS)


func hud_out() -> void:
	if not AnimaniaModule.first_time(&"hud_out"):
		return
	var distance: float = HUD_TWEEN_DISTANCE * AnimaniaModule.FUNKIN_TO_RUBICON
	AnimaniaModule.tween_hud_out(hud_up_nodes, -distance,
		HUD_TWEEN_DELAY_UP, HUD_TWEEN_SECONDS)
	AnimaniaModule.tween_hud_out(hud_down_nodes, distance,
		HUD_TWEEN_DELAY_DOWN, HUD_TWEEN_SECONDS)


func stand_up() -> void:
	if not AnimaniaModule.first_time(&"stand_up"):
		return
	AnimaniaModule.swap_characters(stand_cast, stage)
	if hud_root_node != null:
		hud_root_node.visible = true


func opponent_lanes_in() -> void:
	if not AnimaniaModule.first_time(&"opponent_lanes_in"):
		return
	if opponent_lanes == null or not AnimaniaModule._lane_homes.has(&"player"):
		return
	AnimaniaModule.lanes_fly_in(opponent_lanes,
		AnimaniaModule._lane_homes[&"player"].x,
		LANES_IN_SECONDS, LANES_IN_DELAY, LANES_HALF_ALPHA)


func boyfriend_slide() -> void:
	if not AnimaniaModule.first_time(&"boyfriend_slide"):
		return
	AnimaniaModule.character_slide(&"boyfriend", SLIDE_DISTANCE, SLIDE_SECONDS)


func keys_on() -> void:
	AnimaniaModule.set_keys_enabled(true)
	if script_bars != null:
		script_bars.visible = false


func fade_out(duration: float) -> void:
	AnimaniaModule.fade_out_node(fade_rect, duration)
