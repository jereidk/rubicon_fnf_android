extends Node2D
## The props that fall behind the title, from `animania.states.TitleScreen.updateProps()`.
##
## That method is compiled, so this is not transcribed the way the intro is - it is read out
## of the Linux build's disassembly, which ships unstripped. What the disassembly gives
## exactly is the SHAPE and the NUMBERS; what it does not give is which number lands in
## which field, because that needs the struct offsets resolved against TitleProp's layout.
## So every constant below is the mod's own, and the mapping is this port's reading. Each
## one says which it is.
##
## Derived exactly (constants lifted from .rodata and from the packed Null<int> immediates
## the FlxRandom calls are given):
##
##     -300, -200   negative y, so: spawned above the screen
##     -550, 400    an x range, in a frame of reference the offsets would settle
##     110, 50      speeds
##     1.6, 0.5     a multiplier and a half
##     -10          a small negative
##
## Derived structurally: one FlxTypedGroup of TitleProp, recycled rather than respawned
## (TitleProp's only method is `reloadProp`), six integer randoms and exactly one float
## random per pass.

const SCREEN := Vector2(1920.0, 1080.0)
## Funkin is 1280x720 and this project is 1920x1080; these are screen distances.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## Spawned above the top edge, between the two negative y values the code carries.
const SPAWN_Y := Vector2(-300.0, -200.0)
## The two speeds, as a range. The float random is what varies them.
const FALL_SPEED := Vector2(50.0, 110.0)
## The multiplier the fall is scaled by, and the half that pairs with it.
const SPEED_SPREAD := 1.6
const HALF := 0.5
## The small negative, read here as the drift a prop carries sideways as it falls.
const DRIFT := -10.0

## How many are in the air at once. NOT derived - the pool size lives in create(), not in
## updateProps, and nine props with one sprite each is what the atlas offers.
const POOL := 9

@export var frames: SpriteFrames

var _props: Array[AnimatedSprite2D] = []
var _speeds: PackedFloat32Array = []


func _ready() -> void:
	if frames == null:
		return
	var names: PackedStringArray = frames.get_animation_names()
	if names.is_empty():
		return

	for i: int in POOL:
		var prop := AnimatedSprite2D.new()
		prop.sprite_frames = frames
		prop.centered = false
		add_child(prop)
		_props.append(prop)
		_speeds.append(0.0)
		_recycle(i, true)


func _process(delta: float) -> void:
	for i: int in _props.size():
		var prop: AnimatedSprite2D = _props[i]
		prop.position.y += _speeds[i] * delta
		prop.position.x += DRIFT * FUNKIN_TO_RUBICON * delta
		if prop.position.y > SCREEN.y:
			_recycle(i, false)


## reloadProp: a prop that has fallen past the bottom picks a new drawing, a new x and a new
## speed rather than being freed and remade.
func _recycle(index: int, scatter: bool) -> void:
	var prop: AnimatedSprite2D = _props[index]
	var names: PackedStringArray = prop.sprite_frames.get_animation_names()
	prop.animation = names[randi() % names.size()]
	prop.play()

	prop.position.x = randf_range(0.0, SCREEN.x)
	# On the first pass they are already in the air rather than all queued above the top.
	prop.position.y = randf_range(0.0, SCREEN.y) if scatter \
		else randf_range(SPAWN_Y.x, SPAWN_Y.y) * FUNKIN_TO_RUBICON
	_speeds[index] = randf_range(FALL_SPEED.x, FALL_SPEED.y * SPEED_SPREAD) \
		* FUNKIN_TO_RUBICON * (HALF + randf() * HALF)
