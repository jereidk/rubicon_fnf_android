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
## phone-call.script's onStartSong is explicit: playerId 1 (Boyfriend) gets
## `updateHealthIcon(2 - health)` and playerId 0 (Dad) gets `updateHealthIcon(health)`. So
## it is the PLAYER's icon that reads the inverse here, not the opponent's - the reverse of
## stock Funkin, and of the first version of this port. The song also runs
## `healthBar.flipped = true`, which is the other half of the same mirroring.
@export var inverted: bool = false

## komi.hx: LOSING_THRESHOLD = 0.25 * 2, against a bar that runs 0..2.
const LOSING_THRESHOLD := 0.25
## iconTimer runs to 4 at 6x elapsed.
const SING_HOLD := 4.0 / 6.0

## The extremes, and where they come from: phone-call.script tilts an icon when healthLerp
## passes 1.75 or falls under 0.25 on its 0..2 bar, which is 0.875 and 0.125 of it. Those
## are the only two numbers in this slice that mark "winning hard" and "about to die", so
## they are what the win and predeath states use. AnimaniaStuff.makeAmTakeAnimatedIcon,
## which is what actually drives tadano's four states, is not in this slice - so this is
## inferred from the mod's own numbers rather than read from its code.
const WINNING_THRESHOLD := 0.875
const PREDEATH_THRESHOLD := 0.125

## onStartSong's icon.angle, in degrees per unit of overshoot past the threshold.
const WINNING_TILT := 50.0
const PREDEATH_TILT := -30.0
## onStartSong's `- Math.cos((health - 1) * 2) * 15` bob, a screen distance so it scales.
const BOB_AMPLITUDE := 15.0 * 1920.0 / 1280.0

## The ladder, in order. Every adjacent pair has a transition animation in the atlas and no
## non-adjacent pair does, so a jump of more than one rung walks it a step at a time.
const LADDER := [&"predeath", &"losing", &"idle", &"winning"]

## mania_directions, in Rubicon's lane order.
const LANES := [&"left", &"down", &"up", &"right"]

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
var _initialised: bool = false


func _ready() -> void:
	_rest_position = position

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

	if _sing_timer <= 0.0:
		return

	_sing_timer -= delta
	if _sing_timer > 0.0:
		return
	_rest()


## onStartSong: the icon tilts once health passes the extremes, and rides a cosine of it the
## rest of the time. Both are offsets on top of whatever position the bar gives the icon,
## which is Rubicon's PathFollow2D and not Funkin's centerPoint arithmetic.
func _apply_tilt_and_bob() -> void:
	var ratio: float = _ratio()
	position = _rest_position + Vector2(0.0, -cos((ratio * 2.0 - 1.0) * 2.0) * BOB_AMPLITUDE)

	if ratio > WINNING_THRESHOLD:
		rotation_degrees = WINNING_TILT * (ratio - WINNING_THRESHOLD) * 2.0
	elif ratio < PREDEATH_THRESHOLD:
		rotation_degrees = PREDEATH_TILT * (PREDEATH_THRESHOLD - ratio) * 2.0
	else:
		rotation_degrees = 0.0


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
