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

## HUD scale state: captured at _ready, restored every frame via lerp.
## Any song can punch() the HUD and it will ease back automatically.
var _hud_rest: Vector2 = Vector2.ONE
var _hud_tween: Tween
var hud_root: Control
var hud_up: Array[Node] = []
var hud_down: Array[Node] = []


func _ready() -> void:
	if player_lanes != null:
		_lane_homes[&"player"] = player_lanes.position
	if opponent_lanes != null:
		_lane_homes[&"opponent"] = opponent_lanes.position
	if hud != null:
		_hud_rest = hud.scale
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

	# HUD scale auto-decay: after a punch, ease back to rest.
	if hud != null:
		if _hud_tween != null and _hud_tween.is_running():
			centre_hud(hud)
		elif not hud.scale.is_equal_approx(_hud_rest):
			hud.scale = hud.scale.lerp(_hud_rest, minf(1.0, 3.0 * delta))
			centre_hud(hud)


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


## ─── HUD helpers (extended) ───────────────────────────────────────────────
## Fade nodes in (e.g. hud_root + player_lanes appearing together).
func fade_in_nodes(nodes: Array[Node], duration: float = 0.35) -> void:
	for node: Node in nodes:
		if node != null and node is CanvasItem:
			create_tween().tween_property(node, "modulate:a", 1.0, duration)


## Hide lanes offscreen (opening sequence).
func park_lanes_offscreen(distance: float = 0.0) -> void:
	if distance == 0.0:
		distance = SCREEN_WIDTH * FUNKIN_TO_RUBICON
	for entry: Array in [[&"player", player_lanes], [&"opponent", opponent_lanes]]:
		var lanes: Control = entry[1]
		if lanes == null or not _lane_homes.has(entry[0]):
			continue
		lanes.position.x = _lane_homes[entry[0]].x + distance
		lanes.modulate.a = 0.0


## Position text centred on screen from a frame texture.
func centre_text_on_screen(node: Node2D, texture: Texture2D,
		scale: float = 1.0) -> void:
	if node == null or texture == null:
		return
	node.scale = Vector2.ONE * scale
	node.position = (Vector2(SCREEN_WIDTH, SCREEN_HEIGHT)
		- texture.get_size() * scale) * 0.5


## ─── Beat guard ─────────────────────────────────────────────────────────────
func first_time(beat: StringName) -> bool:
	if _ran.has(beat):
		return false
	_ran[beat] = true
	return true



## ─── Opening (cover + intro text) ──────────────────────────────────────────
## Many songs start with a black screen and optional title card.
## Call from _ready or the chart's first beat.
func setup_opening(cover: ColorRect = null, intro: Node = null,
		intro_scale: float = 0.8) -> void:
	if cover != null:
		cover.color = Color(0.0, 0.0, 0.0, 1.0)
	if intro != null:
		intro.visible = false
		if intro is CanvasItem:
			intro.modulate.a = 0.0


func fade_cover(cover: ColorRect, duration: float) -> void:
	if cover == null:
		return
	create_tween().tween_property(cover, "color:a", 0.0,
		duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func show_intro(intro: Node, duration: float = 2.5,
		scale: float = 0.8) -> void:
	if intro == null or not (intro is CanvasItem):
		return
	intro.visible = true
	if intro is Node2D:
		intro.scale = Vector2.ONE * scale
	intro.modulate.a = 0.0
	create_tween().tween_property(intro, "modulate:a", 1.0,
		duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func hide_intro(intro: Node, duration: float = 0.6) -> void:
	if intro == null or not (intro is CanvasItem):
		return
	create_tween().tween_property(intro, "modulate:a", 0.0,
		duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)


## ─── HUD in (zoom + fade) ──────────────────────────────────────────────────
## HUD appears zoomed in and eases to rest scale while fading up.
## Returns the tween so the caller can chain or guard against conflicts.
func hud_zoom_in(hud_node: CanvasLayer, rest_scale: Vector2,
		zoom: float = 1.1, duration: float = 0.35) -> Tween:
	if hud_node == null:
		return null
	hud_node.scale = rest_scale * zoom
	centre_hud(hud_node)
	var tw := create_tween()
	tw.tween_property(hud_node, "scale", rest_scale, duration)
	return tw


func fade_in_nodes(nodes: Array[Node], duration: float = 0.35) -> void:
	for node: Node in nodes:
		if node != null and node is CanvasItem:
			create_tween().tween_property(node, "modulate:a", 1.0, duration)


## ─── Cinematic bars (letterbox) ────────────────────────────────────────────
## Top/bottom bars that slide in for dramatic moments.
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
			float(entry[1]), duration) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func hide_bars(top: CanvasItem, bottom: CanvasItem,
		duration: float = 0.3) -> void:
	for bar: CanvasItem in [top, bottom]:
		if bar == null:
			continue
		create_tween().tween_property(bar, "offset_bottom", 0.0,
			duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## ─── Flash ──────────────────────────────────────────────────────────────────
## White or black screen flash. Fades from opaque to transparent.
func flash_screen(node: ColorRect, color: Color = Color.WHITE,
		duration: float = 1.5) -> void:
	if node == null:
		return
	node.color = Color(color.r, color.g, color.b, 1.0)
	create_tween().tween_property(node, "color:a", 0.0, duration)


## ─── Camera bop (SetCameraBop) ─────────────────────────────────────────────
## Changes the bumper's automatic beat-bop rate and strength.
## `bumper` is RubiconCameraBumper. intensity=0 disables the bop.
const DEFAULT_BOP := 0.015

func set_bop(bumper: Node, rate: int, intensity: float) -> void:
	if bumper == null:
		return
	bumper.bump_interval = maxi(1, rate)
	bumper.bump_amount = DEFAULT_BOP * intensity
	bumper.enabled = intensity > 0.0


## ─── Strumline pulse on beat ────────────────────────────────────────────────
## Both strumlines scale up then ease back, one beat apart.
## player_scale / opponent_scale are the REST scales (e.g. 1.05, 0.95).
## from_scale is the attack scale (e.g. 0.95).
func pulse_strumlines(player_lanes_node: Control,
		opponent_lanes_node: Control, beat_duration: float,
		player_scale: float = 1.05, opponent_scale: float = 0.95,
		from_scale: float = 0.95) -> void:
	for entry: Array in [
		[opponent_lanes_node, opponent_scale],
		[player_lanes_node, player_scale],
	]:
		var lanes: Control = entry[0]
		if lanes == null:
			continue
		var base: float = float(entry[1])
		lanes.scale = Vector2.ONE * base * from_scale
		create_tween().tween_property(lanes, "scale",
			Vector2.ONE * base, beat_duration) 			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## ─── Opponent lanes fly-in ──────────────────────────────────────────────────
## Lanes fly from offscreen, unwind rotation, settle at alpha.
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
## Tween a character's x position by a delta.
func character_slide(target_name: StringName, distance: float,
		duration: float = 1.35) -> void:
	var character: Node2D = cast.get(target_name)
	if character == null:
		return
	create_tween().tween_property(character, "position:x",
		character.position.x + distance, duration) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## ─── Character swap (mid-song) ─────────────────────────────────────────────
## Replace cast entries with new character nodes and toggle stage props.
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

## Override in subclass for per-song beat choreography.
func _on_beat() -> void:
	pass


## ═════════════════════════════════════════════════════════════════════════════
## SECTION: AnimaniaModule global gameplay (combo, ratings, opponent splash)
## These run for EVERY song, not just phone-call.
## ═════════════════════════════════════════════════════════════════════════════

## ─── Combo tracking ─────────────────────────────────────────────────────────
## Every player hit increments curNoteCombo; misses and breaks reset it.
## When the combo is high enough and few notes remain, spawnCombo() awards
## a bonus score and resets both counters.
var _cur_note_combo: int = 0
var _score_combo: int = 0

## Minimum combo to show the Full Combo sprite.
const COMBO_SPRITE_MIN := 7
## Minimum combo to show the combo number digits.
const COMBO_DIGITS_MIN := 15

## Combo bonus score formula: round(curNoteCombo * (scoreCombo / 150)).
## Called when the player switches focus away from bf (phone-call specific
## trigger) OR when a miss/break happens.


## ─── Opponent splash ────────────────────────────────────────────────────────
## Opponent notes have a 60% chance to splash AND drain 0.85% health.
## This is AnimaniaModule.spawnOpponentSplash.
func opponent_splash(lanes_node: Control, note_index: int,
		note_data: Array, health_module: Node) -> void:
	if lanes_node == null:
		return
	var index: int = int(note_index)
	if index < 0 or index >= note_data.size() or note_data[index] == null:
		return
	# Skip banned kinds.
	var note_type: String = String(note_data[index].type)
	if _is_banned(note_type):
		return
	# 60% chance.
	if randf() > OPPONENT_SPLASH_CHANCE:
		return
	# Health drain: 0.85% of max health.
	if health_module != null and health_module.has_method("get_health"):
		var current: float = health_module.get_health()
		health_module.set_health(current - 0.0085)


func _is_banned(note_type: String) -> bool:
	for kind: StringName in BANNED_NOTEKINDS:
		if String(kind) == note_type:
			return true
	return false


## ─── Focus change (doDiffFocus) ─────────────────────────────────────────────
## When the camera switches from bf to dad/gf, reset camera offset and
## optionally trigger a combo popup.
var _cur_focus: String = ""
var _cur_focus_old: String = ""

func update_focus(player_id: int) -> void:
	_cur_focus = ["bf", "dad", "gf"][player_id] if player_id < 3 else "bf"
	if _cur_focus_old != _cur_focus:
		if _cur_focus_old == "bf" and _cur_focus in ["dad", "gf"]:
			_spawn_combo_on_switch()
		if camera != null:
			camera.position_interpolate_offset = Vector2.ZERO
		_cur_focus_old = _cur_focus


## Override in subclass if you need a visual popup on focus switch.
func _spawn_combo_on_switch() -> void:
	pass


## ─── Note hit/miss hooks ────────────────────────────────────────────────────
## Call these from the note handler's signals.
## Returns the rating name ("sick", "good", "bad", "miss") for display.
func on_player_hit(lane_id: int, rating_name: String, score: int) -> void:
	_cur_note_combo += 1
	_score_combo += score


func on_player_miss() -> void:
	_cur_note_combo = 0
	_score_combo = 0


## ─── Combo bonus (spawnCombo) ───────────────────────────────────────────────
## Awards bonus score and resets counters. Call when focus switches or
## at natural breakpoints.
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
## On every beat, if the FC sprite is visible, pulse it.
## The sprite itself is song-specific (different textures per mod).
func pulse_fc_sprite(sprite: Sprite2D) -> void:
	if sprite == null or not sprite.visible:
		return
	sprite.scale = Vector2.ONE * 0.825
	create_tween().tween_property(sprite, "scale",
		Vector2.ONE * 0.9, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
