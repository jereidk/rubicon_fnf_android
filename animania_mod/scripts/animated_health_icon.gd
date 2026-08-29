extends AnimatedSprite2D
## An Animania health icon: a state machine with transition animations, and - for komi -
## one that sings along with its character.
##
## Rubicon has nothing like this. RubiconHealthBar moves a PathFollow2D and never touches
## the two AnimatedSprite2Ds hanging off it; bf_icon.tres carries a `neutral` and a `lose`
## animation that no code ever switches between. Animania's icons animate INTO and OUT of
## their states and komi's plays a sing pose on every note, with a second full set of poses
## for when she is behind.
##
## Everything here is komi.hx's initHealthIcon and onUpdate plus phone-call.script's
## onStartSong, transcribed:
##
##   * the losing threshold is LOSING_THRESHOLD = 0.25 * 2 on a bar that runs 0..2 - a
##     quarter of it;
##   * a sing pose holds for `iconTimer` counting 0 to 4 at 6x elapsed, i.e. two thirds of
##     a second, and any new note restarts it;
##   * below the threshold every sing pose takes the `-alt` set (iconAnimPostfix);
##   * the icon is drawn flipped, which is why the atlas's "right" art is this port's
##     sing_left (see tools/animania/build_icons.gd).

## Which side of the bar an icon reads.
##
## phone-call.script's onStartSong gives playerId 1 `updateHealthIcon(2 - health)` and
## playerId 0 `updateHealthIcon(health)`, and labels them `// Boyfriend` and `// Dad` in
## that order. THE COMMENTS ARE BACKWARDS. AnimaniaStuff.makeAmTakeAnimatedIcon settles it
## in the mod's own code - `isPlayer = (icon.playerId == 0)` - so playerId 0 is the player
## and it is the OPPONENT's icon that reads the inverse, as in stock Funkin.
##
## Taking the comments at their word put the losing face on tadano at full health and the
## winning face on him as he died. The two tilts say the same thing and were nonsense the
## other way round: playerId 0 tilts when healthLerp is BELOW .25 and playerId 1 when it is
## ABOVE 1.75, which is each of them reacting to its own side losing.
@export var inverted: bool = false

## iconTimer runs to 4 at 6x elapsed.
const SING_HOLD := 4.0 / 6.0

## Which face is on, from `AnimaniaStuff.makeAmTakeAnimatedIcon` - the module that actually
## drives these, recovered from the mod's own assets. It declares its thresholds against a
## bar that runs 0..2, so each is half of what it writes:
##
##     DEATH_THRESHOLD  = 0.125 * 2  ->  0.125
##     LOSING_THRESHOLD = 0.25  * 2  ->  0.25
##     WINING_THRESHOLD = 0.8   * 2  ->  0.8
##
## The atlas calls the bottom rung `predeath` where the module calls it `death`; the atlas
## wins for names, the module for numbers.
const PREDEATH_THRESHOLD := 0.125
const LOSING_THRESHOLD := 0.25
const WINNING_THRESHOLD := 0.8

## And these are a DIFFERENT pair, which is what the first version of this got wrong.
##
## phone-call.script tilts an icon when healthLerp passes 1.75 or falls under 0.25 on the
## same 0..2 bar - 0.875 and 0.125 of it. Those are the angle's thresholds, not the face's.
## Lacking the module, this port read them as both, and shipped a winning face that waited
## until 0.875 when the mod turns it on at 0.8. The bottom one agreed by coincidence.
const PREDEATH_TILT_AT := 0.125

## onStartSong's icon.angle, in degrees per unit of overshoot past the threshold.
##
## One rule per icon, not two: each one tilts only when ITS OWN side is losing, which after
## the inversion is the same threshold for both. The degrees differ per icon - the player's
## -30 and the opponent's 50 - and the opponent's sprite is mirrored, so both droop the same
## way on screen.
@export var tilt_degrees: float = -30.0
## onStartSong's `+ Math.cos((health - 1) * 2) * 15` bob, a screen distance so it scales.
##
## Written as a difference from the cosine's value at NEUTRAL health rather than as the raw
## term, because ICON_DROP - the rest position this rides on - was measured off a capture
## of the original with the bar near neutral, so the cosine has to be worth nothing there
## or the measurement moves. The shape either side is the mod's: the icons sit lowest at
## neutral and rise by 21 pixels toward both extremes.
const BOB_AMPLITUDE := 15.0 * 1920.0 / 1280.0

## onCreatePost's `for (c in [iconP1, iconP2]) c.bopEvery = 4 * 4;`, and HealthIcon's own
## BOP_SCALE.
##
## bopEvery is counted in STEPS, not beats - the method it feeds is onStepHit(Int) - so
## `4 * 4` is sixteen steps, one bar at 4/4. A slow pulse once a measure rather than the
## every-beat one stock Funkin does. BOP_SCALE is 0.2, read out of HealthIcon's __boot
## rather than assumed: the icon jumps to 1.2x and eases back to rest.
const BOP_EVERY_STEPS := 16
const BOP_SCALE := 0.2
## How fast the bop decays. Funkin lerps it out over roughly a beat; this is the same
## per-second factor the HUD punch in phone_call_events.gd uses, for one decay in the port.
const BOP_DECAY := 3.0

## The ladder, in order. Every adjacent pair has a transition animation in the atlas and no
## non-adjacent pair does, so a jump of more than one rung walks it a step at a time.
const LADDER := [&"predeath", &"losing", &"idle", &"winning"]

## mania_directions, in Rubicon's lane order.
const LANES := [&"left", &"down", &"up", &"right"]

## The level clock, for the icon's own bop. Left null on an icon that does not bop.
@export var clock: Node
@export var health_module: Node
## The side whose hits this icon reacts to. Leave null for an icon that only tracks health.
@export var note_controller: Node
## komi has a second pose set for when she is behind; tadano's icon does not.
@export var has_alt_poses: bool = false
## The extreme tilt and the health bob, both from phone-call.script's onStartSong.
@export var tilts: bool = true

var _state: StringName = &"idle"
var _sing_timer: float = 0.0
var _transitioning: bool = false
var _rest_position: Vector2
var _rest_scale: Vector2 = Vector2.ONE
var _initialised: bool = false


func _ready() -> void:
	_rest_position = position
	# Multiplied into, never written over: one of the two icons carries a negative scale.x
	# because that is what puts it on its own side of the bar's centre, and the fit to
	# ICON_HEIGHT is in here too.
	_rest_scale = scale

	if clock != null and clock.has_signal(&"step_change"):
		clock.step_change.connect(_on_step)

	if health_module != null and health_module.has_signal(&"health_changed"):
		health_module.health_changed.connect(_on_health_changed)
	if note_controller != null and note_controller.has_signal(&"handler_just_pressed"):
		note_controller.handler_just_pressed.connect(_on_handler_pressed)

	animation_finished.connect(_on_animation_finished)


func _process(delta: float) -> void:
	# The starting state is settled on the first frame, not in _ready: RubiconHealthModule
	# has not taken its starting_health yet at that point, so `health` reads 0 - and an
	# inverted icon starting from 0 believes it is winning and then plays a transition out
	# of a state it was never in.
	if not _initialised:
		_initialised = true
		_state = _target_state()
		play(_state)

	if tilts:
		_apply_tilt_and_bob()

	if not scale.is_equal_approx(_rest_scale):
		scale = scale.lerp(_rest_scale, minf(1.0, BOP_DECAY * delta))

	if _sing_timer <= 0.0:
		return

	_sing_timer -= delta
	if _sing_timer > 0.0:
		return
	_rest()


## onStartSong: the icon tilts once health passes the extremes, and rides a cosine of it the
## rest of the time. Both are offsets on top of wherever the bar puts the icon at rest -
## which is now a FIXED point pinned to the bar's own centre (see build_health_bar.gd's
## IconAnchor), matching phone-call.script's `icon.x = healthBar.centerPoint.x + ...`. It
## used to ride Rubicon's health-driven PathFollow2D instead, which is Funkin's own
## behaviour and not this mod's: Animania's icons never move in x with health at all.
func _apply_tilt_and_bob() -> void:
	var ratio: float = _ratio()
	position = _rest_position + Vector2(0.0,
		(cos((ratio * 2.0 - 1.0) * 2.0) - 1.0) * BOB_AMPLITUDE)

	if ratio < PREDEATH_TILT_AT:
		rotation_degrees = tilt_degrees * (PREDEATH_TILT_AT - ratio) * 2.0
	else:
		rotation_degrees = 0.0


## onStepHit: every bopEvery steps the icon jumps to 1 + BOP_SCALE and eases back.
func _on_step() -> void:
	if int(clock.time_step) % BOP_EVERY_STEPS != 0:
		return
	scale = _rest_scale * (1.0 + BOP_SCALE)


func _on_health_changed() -> void:
	var target: StringName = _target_state()
	if target == _state:
		return

	# Mid-sing the state still changes, but the transition waits: cutting a sing pose off to
	# play a crossfade is the one thing the original never does.
	if _sing_timer > 0.0:
		_state = target
		return
	_step_towards(target)


func _on_handler_pressed(id: StringName) -> void:
	if not sprite_frames.has_animation(&"sing_left"):
		return

	var lane: int = LANES.find(StringName(String(id).trim_prefix("mania_lane")))
	if lane < 0:
		lane = int(String(id).trim_prefix("mania_lane"))
	if lane < 0 or lane >= LANES.size():
		return

	var name := StringName("sing_%s%s" % [
		LANES[lane], "_alt" if (_state != &"idle" and has_alt_poses) else ""])
	if not sprite_frames.has_animation(name):
		return

	_transitioning = false
	_sing_timer = SING_HOLD
	play(name)


func _rest() -> void:
	_sing_timer = 0.0
	_transitioning = false
	play(_state)


## One rung at a time: the atlas has basic<->lose, basic<->win and lose<->predeath and
## nothing else, so a jump from winning to predeath plays three transitions rather than
## snapping or looking for an animation that was never drawn.
func _step_towards(target: StringName) -> void:
	var from: int = LADDER.find(_state)
	var to: int = LADDER.find(target)
	if from < 0 or to < 0 or from == to:
		_state = target
		_pending = &""
		_rest()
		return

	var next: StringName = LADDER[from + (1 if to > from else -1)]
	var transition: StringName = _transition_between(_state, next)
	_state = next
	_pending = target

	if not sprite_frames.has_animation(transition):
		if _state == target:
			_pending = &""
			_rest()
		else:
			_step_towards(target)
		return

	_transitioning = true
	play(transition)


var _pending: StringName = &""


## The transitions are named for the end that is NOT idle: to_losing / from_losing,
## to_winning / from_winning, to_predeath / from_predeath. So a step away from idle is
## `to_<destination>` and a step back toward it is `from_<origin>`.
func _transition_between(from: StringName, to: StringName) -> StringName:
	if _distance_from_idle(to) > _distance_from_idle(from):
		return StringName("to_%s" % to)
	return StringName("from_%s" % from)


func _distance_from_idle(state: StringName) -> int:
	return absi(LADDER.find(state) - LADDER.find(&"idle"))


func _on_animation_finished() -> void:
	if not _transitioning:
		# A sing pose that runs out before its hold does goes back on its own; the hold is
		# what stops the next note from being swallowed, not what keeps the frame up.
		return

	_transitioning = false
	if _pending != &"" and _pending != _state:
		_step_towards(_pending)
		return
	_pending = &""
	play(_state)


func _ratio() -> float:
	if health_module == null:
		return 0.5

	var span: float = float(health_module.max_health) - float(health_module.min_health)
	if is_zero_approx(span):
		return 0.5

	var ratio: float = (float(health_module.health) - float(health_module.min_health)) / span
	return 1.0 - ratio if inverted else ratio


func _target_state() -> StringName:
	var ratio: float = _ratio()
	if sprite_frames.has_animation(&"predeath") and ratio < PREDEATH_THRESHOLD:
		return &"predeath"
	if ratio < LOSING_THRESHOLD:
		return &"losing"
	if sprite_frames.has_animation(&"winning") and ratio > WINNING_THRESHOLD:
		return &"winning"
	return &"idle"
