extends Node
## The chart events that are actions rather than values.
##
## Most of what the chart does to the camera - FocusCamera, ZoomCamera, CinematicBars - is
## a target being tweened, so it bakes into a value track and needs no code. These do not:
##
##   * AddCameraZoom is a one-shot punch. RubiconCameraBumper's own bump is `zoom +=`, and
##     the camera's _process eases it back out, so a punch is that same one line fired off
##     the animation instead of off the beat. It is not a setting - the giveaway is that
##     the first of the twelve is 0.05 at 6.5s, in the stretch where SetCameraBop has the
##     automatic bop switched off, which is a manual accent where the automatic one cannot
##     reach.
##   * SetCameraBop changes the bumper's rate and strength for everything after it.
##   * PlayAnimation makes a character play something the note chart would not.
##   * SetProperty boyfriend.idleSuffix swaps tadano onto his whole "-alt" pose set for the
##     rest of the song - which is what all those alt animations in his atlas are for.
##
## They arrive as method-track keys on the level clock's animation.

## camGame.flash(FlxColor.WHITE, 1.5) in standUP().
const FLASH_SECONDS := 1.5

## Funkin's default per-bop game zoom. SetCameraBop's `intensity` is a multiplier on it,
## which is why the chart's AddCameraZoom events mostly carry this exact number.
const DEFAULT_BOP := 0.015

@export var camera: Camera2D
@export var bumper: Node
## The UI canvas, for the HUD half of a punch.
@export var hud: CanvasLayer
## The chart names characters the way Funkin does: "boyfriend"/"bf", "dad", "gf".
@export var cast: Dictionary[StringName, Node] = {}
## The two characters standUP() swaps in, and the phone-call pair it swaps out.
@export var stand_cast: Dictionary[StringName, Node] = {}
@export var stage: Node2D
## A full-screen white ColorRect for camGame.flash.
@export var flash: ColorRect

var _hud_rest: Vector2 = Vector2.ONE
var _stood_up: bool = false


func _ready() -> void:
	if hud != null:
		_hud_rest = hud.scale


## AddCameraZoom. `hud_zoom` is applied to the UI canvas about the middle of the screen -
## a CanvasLayer scales from its top-left corner, so scaling alone would slide the whole
## HUD up and to the left instead of pulsing it in place.
func punch(game_zoom: float, hud_zoom: float) -> void:
	if camera != null:
		camera.zoom += Vector2.ONE * game_zoom

	if hud == null:
		return
	var screen: Vector2 = Vector2(hud.get_viewport().get_visible_rect().size)
	hud.scale = _hud_rest + Vector2.ONE * hud_zoom
	hud.offset = -screen * 0.5 * (hud.scale - Vector2.ONE)


## SetCameraBop. `rate` is in beats.
func set_bop(rate: int, intensity: float) -> void:
	if bumper == null:
		return
	bumper.bump_interval = maxi(1, rate)
	bumper.bump_amount = DEFAULT_BOP * intensity
	bumper.enabled = intensity > 0.0


## The HUD punch has to decay the way the camera's does; the camera gets that free from
## RubiconInterpolatedCamera2D's own lerp, and the CanvasLayer has no equivalent.
func _process(delta: float) -> void:
	if hud == null or hud.scale.is_equal_approx(_hud_rest):
		return

	hud.scale = hud.scale.lerp(_hud_rest, minf(1.0, 3.0 * delta))
	var screen: Vector2 = Vector2(hud.get_viewport().get_visible_rect().size)
	hud.offset = -screen * 0.5 * (hud.scale - Vector2.ONE)


## PlayAnimation. Funkin passes the event's `force` straight into
## playAnimation(name, restart, ...) as RESTART - it is not a condition on whether to play
## at all. So `force: false` means "play it, but leave it alone if it is already running",
## which is what the chart's two `breath` events want and what a stricter reading would
## have thrown away.
func play_character_animation(target: StringName, animation: StringName, force: bool) -> void:
	var character: Node = cast.get(target)
	if character == null:
		push_warning("PlayAnimation nombra a %s, que no esta en el reparto" % target)
		return

	if not character.animation_player.has_animation(animation):
		# The chart spells animations Funkin's way and this port spells them Rubicon's, so
		# `endConv` has to find `end_conv`. Only tried as a fallback: an exact match always
		# wins, and every name that is already snake_case survives the conversion unchanged.
		var converted := StringName(String(animation).to_snake_case())
		if not character.animation_player.has_animation(converted):
			push_warning("PlayAnimation pide %s, que %s no tiene" % [animation, target])
			return
		animation = converted

	if not force and character.animation_player.current_animation == animation:
		return

	# Held in STATE_OVERRIDE until the clip ends, and this is the one place the port does
	# not simply mirror Funkin. Rubicon re-dances a resting character on the next dance
	# step, which at 152bpm is 0.4s, and komi's `breath` and `reaction` are 0.625s - so
	# played and released, the event was visible for SEVEN MILLISECONDS before dance_idle
	# took it back. An event the chart spends a key on and nobody can see is the same as
	# not porting it.
	#
	# The cost is that a note arriving inside the window does not animate. For the two
	# `breath` events that costs nothing: there is not a single opponent note in either
	# window. For `reaction`, which the chart marks force:true, komi skips one sing - and
	# forcing it is what the charter asked for.
	character.state = character.CharacterState.STATE_OVERRIDE
	character.play(animation, true)

	var player: AnimationPlayer = character.animation_player
	if player.animation_finished.is_connected(_release):
		player.animation_finished.disconnect(_release)
	player.animation_finished.connect(_release.bind(character), CONNECT_ONE_SHOT)


## SetProperty <character>.idleSuffix. Rubicon has no idleSuffix: a character picks its
## animation from `animations`, which maps a lane alias to an animation name, and dances
## whatever is in `dancing_animations`. So a suffix switch is a remap of both - and
## rubicon_character.gd's _refresh_last_sing_anim() already exists to handle exactly this
## happening in the middle of a hold note.
func set_idle_suffix(target: StringName, suffix: String) -> void:
	var character: Node = cast.get(target)
	if character == null:
		push_warning("SetProperty nombra a %s, que no esta en el reparto" % target)
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


## phone-call.script's standUP(), at beat 232 - 91.6s at 152bpm, where the song stops being
## a phone call and the two of them are finally standing in front of each other.
##
## The script destroys the phone characters and fetches "tadano-stand" and "komi-stand" from
## the character registry. Here all four are in the scene from the start and this is a
## visibility swap: instantiating two multisparrow characters mid-song on a phone is a
## stall, and there is nothing to gain from it.
##
## It also inverts the whole stage - `prop.visible = prop.name.indexOf("stand-") != -1` -
## which is what the six `stand-` props hidden since buildStage() have been waiting for.
func stand_up() -> void:
	# Idempotent, and it has to be: the swap rebinds `cast` onto the standing pair, so a
	# second call would hide the characters the first one just revealed. A method key fires
	# more than once whenever something re-seeks across it, which every harness here does.
	if _stood_up:
		return
	_stood_up = true

	for slot: StringName in stand_cast:
		var character: Node2D = stand_cast[slot]
		if character == null:
			continue
		character.visible = true

	for slot: StringName in [&"boyfriend", &"dad", &"gf"]:
		var character: Node2D = cast.get(slot)
		if character != null:
			character.visible = false

	# The chart's PlayAnimation events at 132.2s ask for `endAnimation` on boyfriend and
	# `endConv` on dad, and those animations only exist on the standing pair - which is what
	# the swap is FOR. Funkin gets this for free by destroying the old characters and
	# putting the new ones in the same slots; here the cast has to be rebound.
	for slot: StringName in stand_cast:
		if stand_cast[slot] == null:
			continue
		cast[slot] = stand_cast[slot]
		if slot == &"boyfriend":
			cast[&"bf"] = stand_cast[slot]

	if stage != null:
		_swap_props(stage)

	if flash != null:
		flash.color = Color(1.0, 1.0, 1.0, 1.0)
		var tween: Tween = create_tween()
		tween.tween_property(flash, "color:a", 0.0, FLASH_SECONDS)


func _swap_props(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Sprite2D:
			# The stage builds every prop under its authored name, `stand-` ones included,
			# with the dashes turned into underscores.
			child.visible = String(child.name).contains("stand_")
		_swap_props(child)
