extends AnimatedSprite2D
## An Animania health icon: a state machine with transition animations, and - for komi -
## one that sings along with its character.
##
## Rubicon has nothing like this. RubiconHealthBar moves a PathFollow2D and never touches
## the two AnimatedSprite2Ds hanging off it; bf_icon.tres carries a `neutral` and a `lose`
## animation that no code ever switches between. Animania's icons animate INTO and OUT of
## the losing state (`basic-to-lose`, `lose-to-basic`) and komi's plays a sing pose on every
## note, with a second full set of poses for when she is behind.
##
## Everything here is komi.hx's initHealthIcon and onUpdate, transcribed:
##
##   * the threshold is LOSING_THRESHOLD = 0.25 * 2, a quarter of the bar;
##   * a sing pose holds for `iconTimer` counting from 0 to 4 at 6x elapsed, i.e. two
##     thirds of a second, and any new note restarts it;
##   * below the threshold every sing pose takes the `-alt` set - iconAnimPostfix;
##   * the icon is drawn flipped, which is why the atlas's "right" art is this port's
##     sing_left (see build_icons.gd).
##
## An opponent's icon reads the INVERSE of the player's health - Funkin calls
## `iconP2.updateHealthIcon(100 - healthPercent)` - which is what `inverted` is for.

## komi.hx: LOSING_THRESHOLD = 0.25 * 2, against a bar that runs 0..2.
const LOSING_THRESHOLD := 0.25
## iconTimer runs to 4 at 6x elapsed.
const SING_HOLD := 4.0 / 6.0

@export var health_module: Node
## The side whose hits this icon reacts to. Leave null for an icon that only tracks health.
@export var note_controller: Node
## True for the opponent's icon, which is losing when the player is winning.
@export var inverted: bool = false
## komi has a second pose set for when she is behind; tadano's icon does not.
@export var has_alt_poses: bool = false

## mania_directions, in Rubicon's lane order.
const LANES := [&"left", &"down", &"up", &"right"]

var _losing: bool = false
var _sing_timer: float = 0.0
var _transitioning: bool = false


func _ready() -> void:
	if health_module != null and health_module.has_signal(&"health_changed"):
		health_module.health_changed.connect(_on_health_changed)
	if note_controller != null and note_controller.has_signal(&"handler_just_pressed"):
		note_controller.handler_just_pressed.connect(_on_handler_pressed)

	animation_finished.connect(_on_animation_finished)
	_losing = _is_losing()
	play(&"losing" if _losing else &"idle")


func _process(delta: float) -> void:
	if _sing_timer <= 0.0:
		return

	_sing_timer -= delta
	if _sing_timer > 0.0:
		return
	_rest()


func _on_health_changed() -> void:
	var losing: bool = _is_losing()
	if losing == _losing:
		return

	_losing = losing
	# Mid-sing the state still flips, but the transition waits: cutting a sing pose off to
	# play a crossfade is the one thing the original never does.
	if _sing_timer > 0.0:
		return
	_transition()


func _on_handler_pressed(id: StringName) -> void:
	if not sprite_frames.has_animation(&"sing_left"):
		return

	var lane: int = LANES.find(StringName(String(id).trim_prefix("mania_lane")))
	if lane < 0:
		lane = int(String(id).trim_prefix("mania_lane"))
	if lane < 0 or lane >= LANES.size():
		return

	var name := StringName("sing_%s%s" % [
		LANES[lane], "_alt" if (_losing and has_alt_poses) else ""])
	if not sprite_frames.has_animation(name):
		return

	_transitioning = false
	_sing_timer = SING_HOLD
	play(name)


func _rest() -> void:
	_sing_timer = 0.0
	_transitioning = false
	play(&"losing" if _losing else &"idle")


func _transition() -> void:
	var name := StringName("to_losing" if _losing else "from_losing")
	if not sprite_frames.has_animation(name):
		_rest()
		return

	_transitioning = true
	play(name)


func _on_animation_finished() -> void:
	if not _transitioning:
		# A sing pose that runs out before its hold does goes back on its own; the hold is
		# what stops the next note from being swallowed, not what keeps the frame up.
		return
	_transitioning = false
	play(&"losing" if _losing else &"idle")


func _is_losing() -> bool:
	if health_module == null:
		return false

	var span: float = float(health_module.max_health) - float(health_module.min_health)
	if is_zero_approx(span):
		return false

	var ratio: float = (float(health_module.health) - float(health_module.min_health)) / span
	if inverted:
		ratio = 1.0 - ratio
	return ratio < LOSING_THRESHOLD
