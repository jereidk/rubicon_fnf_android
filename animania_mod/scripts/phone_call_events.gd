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

## Funkin is 1280x720 and this project is 1920x1080. Shake intensity is a FRACTION of the
## camera's size in Flixel, and the HUD tween distances are screen distances, so both scale.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCREEN_WIDTH := 1920.0
const SCREEN_HEIGHT := 1080.0

## onBeatHit's tween at beat 332: y +/- 250 over 1.75s, alpha to 0.
const HUD_TWEEN_DISTANCE := 250.0
const HUD_TWEEN_SECONDS := 1.75
const HUD_TWEEN_DELAY_UP := 0.25
const HUD_TWEEN_DELAY_DOWN := 0.5

## Funkin's default per-bop game zoom. SetCameraBop's `intensity` is a multiplier on it,
## which is why the chart's AddCameraZoom events mostly carry this exact number.
const DEFAULT_BOP := 0.015

## onCreatePost, and onBeatHit cases 0, 1, 11, 13, 31 and 166: the opening.
##
## A full-screen black cover is up from the first frame and comes off at beat 13; the title
## card fades in at beat 1 and out at beat 11; the HUD does not exist until beat 31.
const INTRO_FADE_SECONDS := 2.5
const INTRO_TEXT_SCALE := 0.8

## case 13: `tad.x += 380`, then a tween to `tad.x - 350` over 1.45s, then one to
## `tad.x - 380` over half a second. Haxe reads both targets when the chain is BUILT, with
## x already at home + 380, so the two legs land on home + 30 and home.
const ENTRANCE_OUT := 380.0
const ENTRANCE_BACK := 350.0
const ENTRANCE_SECONDS := 1.45
const ENTRANCE_SETTLE_SECONDS := 0.5

## case 168: tadano slides 800 further right. The chart's FocusCamera on the same beat
## carries an x offset of 700, which is what makes this readable as one gesture rather than
## two coincidences.
const SLIDE_DISTANCE := 800.0
const SLIDE_SECONDS := 1.35

## case 31: camHUD comes up from alpha 0 and zoom 1.1 in just over a third of a second, and
## the player's lanes fade in with it. The timing is not loose: beat 31 is 12.24s and the
## first player note is at 12.26s.
const HUD_IN_SECONDS := 0.35
const HUD_IN_ZOOM := 1.1

## The two strumlines EXCHANGE sides, and the arithmetic forces that reading whatever
## `Constants.STRUMLINE_X_OFFSET` happens to be. onCreatePost moves the player's lanes half
## a screen left and nothing ever moves them back, so their home must be
## `width / 2 + OFFSET` - otherwise 195 player notes would fall off the left edge for the
## whole song. That leaves them on `OFFSET`, which is the opponent's home. And beat 166
## flies the opponent's lanes to `width / 2 + OFFSET`, which is the player's.
##
## The opponent starts a full screen right of its own home, at alpha 0 and a full turn of
## rotation, and arrives at half alpha; beat 232 takes it the rest of the way. Which is the
## song: komi is a voice on a phone until she is standing there.
const LANES_SPIN := 360.0
const LANES_IN_DELAY := 2.0
const LANES_IN_SECONDS := 1.35
const LANES_HALF_ALPHA := 0.5

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
## A full-screen black ColorRect for camGame.fade.
@export var fade: ColorRect
## What beat 332 tweens away: the health bar and its icons upward, the strumlines downward.
@export var hud_up: Array[Node] = []
@export var hud_down: Array[Node] = []

## The opening. `hud_root` is the Control the whole HUD hangs off, which is what camHUD's
## alpha maps to; the two lane containers move and fade on their own underneath it.
##
## `cover` is onCreatePost's blackScreenSpr, and it is NOT the same node as `fade`. Funkin
## gives it zIndex 5999, between overlay-all at 5000 and introText at 6000, so the title
## card reads over the black instead of under it - which is the whole shape of the opening.
## It therefore lives inside the stage's screen-space layer, not in the level's overlays.
@export var cover: ColorRect
@export var intro_text: AnimatedSprite2D
@export var hud_root: Control
@export var player_lanes: Control
@export var opponent_lanes: Control

var _hud_rest: Vector2 = Vector2.ONE
var _hud_tween: Tween
var _stood_up: bool = false
var _lane_homes: Dictionary[StringName, Vector2] = {}
var _shake_amount: float = 0.0
var _shake_left: float = 0.0


func _ready() -> void:
	if hud != null:
		_hud_rest = hud.scale
	# Read before anything moves them: `opening()` assigns absolute positions off these, so
	# it can be re-fired by a re-seek without walking the lanes further each time.
	if player_lanes != null:
		_lane_homes[&"player"] = player_lanes.position
	if opponent_lanes != null:
		_lane_homes[&"opponent"] = opponent_lanes.position
	opening()


## AddCameraZoom. `hud_zoom` is applied to the UI canvas about the middle of the screen -
## a CanvasLayer scales from its top-left corner, so scaling alone would slide the whole
## HUD up and to the left instead of pulsing it in place.
func punch(game_zoom: float, hud_zoom: float) -> void:
	if camera != null:
		camera.zoom += Vector2.ONE * game_zoom

	if hud == null:
		return
	hud.scale = _hud_rest + Vector2.ONE * hud_zoom
	_centre_hud()


## A CanvasLayer scales from its top-left corner, so every scale it is given has to be paid
## back as an offset or the whole HUD slides up and to the left instead of pulsing in place.
func _centre_hud() -> void:
	var screen: Vector2 = Vector2(hud.get_viewport().get_visible_rect().size)
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
	if _shake_left > 0.0:
		_shake_left -= delta
		if camera != null:
			camera.position_interpolate_offset = Vector2(
				randf_range(-_shake_amount, _shake_amount),
				randf_range(-_shake_amount, _shake_amount)) \
				if _shake_left > 0.0 else Vector2.ZERO

	if hud == null:
		return

	# Beat 31's zoom-in owns the scale while it runs; the punch decay would fight it for
	# every one of those 0.35 seconds.
	if _hud_tween != null and _hud_tween.is_running():
		_centre_hud()
		return

	if hud.scale.is_equal_approx(_hud_rest):
		return
	hud.scale = hud.scale.lerp(_hud_rest, minf(1.0, 3.0 * delta))
	_centre_hud()


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

	# Beat 232 also finishes the opponent's lanes off, and it has to ride here rather than
	# on a key of its own: two method keys at the same time collapse into one. Animation's
	# key-collision epsilon is RELATIVE (CMP_EPSILON * |t|), and at 91.6s two keys have to
	# be a full millisecond apart to survive as two.
	if opponent_lanes != null:
		create_tween().tween_property(opponent_lanes, "modulate:a", 1.0, LANES_IN_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _swap_props(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Sprite2D:
			# The stage builds every prop under its authored name, `stand-` ones included,
			# with the dashes turned into underscores.
			child.visible = String(child.name).contains("stand_")
		_swap_props(child)


## camGame.shake(intensity, duration) at beats 16, 19 and 23.
##
## Flixel's intensity is a FRACTION of the camera's size, so the script's 0.0005 is 0.96px
## at 1920 wide - a rumble on a beat accent, not a jolt. It is applied through the camera's
## position_interpolate_OFFSET rather than its position, so it rides on top of the baked
## FocusCamera track instead of fighting it.
func shake(intensity: float, duration: float) -> void:
	_shake_amount = intensity * SCREEN_WIDTH
	_shake_left = duration


## onBeatHit case 332: the HUD leaves. Downscroll here, so the bar and its icons go up and
## the strumlines go down, both fading, with the strumlines a quarter of a second behind.
func hud_out() -> void:
	var distance: float = HUD_TWEEN_DISTANCE * FUNKIN_TO_RUBICON
	_tween_out(hud_up, -distance, HUD_TWEEN_DELAY_UP)
	_tween_out(hud_down, distance, HUD_TWEEN_DELAY_DOWN)


func _tween_out(nodes: Array[Node], distance: float, delay: float) -> void:
	for node: Node in nodes:
		if node == null or not (node is CanvasItem):
			continue
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(node, "position:y", node.position.y + distance,
			HUD_TWEEN_SECONDS).set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(
			Tween.EASE_IN)
		tween.tween_property(node, "modulate:a", 0.0,
			HUD_TWEEN_SECONDS).set_delay(delay)


## onCreatePost, and onBeatHit case 0. Everything the opening needs to be true before the
## first frame is drawn: the screen is black, the title card is not up yet, the HUD does not
## exist, and the two strumlines have exchanged homes with the opponent's parked a full
## screen off the right edge.
##
## Assigned absolutely off the homes read in _ready, never adjusted, so a re-seek to the top
## of the song puts the opening back instead of walking the lanes another screen away.
func opening() -> void:
	if cover != null:
		cover.color = Color(0.0, 0.0, 0.0, 1.0)

	if intro_text != null:
		intro_text.visible = false
		intro_text.modulate.a = 0.0

	if hud_root != null:
		hud_root.modulate.a = 0.0

	if player_lanes != null and _lane_homes.has(&"opponent"):
		player_lanes.position.x = _lane_homes[&"opponent"].x
		player_lanes.modulate.a = 0.0

	if opponent_lanes != null and _lane_homes.has(&"opponent"):
		opponent_lanes.position.x = _lane_homes[&"opponent"].x + SCREEN_WIDTH
		opponent_lanes.modulate.a = 0.0
		opponent_lanes.rotation_degrees = LANES_SPIN


## case 1: the title card is centred, scaled to 0.8 and fades up over two and a half
## seconds. It is the one prop the stage ships switched off, because nothing in the stage
## data ever turns it on - this is what does.
func intro_show_text() -> void:
	if intro_text == null:
		return

	intro_text.visible = true
	intro_text.scale = Vector2.ONE * INTRO_TEXT_SCALE
	# screenCenter() on a sprite drawn from its top-left corner.
	var frame: Texture2D = intro_text.sprite_frames.get_frame_texture(
		intro_text.animation, 0)
	if frame != null:
		intro_text.position = (Vector2(SCREEN_WIDTH, SCREEN_HEIGHT)
			- frame.get_size() * INTRO_TEXT_SCALE) * 0.5
	intro_text.play()

	intro_text.modulate.a = 0.0
	create_tween().tween_property(intro_text, "modulate:a", 1.0, INTRO_FADE_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## case 11: and back out again, over the same two and a half seconds.
func intro_hide_text() -> void:
	if intro_text == null:
		return
	create_tween().tween_property(intro_text, "modulate:a", 0.0, INTRO_FADE_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## case 13: the black cover comes off and tadano walks into frame playing `intro`.
##
## The camera does not follow him. Funkin's FocusCamera takes a SNAPSHOT of the character's
## midpoint when the event fires and tweens the follow point to it - it does not track a
## moving character - which is exactly why this port could bake the whole camera into a
## value track in the first place. So the walk reads as a walk.
func intro_reveal() -> void:
	if cover != null:
		create_tween().tween_property(cover, "color:a", 0.0, INTRO_FADE_SECONDS) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var tadano: Node2D = cast.get(&"boyfriend")
	if tadano == null:
		return

	var home: float = tadano.position.x
	tadano.position.x = home + ENTRANCE_OUT
	var walk: Tween = create_tween()
	# Default ease, which in Flixel is linear, then a cube-out onto the last thirty pixels.
	walk.tween_property(tadano, "position:x", home + ENTRANCE_OUT - ENTRANCE_BACK,
		ENTRANCE_SECONDS).set_trans(Tween.TRANS_LINEAR)
	walk.tween_property(tadano, "position:x", home, ENTRANCE_SETTLE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	play_character_animation(&"boyfriend", &"intro", true)


## case 31: the HUD arrives, zooming in from 1.1 as it fades up, and the player's lanes fade
## up with it.
func hud_in() -> void:
	if hud != null:
		hud.scale = _hud_rest * HUD_IN_ZOOM
		_centre_hud()
		_hud_tween = create_tween()
		_hud_tween.tween_property(hud, "scale", _hud_rest, HUD_IN_SECONDS)

	for node: CanvasItem in [hud_root, player_lanes]:
		if node != null:
			create_tween().tween_property(node, "modulate:a", 1.0, HUD_IN_SECONDS)


## case 168: tadano slides 800 right, into the offset the chart's FocusCamera already has.
func boyfriend_slide() -> void:
	var tadano: Node2D = cast.get(&"boyfriend")
	if tadano == null:
		return
	create_tween().tween_property(tadano, "position:x",
		tadano.position.x + SLIDE_DISTANCE, SLIDE_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## case 166: two seconds later the opponent's lanes fly in from off the right edge, unwind a
## full turn and settle at half alpha on what was the player's side.
func opponent_lanes_in() -> void:
	if opponent_lanes == null or not _lane_homes.has(&"player"):
		return

	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(opponent_lanes, "position:x", _lane_homes[&"player"].x,
		LANES_IN_SECONDS).set_delay(LANES_IN_DELAY)
	tween.tween_property(opponent_lanes, "rotation_degrees", 0.0,
		LANES_IN_SECONDS).set_delay(LANES_IN_DELAY)
	tween.tween_property(opponent_lanes, "modulate:a", LANES_HALF_ALPHA,
		LANES_IN_SECONDS).set_delay(LANES_IN_DELAY)


## onBeatHit case 348: camGame.fade(FlxColor.BLACK, 3, false).
func fade_out(duration: float) -> void:
	if fade == null:
		return
	fade.color = Color(0.0, 0.0, 0.0, 0.0)
	create_tween().tween_property(fade, "color:a", 1.0, duration)
