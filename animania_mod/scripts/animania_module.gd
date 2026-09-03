extends Node
## Global Animania gameplay module — runs for every song.
##
## Ported from AnimaniaModule.hx: the Module that intercepts PlayState
## and injects Animania's HUD, combo tracking, camera nudge, opponent
## splash, rating popups, and focus-change logic.
##
## This is an autoload (first in the list) so it captures errors from
## all other autoloads and scripts.

## ─── Constants ──────────────────────────────────────────────────────────────

## Scaling: Funkin is 1280x720; this project is 1920x1080.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCREEN_WIDTH := 1920.0
const SCREEN_HEIGHT := 1080.0

## Note kinds that drive neither animation nor camera.
const BANNED_NOTEKINDS: Array[StringName] = [
	&"noAnimation", &"noanim", &"parents-miss", &"solotime"
]

## Opponent notes splash 60% of the time, at random.
const OPPONENT_SPLASH_CHANCE := 0.6

## Camera nudge magnitude and decay.
const CAM_NUDGE := 25.0
const NUDGE_PRECISION := 0.01
const NUDGE_SECONDS := 1.0

## Default per-bop game zoom (SetCameraBop intensity multiplier).
const DEFAULT_BOP := 0.015

## Minimum combo to show the Full Combo sprite.
const COMBO_SPRITE_MIN := 7
## Minimum combo to show combo number digits.
const COMBO_DIGITS_MIN := 15
## Combo bonus: round(curNoteCombo * (scoreCombo / 150)).


## ─── State ──────────────────────────────────────────────────────────────────

## The camera, HUD, and cast are set per-song by the song's events script.
var camera: Camera2D
var hud: CanvasLayer
var cast: Dictionary[StringName, Node] = {}

## Note controllers set per-song.
var player_lanes: Control
var opponent_lanes: Control

## Camera nudge state (shared offset with shake).
var _nudge: Vector2 = Vector2.ZERO
var _shake_amount: float = 0.0
var _shake_left: float = 0.0

## Focus tracking.
var _cur_focus: String = ""
var _cur_focus_old: String = ""

## Combo tracking.
var _cur_note_combo: int = 0
var _score_combo: int = 0

## HUD scale state.
var _hud_rest: Vector2 = Vector2.ONE
var _hud_tween: Tween
var hud_root: Control
var hud_up: Array[Node] = []
var hud_down: Array[Node] = []

## Stage zoom (set per-song).
var _stage_zoom: float = 0.65

## Lane home positions.
var _lane_homes: Dictionary[StringName, Vector2] = {}

## Full Combo sprite (set per-song if the mod uses one).
var _fc_sprite: Sprite2D


## ─── Per-frame ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Camera nudge decay.
	_nudge = _nudge.lerp(Vector2.ZERO,
		1.0 - pow(NUDGE_PRECISION, delta / NUDGE_SECONDS))

	# Shake + nudge share one offset.
	var shake := Vector2.ZERO
	if _shake_left > 0.0:
		_shake_left -= delta
		if _shake_left > 0.0:
			shake = Vector2(randf_range(-_shake_amount, _shake_amount),
				randf_range(-_shake_amount, _shake_amount))

	if camera != null:
		camera.position_interpolate_offset = shake + _nudge

	# HUD scale auto-decay.
	if hud != null:
		if _hud_tween != null and _hud_tween.is_running():
			_centre_hud()
		elif not hud.scale.is_equal_approx(_hud_rest):
			hud.scale = hud.scale.lerp(_hud_rest, minf(1.0, 3.0 * delta))
			_centre_hud()


## ─── Setup (called by song events script) ───────────────────────────────────

func setup(cam: Camera2D, h: CanvasLayer, p_lanes: Control,
		o_lanes: Control, stage_zoom: float = 0.65) -> void:
	camera = cam
	hud = h
	player_lanes = p_lanes
	opponent_lanes = o_lanes
	_stage_zoom = stage_zoom
	if hud != null:
		_hud_rest = hud.scale
	if player_lanes != null:
		_lane_homes[&"player"] = player_lanes.position
	if opponent_lanes != null:
		_lane_homes[&"opponent"] = opponent_lanes.position
	# Connect lane hit signals for camera nudge.
	for entry: Array in [[player_lanes, true], [opponent_lanes, false]]:
		var lanes: Control = entry[0]
		if lanes == null:
			continue
		for lane: Node in lanes.get_children():
			if lane.has_signal(&"just_pressed"):
				lane.just_pressed.connect(_on_lane_hit.bind(lane, bool(entry[1])))


## ─── Camera helpers ─────────────────────────────────────────────────────────

## Instant FocusCamera (no tween).
func snap_camera(target: Vector2) -> void:
	if camera == null:
		return
	camera.position_interpolate_target = target
	camera.global_position = target


## One-shot zoom punch.
func punch(game_zoom: float, hud_zoom: float = 0.0) -> void:
	if camera == null:
		return
	camera.zoom = camera.zoom * (1.0 + game_zoom)
	camera.set(&"zoom_interpolate_target", camera.zoom)


## Screen shake.
func shake_screen(intensity: float, duration: float) -> void:
	_shake_amount = intensity * SCREEN_WIDTH
	_shake_left = duration


## Camera nudge (triggerCameraMovement). Direction 0-3: left/down/up/right.
func _on_lane_hit(lane: Node, is_player: bool) -> void:
	if camera == null:
		return
	# Only nudge when the camera is on the hitting side.
	if is_player != _camera_is_on_player():
		return
	# Skip banned note kinds.
	var index: int = int(lane.last_hit_note_index)
	var notes: Array = lane.data
	if index >= 0 and index < notes.size() and notes[index] != null:
		if _is_banned(String(notes[index].type)):
			return
	var zoom: float = maxf(0.01, camera.zoom.x)
	var amount: float = CAM_NUDGE / zoom * (_stage_zoom * 0.5) * FUNKIN_TO_RUBICON
	match int(lane.lane_id):
		0: _nudge = Vector2(-amount, 0.0)
		1: _nudge = Vector2(0.0, amount)
		2: _nudge = Vector2(0.0, -amount)
		3: _nudge = Vector2(amount, 0.0)


func _camera_is_on_player() -> bool:
	if camera == null or player_lanes == null or opponent_lanes == null:
		return true
	# Simple: which side's notes are closer to the camera target?
	if player_point == null or opponent_point == null:
		return true
	var target: Vector2 = camera.position_interpolate_target
	return target.distance_squared_to(player_point.global_position) \
		<= target.distance_squared_to(opponent_point.global_position)


## Player point / opponent point — set per-song.
var player_point: Node2D
var opponent_point: Node2D


## ─── Character animation helpers ────────────────────────────────────────────

## PlayAnimation. force=false means "play but don't restart if already running."
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


## SetProperty <character>.idleSuffix.
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


## ─── HUD helpers ────────────────────────────────────────────────────────────

func _centre_hud() -> void:
	if hud == null:
		return
	var screen_size: Vector2 = hud.get_viewport().get_visible_rect().size
	hud.offset = -screen_size * 0.5 * (hud.scale - Vector2.ONE)


func hud_zoom_in(zoom: float = 1.1, duration: float = 0.35) -> void:
	if hud == null:
		return
	hud.scale = _hud_rest * zoom
	_centre_hud()
	_hud_tween = create_tween()
	_hud_tween.tween_property(hud, "scale", _hud_rest, duration)


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


func fade_in_nodes(nodes: Array[Node], duration: float = 0.35) -> void:
	for node: Node in nodes:
		if node != null and node is CanvasItem:
			create_tween().tween_property(node, "modulate:a", 1.0, duration)


func park_lanes_offscreen(distance: float = 0.0) -> void:
	if distance == 0.0:
		distance = SCREEN_WIDTH * FUNKIN_TO_RUBICON
	for entry: Array in [[&"player", player_lanes], [&"opponent", opponent_lanes]]:
		var lanes: Control = entry[1]
		if lanes == null or not _lane_homes.has(entry[0]):
			continue
		lanes.position.x = _lane_homes[entry[0]].x + distance
		lanes.modulate.a = 0.0


## ─── Camera bop (SetCameraBop) ─────────────────────────────────────────────

func set_bop(bumper: Node, rate: int, intensity: float) -> void:
	if bumper == null:
		return
	bumper.bump_interval = maxi(1, rate)
	bumper.bump_amount = DEFAULT_BOP * intensity
	bumper.enabled = intensity > 0.0


## ─── Strumline pulse on beat ────────────────────────────────────────────────

func pulse_strumlines(player_scale: float = 1.05, opponent_scale: float = 0.95,
		from_scale: float = 0.95, beat_duration: float = 0.5) -> void:
	for entry: Array in [
		[opponent_lanes, opponent_scale],
		[player_lanes, player_scale],
	]:
		var lanes: Control = entry[0]
		if lanes == null:
			continue
		var base: float = float(entry[1])
		lanes.scale = Vector2.ONE * base * from_scale
		create_tween().tween_property(lanes, "scale",
			Vector2.ONE * base, beat_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## ─── Opponent lanes fly-in ──────────────────────────────────────────────────

func lanes_fly_in(lanes: Control, target_x: float,
		duration: float = 1.5, delay: float = 0.0,
		alpha: float = 0.5) -> void:
	if lanes == null:
		return
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(lanes, "position:x", target_x,
		duration).set_delay(delay)
	tween.tween_property(lanes, "rotation_degrees", 0.0,
		duration).set_delay(delay)
	tween.tween_property(lanes, "modulate:a", alpha,
		duration).set_delay(delay)


## ─── Character slide ────────────────────────────────────────────────────────

func character_slide(target_name: StringName, distance: float,
		duration: float = 1.35) -> void:
	var character: Node2D = cast.get(target_name)
	if character == null:
		return
	create_tween().tween_property(character, "position:x",
		character.position.x + distance, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## ─── Character swap (mid-song) ─────────────────────────────────────────────

func swap_characters(new_cast: Dictionary[StringName, Node],
		stage: Node = null, show_prefix: String = "stand-",
		hide_prefixes: Array[String] = ["phone-", "sitting-"]) -> void:
	for key: StringName in new_cast:
		cast[key] = new_cast[key]
	if stage != null:
		for child: Node in stage.get_children():
			if child.name.begins_with(show_prefix):
				child.visible = true
			for hp: String in hide_prefixes:
				if child.name.begins_with(hp):
					child.visible = false


## ─── Focus change (doDiffFocus) ─────────────────────────────────────────────

func update_focus(player_id: int) -> void:
	_cur_focus = ["bf", "dad", "gf"][player_id] if player_id < 3 else "bf"
	if _cur_focus_old != _cur_focus:
		if _cur_focus_old == "bf" and _cur_focus in ["dad", "gf"]:
			_spawn_combo_on_switch()
		if camera != null:
			camera.position_interpolate_offset = Vector2.ZERO
		_cur_focus_old = _cur_focus


func _spawn_combo_on_switch() -> void:
	pass


## ─── Combo tracking ─────────────────────────────────────────────────────────

func on_player_hit(_lane_id: int, _rating_name: String, score: int) -> void:
	_cur_note_combo += 1
	_score_combo += score


func on_player_miss() -> void:
	_cur_note_combo = 0
	_score_combo = 0


func award_combo_bonus(note_controller: Node) -> void:
	if _cur_note_combo <= COMBO_SPRITE_MIN:
		return
	if note_controller == null:
		return
	var bonus: int = roundi(_cur_note_combo * (_score_combo / 150.0))
	if note_controller.has_method("set"):
		note_controller.performance_score_value += maxi(0, bonus - roundi(_score_combo / 150.0))
	_score_combo = 0
	_cur_note_combo = 0


## ─── Full Combo sprite beat pulse ───────────────────────────────────────────

func pulse_fc_sprite(sprite: Sprite2D = null) -> void:
	if sprite == null:
		sprite = _fc_sprite
	if sprite == null or not sprite.visible:
		return
	sprite.scale = Vector2.ONE * 0.825
	create_tween().tween_property(sprite, "scale",
		Vector2.ONE * 0.9, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## ─── Opponent splash ────────────────────────────────────────────────────────

func opponent_splash(note_index: int, note_data: Array,
		health_module: Node = null) -> void:
	var index: int = int(note_index)
	if index < 0 or index >= note_data.size() or note_data[index] == null:
		return
	if _is_banned(String(note_data[index].type)):
		return
	if randf() > OPPONENT_SPLASH_CHANCE:
		return
	if health_module != null and health_module.has_method("get_health"):
		health_module.set_health(health_module.get_health() - 0.0085)


## ─── Utilities ──────────────────────────────────────────────────────────────

func _is_banned(note_type: String) -> bool:
	for kind: StringName in BANNED_NOTEKINDS:
		if String(kind) == note_type:
			return true
	return false


## Beat guard: true the first time, false after.
var _ran: Dictionary[StringName, bool] = {}

func first_time(beat: StringName) -> bool:
	if _ran.has(beat):
		return false
	_ran[beat] = true
	return true


func fade_out_node(node: ColorRect, duration: float) -> void:
	if node == null:
		return
	node.color = Color(0.0, 0.0, 0.0, 0.0)
	create_tween().tween_property(node, "color:a", 1.0, duration)


func flash_screen(node: ColorRect, color: Color = Color.WHITE,
		duration: float = 1.5) -> void:
	if node == null:
		return
	node.color = Color(color.r, color.g, color.b, 1.0)
	create_tween().tween_property(node, "color:a", 0.0, duration)


func show_bars(top: CanvasItem, bottom: CanvasItem,
		height: float = 100.0, duration: float = 0.3) -> void:
	for entry: Array in [[top, -height], [bottom, height]]:
		var bar: CanvasItem = entry[0]
		if bar == null:
			continue
		bar.visible = true
		if bar is Control:
			bar.offset_top = 0.0 if entry[1] < 0 else 0.0
		create_tween().tween_property(bar, "offset_bottom",
			float(entry[1]), duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func hide_bars(top: CanvasItem, bottom: CanvasItem,
		duration: float = 0.3) -> void:
	for bar: CanvasItem in [top, bottom]:
		if bar == null:
			continue
		create_tween().tween_property(bar, "offset_bottom", 0.0,
			duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
