extends Node
## HQ Note Mechanics — song-level handlers for the mod's Bullet/Timestop
## notes. The metadata (hq_note_metadata.gd) routes note_hit() here through
## the "hq_note_mechanics" group, so this node can live in any song scene
## with the exported paths pointing at its own tree.
##
## Implements, from the mod's Bullet Note.hx / Timestop Note.hx /
## StatusEffects.hx:
## - bullet hit: dodge animation on the player + Homura's shoot + shell/shield
## - bullet miss: hurt-short anim, 0.10 health damage, 5s bleed (drains
##   0.085 * stacks per second), InstantKillMechanics gauntlet mod kills
## - timestop hit: 1.5s freeze (inputs off, vocals muted, grey overlay)

@export var health_path: NodePath
@export var player_controller_path: NodePath
@export var boyfriend_path: NodePath
@export var opponent_path: NodePath
@export var vocals_player_path: NodePath
@export var vocals_opponent_path: NodePath

const TIMESTOP_SECONDS := 1.0
const BLEED_DRAIN_PER_STACK := 0.085

var _health: Node
var _player_controller: Node
var _boyfriend: Node
var _opponent: Node
var _vocals_player: AudioStreamPlayer
var _vocals_opponent: AudioStreamPlayer

var _timestop_left: float = -1.0
var _bleed_left: float = -1.0
var _bleed_stack: int = 0
var _timestop_overlay: ColorRect
var _ui_layer: CanvasLayer

const DODGE_ANIMS: Array[StringName] = [&"dodgeLEFT", &"dodgeDOWN", &"dodgeUP", &"dodgeRIGHT"]


func _ready() -> void:
	add_to_group(&"hq_note_mechanics")
	if health_path != NodePath():
		_health = get_node_or_null(health_path)
	if player_controller_path != NodePath():
		_player_controller = get_node_or_null(player_controller_path)
	if boyfriend_path != NodePath():
		_boyfriend = get_node_or_null(boyfriend_path)
	if opponent_path != NodePath():
		_opponent = get_node_or_null(opponent_path)
	if vocals_player_path != NodePath():
		_vocals_player = get_node_or_null(vocals_player_path) as AudioStreamPlayer
	if vocals_opponent_path != NodePath():
		_vocals_opponent = get_node_or_null(vocals_opponent_path) as AudioStreamPlayer


func _process(delta: float) -> void:
	if _timestop_left >= 0.0:
		_timestop_left = maxf(_timestop_left - delta, 0.0)
		if _timestop_left == 0.0:
			_end_timestop()

	if _bleed_left >= 0.0:
		_bleed_left = maxf(_bleed_left - delta, 0.0)
		_bleed_stack = ceili(_bleed_left / 5.0)
		if _health != null and float(_health.get("health")) >= 0.01:
			_health.health = float(_health.health) - (BLEED_DRAIN_PER_STACK * _bleed_stack * delta)
		if _bleed_left == 0.0:
			_bleed_stack = 0


## Bullet note was hit: dodge, shoot, shell + shield FX.
func _hq_bullet_hit(direction: int) -> void:
	if _boyfriend != null and direction >= 0 and direction < DODGE_ANIMS.size():
		_play_char_anim(_boyfriend, [DODGE_ANIMS[direction], &"bf_dodge_start", &"bf_dodge_loop"])
	if _opponent != null:
		_play_char_anim(_opponent, [&"homura-base_shoot", &"shoot"])
	_spawn_fx(&"bullet-shot", direction, true)
	_spawn_fx(&"bullet-hit", direction, false)


## Bullet note was missed: hurt, damage, bleed, optional instant kill.
func _hq_bullet_miss() -> void:
	if _health != null:
		_health.health = float(_health.health) - 10.0
	_bleed_left = maxf(_bleed_left, 0.0) + 5.0
	_bleed_stack = ceili(_bleed_left / 5.0)
	if _boyfriend != null:
		_play_char_anim(_boyfriend, [&"hurt-shot", &"bf_shaking_idle"])
	if HQSaves.cur_gauntlet_mods.has("InstantKillMechanics"):
		_kill_player()


## Timestop note was pressed: freeze the song briefly.
func _hq_timestop_hit() -> void:
	_timestop_left = TIMESTOP_SECONDS
	if _opponent != null:
		_play_char_anim(_opponent, [&"homura-base_timestop", &"timestop"])
	if _player_controller != null:
		_player_controller.disable_inputs = true
	if _vocals_player != null and _vocals_player.playing:
		_vocals_player.volume_db = -80.0
	if _vocals_opponent != null and _vocals_opponent.playing:
		_vocals_opponent.volume_db = -80.0
	_show_timestop_overlay()


func _end_timestop() -> void:
	if _player_controller != null:
		_player_controller.disable_inputs = false
	if _vocals_player != null:
		_vocals_player.volume_db = 0.0
	if _vocals_opponent != null:
		_vocals_opponent.volume_db = 0.0
	if _timestop_overlay != null and is_instance_valid(_timestop_overlay):
		var tw := create_tween()
		tw.tween_property(_timestop_overlay, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): _timestop_overlay.queue_free())
	_timestop_overlay = null


func _show_timestop_overlay() -> void:
	if _timestop_overlay != null and is_instance_valid(_timestop_overlay):
		return
	if _ui_layer == null:
		_ui_layer = CanvasLayer.new()
		_ui_layer.layer = 90
		add_child(_ui_layer)
	_timestop_overlay = ColorRect.new()
	_timestop_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_timestop_overlay.color = Color(0.35, 0.35, 0.42, 0.55)
	_timestop_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_timestop_overlay)
	var label := Label.new()
	label.text = "TIME FROZEN"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 72)
	label.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0, 0.9))
	label.set_anchors_preset(Control.PRESET_CENTER)
	_timestop_overlay.add_child(label)


func _kill_player() -> void:
	if _health != null:
		var min_health: Variant = _health.get("min_health")
		_health.health = float(min_health) if min_health != null else 0.0


## Small cosmetic pop next to the receptor: a shell flies off on a dodge, a
## shield flat-pops on a hit.
func _spawn_fx(tex_name: StringName, direction: int, is_shell: bool) -> void:
	var path := "res://holyquintet_mod/source/images/game/mechanics/homura/%s.png" % tex_name
	if not ResourceLoader.exists(path):
		return
	if _ui_layer == null:
		_ui_layer = CanvasLayer.new()
		_ui_layer.layer = 90
		add_child(_ui_layer)
	var tex: Texture2D = load(path)
	var fx := TextureRect.new()
	fx.texture = tex
	fx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var base := _lane_anchor(direction)
	fx.position = base - tex.get_size() / 2.0
	fx.z_index = 5
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(fx)

	if is_shell:
		fx.pivot_offset = tex.get_size() / 2.0
		fx.rotation_degrees = 0.0
		var vel := Vector2(-250.0 if randf() < 0.5 else 250.0, -550.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(fx, "position", fx.position + vel, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(fx, "rotation_degrees", -500.0, 0.6)
		tw.chain().tween_property(fx, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): fx.queue_free())
	else:
		fx.rotation_degrees = -5.0 if randf() < 0.5 else 5.0
		fx.pivot_offset = tex.get_size() / 2.0
		fx.scale = Vector2(1.1, 1.1)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(fx, "scale", Vector2(0.9, 0.9), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tw.tween_property(fx, "rotation_degrees", 0.0, 0.25).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(fx, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_IN).set_delay(0.1)
		tw.tween_callback(func(): fx.queue_free())


func _lane_anchor(direction: int) -> Vector2:
	if _player_controller == null:
		return Vector2(480 + direction * 150, 850)
	var lane := _player_controller.get_node_or_null("Lane%d" % direction)
	if lane == null:
		lane = _player_controller.get_node_or_null("Lane")
	if lane is Control:
		var c := lane as Control
		return c.get_global_rect().get_center()
	return Vector2(480 + direction * 150, 850)


## Plays the first animation a character actually has, accepting both the
## mod's bare names ("shoot") and the port's prefixed library names
## ("homura-base_shoot"). Returns without error when neither exists.
func _play_char_anim(node: Node, candidates: Array[StringName]) -> void:
	if node == null:
		return
	var anim_player: Variant = node.get("animation_player")
	for anim: StringName in candidates:
		if anim_player != null and anim_player.has_animation(anim):
			node.play(anim)
			return
