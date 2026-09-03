extends Node
## Base class for song-specific chart events shared across all Animania songs.
##
## Anything that AnimaniaModule does globally in the original mod lives here:
## camera nudge, shake, note-kind banning, opponent splash rules, character
## animation helpers, key disabling, and the one-shot beat guard.
##
## Per-song scripts extend this and add their own beat-driven choreography
## (intros, HUD anims, stage swaps, etc.) by overriding or calling the
## helpers exposed here.

## ─── Scaling ────────────────────────────────────────────────────────────────
## Funkin is 1280x720; this project is 1920x1080.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCREEN_WIDTH := 1920.0
const SCREEN_HEIGHT := 1080.0

## ─── Camera nudge (AnimaniaModule.triggerCameraMovement) ────────────────────
## Every note the CURRENTLY FOCUSED character hits shoves the camera a little
## in that note's direction, easing back via smoothLerpPrecision.
const NOTE_NUDGE := 25.0
const NUDGE_PRECISION := 0.01
const NUDGE_SECONDS := 1.0

## ─── Note-kind blacklist ────────────────────────────────────────────────────
## Kinds that drive neither animation nor camera.
const BANNED_NOTEKINDS: Array[StringName] = [
	&"noAnimation", &"noanim", &"parents-miss", &"solotime"
]

## ─── Opponent splash rule ───────────────────────────────────────────────────
## Opponent notes splash 60% of the time, at random — NOT on perfect.
const OPPONENT_SPLASH_CHANCE := 0.6

## ─── Exports ────────────────────────────────────────────────────────────────
@export var camera: Camera2D
@export var clock: Node
@export var hud: CanvasLayer
@export var player_point: Node2D
@export var opponent_point: Node2D
@export var player_lanes: Control
@export var opponent_lanes: Control
@export var cast: Dictionary[StringName, Node] = {}

## ─── Internal state ─────────────────────────────────────────────────────────
var _shake_amount: float = 0.0
var _shake_left: float = 0.0
var _nudge: Vector2 = Vector2.ZERO
var dying: bool = false
var _lane_homes: Dictionary[StringName, Vector2] = {}

## Beat guard: true the first time a named beat fires, false forever after.
var _ran: Dictionary[StringName, bool] = {}


func _ready() -> void:
	if player_lanes != null:
		_lane_homes[&"player"] = player_lanes.position
	if opponent_lanes != null:
		_lane_homes[&"opponent"] = opponent_lanes.position
	if clock != null and clock.has_signal(&"beat_change"):
		clock.beat_change.connect(_on_beat)
	# Connect lane hit signals for camera nudge.
	for entry: Array in [[player_lanes, true], [opponent_lanes, false]]:
		var lanes: Control = entry[0]
		if lanes == null:
			continue
		for lane: Node in lanes.get_children():
			if lane.has_signal(&"just_pressed"):
				lane.just_pressed.connect(_on_lane_hit.bind(lane, bool(entry[1])))


## ─── Per-frame ──────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# Shake + nudge share one offset.
	var shake := Vector2.ZERO
	if _shake_left > 0.0:
		_shake_left -= delta
		if _shake_left > 0.0:
			shake = Vector2(randf_range(-_shake_amount, _shake_amount),
				randf_range(-_shake_amount, _shake_amount))
	_nudge = _nudge.lerp(Vector2.ZERO,
		1.0 - pow(NUDGE_PRECISION, delta / NUDGE_SECONDS))
	if camera != null:
		camera.position_interpolate_offset = shake + _nudge


## ─── Camera helpers ─────────────────────────────────────────────────────────
## Instant FocusCamera (no tween).
func snap_camera(target: Vector2) -> void:
	if camera == null:
		return
	camera.position_interpolate_target = target
	camera.global_position = target


## One-shot zoom punch. scale = base * (1 + game_zoom) → eases back.
func punch(game_zoom: float, hud_zoom: float) -> void:
	if camera == null:
		return
	var base := camera.zoom
	camera.zoom = base * (1.0 + game_zoom)
	camera.set(&"zoom_interpolate_target", camera.zoom)


## Screen shake.
func shake(intensity: float, duration: float) -> void:
	_shake_amount = intensity * SCREEN_WIDTH
	_shake_left = duration


## ─── Camera nudge (triggerCameraMovement) ───────────────────────────────────
func _on_lane_hit(lane: Node, is_player: bool) -> void:
	if camera == null or is_player != _camera_is_on_player():
		return
	var index: int = int(lane.last_hit_note_index)
	var notes: Array = lane.data
	if index >= 0 and index < notes.size() and notes[index] != null:
		if BANNED_NOTEKINDS.has(StringName(notes[index].type)):
			return
	var zoom: float = maxf(0.01, camera.zoom.x)
	# Stage zoom is read from the level's metadata or set per-song.
	var stage_zoom: float = _get_stage_zoom()
	var amount: float = NOTE_NUDGE / zoom * (stage_zoom * 0.5) * FUNKIN_TO_RUBICON
	match int(lane.lane_id):
		0: _nudge = Vector2(-amount, 0.0)
		1: _nudge = Vector2(0.0, amount)
		2: _nudge = Vector2(0.0, -amount)
		3: _nudge = Vector2(amount, 0.0)


func _camera_is_on_player() -> bool:
	if camera == null or player_point == null or opponent_point == null:
		return true
	var target: Vector2 = camera.position_interpolate_target
	return target.distance_squared_to(player_point.global_position) \
		<= target.distance_squared_to(opponent_point.global_position)


## Override per-song if stage zoom varies. Default 0.65 (phoneCallStreet).
func _get_stage_zoom() -> float:
	return 0.65


## ─── Character animation helpers ────────────────────────────────────────────
## PlayAnimation. `force: false` means "play but don't restart if already running."
func play_character_animation(target: StringName, animation: StringName,
		force: bool) -> void:
	var character: Node = cast.get(target)
	if character == null:
		push_warning("PlayAnimation: %s not in cast" % target)
		return
	if not character.animation_player.has_animation(animation):
		var converted := StringName(String(animation).to_snake_case())
		if not character.animation_player.has_animation(converted):
			push_warning("PlayAnimation: %s has no anim '%s'" % [target, animation])
			return
		animation = converted
	if not force and character.animation_player.current_animation == animation:
		return
	character.state = character.CharacterState.STATE_OVERRIDE
	character.play(animation, true)
	var player: AnimationPlayer = character.animation_player
	if player.animation_finished.is_connected(_release):
		player.animation_finished.disconnect(_release)
	player.animation_finished.connect(_release.bind(character), CONNECT_ONE_SHOT)


## SetProperty <character>.idleSuffix — remaps dancing + sing animations.
func set_idle_suffix(target: StringName, suffix: String) -> void:
	var character: Node = cast.get(target)
	if character == null:
		push_warning("SetProperty: %s not in cast" % target)
		return
	var remapped: Dictionary[StringName, StringName] = {}
	for alias: StringName in character.animations:
		var base: StringName = character.animations[alias]
		var suffixed := StringName("%s%s" % [base, suffix.replace("-", "_")])
		remapped[alias] = suffixed if character.animation_player.has_animation(suffixed) \
			else base
	character.animations = remapped
	var dancing: Array[StringName] = []
	for animation: StringName in character.dancing_animations:
		var suffixed := StringName("%s%s" % [animation, suffix.replace("-", "_")])
		dancing.append(suffixed if character.animation_player.has_animation(suffixed)
			else animation)
	character.dancing_animations = dancing


func _release(_animation: StringName, character: Node) -> void:
	if not is_instance_valid(character):
		return
	if character.state == character.CharacterState.STATE_OVERRIDE:
		character.state = character.CharacterState.STATE_DANCING


## ─── Key disable ────────────────────────────────────────────────────────────
func set_keys_enabled(enabled: bool) -> void:
	if player_lanes != null:
		player_lanes.disable_inputs = not enabled


## ─── Fade ───────────────────────────────────────────────────────────────────
func fade_out_node(node: ColorRect, duration: float) -> void:
	if node == null:
		return
	node.color = Color(0.0, 0.0, 0.0, 0.0)
	create_tween().tween_property(node, "color:a", 1.0, duration)


## ─── HUD helpers ────────────────────────────────────────────────────────────
## Centre the HUD so scale changes happen from the middle.
func centre_hud(hud_node: CanvasLayer) -> void:
	if hud_node == null:
		return
	var screen_size: Vector2 = hud_node.get_viewport().get_visible_rect().size
	hud_node.offset = -screen_size * 0.5 * (hud_node.scale - Vector2.ONE)


func tween_hud_out(nodes: Array[Node], distance: float, delay: float,
		duration: float) -> void:
	for node: Node in nodes:
		if node == null or not (node is CanvasItem):
			continue
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(node, "position:y", node.position.y + distance,
			duration).set_delay(delay).set_trans(Tween.TRANS_QUINT) \
			.set_ease(Tween.EASE_IN)
		tween.tween_property(node, "modulate:a", 0.0,
			duration).set_delay(delay)


## ─── Beat guard ─────────────────────────────────────────────────────────────
func first_time(beat: StringName) -> bool:
	if _ran.has(beat):
		return false
	_ran[beat] = true
	return true


## Override in subclass for per-song beat choreography.
func _on_beat() -> void:
	pass
