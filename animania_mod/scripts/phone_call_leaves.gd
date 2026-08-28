@tool
extends Node2D
## Falling leaves for the Phone Call Street stage.
##
## A straight port of PhoneCallStreet.hx's createLeaf/onBeatHit/onUpdate. Every
## constant here is the mod's, kept as a named range rather than folded into a
## single number so a future look pass can see what was authored:
##
##   * three leaves exist from the moment the stage is built, and onBeatHit rolls
##     a 10% chance to add one while there are nine or fewer;
##   * a leaf that falls past y = 1550 is not freed, it is re-randomised and put
##     back at the top - so the pool never grows past ten and nothing is ever
##     instantiated mid-song;
##   * each leaf gets its own horizontal scroll factor (0.9 .. 1.1), which is why
##     each one lives under its own Parallax2D instead of the whole group sharing
##     one. Rotation, fall speed, drift, scale, start frame and playback rate are
##     all per-leaf too.
##
## Preferences.lowQuality skips the whole system in the mod - both the initial three
## and the per-beat roll. `low_quality` is that switch. This branch has no quality
## ladder yet, so it is a plain exported bool rather than a read of a settings
## autoload that does not exist; wire it up when one lands.

const RECYCLE_Y := 1550.0
const INITIAL_LEAVES := 3
const MAX_LEAVES := 9
const SPAWN_CHANCE := 0.10

const BOUNDS_X := Vector2(-1500.0, 1500.0)
const BOUNDS_Y := Vector2(-150.0, 50.0)
const ANGULAR_VELOCITY := Vector2(-25.0, 65.0)
const VELOCITY_X := Vector2(-225.0, 275.0)
const VELOCITY_Y := Vector2(225.0, 450.0)
const SCALE_RANGE := Vector2(1.1, 1.35)
const SCROLL_X := Vector2(0.9, 1.1)
const FRAME_RATE := Vector2i(4, 24)
const START_FRAME := Vector2i(1, 9)
const ATLAS_FPS := 24.0

@export var leaf_frames: SpriteFrames
@export var leaf_animation: StringName = &"leaf"
## Skips the whole system, the way Preferences.lowQuality does in the mod.
@export var low_quality: bool = false

var _leaves: Array[AnimatedSprite2D] = []
var _velocities: Array[Vector2] = []
var _spins: Array[float] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if low_quality:
		return
	for i: int in INITIAL_LEAVES:
		_spawn()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or low_quality:
		return

	for i: int in _leaves.size():
		var leaf: AnimatedSprite2D = _leaves[i]
		leaf.position += _velocities[i] * delta
		leaf.rotation += _spins[i] * delta
		if leaf.position.y > RECYCLE_Y:
			_randomise(i)


## The mod rolls this on every beat and caps the pool at ten leaves.
func beat_hit() -> void:
	if low_quality:
		return
	if _leaves.size() > MAX_LEAVES:
		return
	if randf() >= SPAWN_CHANCE:
		return
	_spawn()


func _spawn() -> void:
	var parallax := Parallax2D.new()
	add_child(parallax)

	var leaf := AnimatedSprite2D.new()
	leaf.sprite_frames = leaf_frames
	leaf.animation = leaf_animation
	leaf.centered = false
	parallax.add_child(leaf)

	_leaves.append(leaf)
	_velocities.append(Vector2.ZERO)
	_spins.append(0.0)
	_randomise(_leaves.size() - 1)


func _randomise(index: int) -> void:
	var leaf: AnimatedSprite2D = _leaves[index]
	var parallax: Parallax2D = leaf.get_parent() as Parallax2D

	_spins[index] = deg_to_rad(randf_range(ANGULAR_VELOCITY.x, ANGULAR_VELOCITY.y))
	_velocities[index] = Vector2(
		randf_range(VELOCITY_X.x, VELOCITY_X.y),
		randf_range(VELOCITY_Y.x, VELOCITY_Y.y))

	leaf.position = Vector2(
		randf_range(BOUNDS_X.x, BOUNDS_X.y),
		randf_range(BOUNDS_Y.x, BOUNDS_Y.y))
	leaf.rotation = 0.0

	var leaf_scale: float = randf_range(SCALE_RANGE.x, SCALE_RANGE.y)
	leaf.scale = Vector2(leaf_scale, leaf_scale)

	# The mod randomises FlxAnimation.frameRate against a 24fps atlas.
	leaf.speed_scale = float(randi_range(FRAME_RATE.x, FRAME_RATE.y)) / ATLAS_FPS
	leaf.play(leaf_animation)
	leaf.frame = randi_range(START_FRAME.x, START_FRAME.y)

	if parallax != null:
		parallax.scroll_scale = Vector2(randf_range(SCROLL_X.x, SCROLL_X.y), 1.0)
