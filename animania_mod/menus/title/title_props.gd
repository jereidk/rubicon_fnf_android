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
## Re-read against the closure at 0x2b258f0. The constant list this file used to carry was
## partly guessed - it claimed "-550, 400" where the packed `Null<int>` immediates are -550
## and **-440**, and it was missing half of them. The measured set:
##
##     doubles  -300.0, 0.85, 1.15, 1.6, 2.05, 110.0, 50.0, 0.8, 0.7, 0.5
##     ints     10, 200, -10, -200, -440, -550, 0
##
## Two of those now have a job rather than a shrug:
##
##     277  var jitter = FlxG.random.float(0.85, 1.15);
##     278  scale.set(s, s) where s = <ratio> * 0.8 + 0.7, then s *= jitter
##     279  updateHitbox();
##     283  speed = 110.0 / ((width + height) * 0.5) * ... * s
##
## Line 283 is unambiguous in the dump - get_width (0x230), get_height (0x238), added, times
## 0.5, divided into 110 - so **a bigger prop falls slower**. This file used a flat 50-110
## range and had no size term at all.
##
## What the ratio in line 278 divides is still unresolved, so the base scale here is a random
## in the range that formula spans (0.7 to 1.5) rather than the formula itself.
##
## Derived structurally: one FlxTypedGroup of TitleProp, recycled rather than respawned
## (TitleProp's only method is `reloadProp`), six integer randoms and one float per pass.

const SCREEN := Vector2(1920.0, 1080.0)
## Funkin is 1280x720 and this project is 1920x1080; these are screen distances.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## Spawned above the top edge, between the two negative y values the code carries.
const SPAWN_Y := Vector2(-300.0, -200.0)
## The 110 line 283 divides by the prop's average dimension, and the 50 beside it.
const FALL_NUMERATOR := 110.0
const FALL_BASE := 50.0
## The multiplier the fall is scaled by, and the half that pairs with it.
const SPEED_SPREAD := 1.6
const HALF := 0.5
## The small negative, read here as the drift a prop carries sideways as it falls.
const DRIFT := -10.0
## The float random line 277 varies each prop by, and the span line 278's formula covers.
const SIZE_JITTER := Vector2(0.85, 1.15)
const SIZE_SPAN := Vector2(0.7, 1.5)

## create() line 167 allocates SIX TitleProps, each parked at -1000000 until updateProps
## places it. This file used to say nine and that the number was not derivable; it is, and
## it is in create().
const POOL := 6

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

	# Line 278: a base scale over the span its formula covers, then the 0.85-1.15 jitter.
	var size: float = randf_range(SIZE_SPAN.x, SIZE_SPAN.y) \
		* randf_range(SIZE_JITTER.x, SIZE_JITTER.y)
	prop.scale = Vector2.ONE * size * FUNKIN_TO_RUBICON

	prop.position.x = randf_range(0.0, SCREEN.x)
	# On the first pass they are already in the air rather than all queued above the top.
	prop.position.y = randf_range(0.0, SCREEN.y) if scatter \
		else randf_range(SPAWN_Y.x, SPAWN_Y.y) * FUNKIN_TO_RUBICON

	# Line 283 divides 110 by the prop's average dimension, so a bigger prop falls slower.
	# The two factors that multiply into it are not resolved, so what is taken from the line
	# is the SHAPE - speed inversely proportional to size - normalised on the prop's own art
	# so it comes out as `1 / scale`. That keeps the mod's relationship without inventing a
	# pixel constant to make the units work, which a first attempt here did: it put an
	# average prop at 4600 px/s, across the screen in a quarter of a second.
	_speeds[index] = randf_range(FALL_BASE, FALL_NUMERATOR * SPEED_SPREAD) \
		* FUNKIN_TO_RUBICON * (HALF + randf() * HALF) / maxf(0.1, size)
