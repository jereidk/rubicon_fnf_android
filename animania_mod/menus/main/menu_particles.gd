extends Node2D
## createParticles (0x17fb440), which this port did not have at all.
##
## An FlxTypedEmitter, and the reason it sat unported for a while is that its settings go
## through `set` calls on a field pointer the disassembly does not name. What names them is
## that hxcpp returns the bounds object for chaining, so the hidden return slot takes `rdi`
## and **`rsi` is the field being configured** - read `rdi` and every one of them looks like
## the same anonymous temporary. With `rsi` read instead, the offsets fall straight onto
## FlxTypedEmitter's declaration order:
##
##     0x0a8  velocity  FlxPointRangeBounds   set(-450, 0, -300, 300)
##     0x0e8  lifespan  FlxBounds             set(2, 4)
##     0x0f0  scale     FlxPointRangeBounds   set(0.35, 0.35, 0.1, 0.1)
##     0x0f8  alpha     FlxRangeBounds        set(0.9, 1, 0, 0)
##     0x100  color     FlxRangeBounds        set(white, white, cyan, pink)
##     0x108  drag      FlxPointRangeBounds   set(-200, 10, 300, -300)
##
## The argument order is hxcpp's right-to-left evaluation: the LAST parameter is the first
## Dynamic built. That is what makes alpha read as 0.9-to-1 fading to 0 rather than the
## nonsense it looks like taken forwards, and it is the check that the reading is right -
## a fade-out is what a particle does.
##
## Emitter at (750, -150), above the screen and right of centre, streaming one particle
## every 0.09s. Negative drag on x is not a misreading: in Flixel drag pulls a velocity
## toward zero, so a negative one pushes it away, and these specks accelerate leftwards.

const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const WORLD_OFFSET := Vector2(-4.0, -37.0)

const ART := "res://animania_mod/source/images/menus/particle.png"
const EMITTER_POS := Vector2(750.0, -150.0)
const VELOCITY_X := Vector2(-450.0, 0.0)
const VELOCITY_Y := Vector2(-300.0, 300.0)
const DRAG_X := Vector2(-200.0, 10.0)
const DRAG_Y := Vector2(-300.0, 300.0)
const LIFESPAN := Vector2(2.0, 4.0)
const SCALE_FROM := 0.35
const SCALE_TO := 0.1
const ALPHA_FROM := Vector2(0.9, 1.0)
const ALPHA_TO := 0.0
const COLOR_FROM := Color(1.0, 1.0, 1.0)
const COLOR_TO_A := Color(0.0, 1.0, 1.0)
const COLOR_TO_B := Color(1.0, 192.0 / 255.0, 203.0 / 255.0)
const FREQUENCY := 0.09
## Anything past this is off screen for good; Flixel recycles by lifespan alone but a cap
## keeps a paused or backgrounded menu from piling them up.
const MAX_ALIVE := 96

var _tex: Texture2D = null
var _since: float = 0.0
## [node, velocity, drag, age, life, scale_base, alpha_from, colour_to]
var _live: Array = []


func _ready() -> void:
	if ResourceLoader.exists(ART):
		_tex = load(ART) as Texture2D


func _process(delta: float) -> void:
	if _tex == null:
		return
	_since += delta
	while _since >= FREQUENCY:
		_since -= FREQUENCY
		_emit()
	_advance(delta)


func _emit() -> void:
	if _live.size() >= MAX_ALIVE:
		return
	var sprite := Sprite2D.new()
	sprite.texture = _tex
	sprite.centered = true
	sprite.position = _world(EMITTER_POS)
	add_child(sprite)

	var life: float = randf_range(LIFESPAN.x, LIFESPAN.y)
	var alpha: float = randf_range(ALPHA_FROM.x, ALPHA_FROM.y)
	var tint: Color = COLOR_TO_A.lerp(COLOR_TO_B, randf())
	_live.append({
		"node": sprite,
		"vel": Vector2(randf_range(VELOCITY_X.x, VELOCITY_X.y),
			randf_range(VELOCITY_Y.x, VELOCITY_Y.y)),
		"drag": Vector2(randf_range(DRAG_X.x, DRAG_X.y),
			randf_range(DRAG_Y.x, DRAG_Y.y)),
		"age": 0.0,
		"life": life,
		"alpha": alpha,
		"tint": tint,
	})


## Flixel's own integration: drag is applied against the sign of the velocity and never
## carries it past zero, which is why a negative one accelerates instead of stopping.
func _advance(delta: float) -> void:
	var still: Array = []
	for p: Dictionary in _live:
		var sprite: Sprite2D = p["node"]
		if not is_instance_valid(sprite):
			continue
		p["age"] = float(p["age"]) + delta
		var t: float = clampf(float(p["age"]) / float(p["life"]), 0.0, 1.0)
		if t >= 1.0:
			sprite.queue_free()
			continue
		var vel: Vector2 = p["vel"]
		var drag: Vector2 = p["drag"]
		vel.x = _drag_axis(vel.x, drag.x, delta)
		vel.y = _drag_axis(vel.y, drag.y, delta)
		p["vel"] = vel
		sprite.position += vel * delta * FUNKIN_TO_RUBICON
		var s: float = lerpf(SCALE_FROM, SCALE_TO, t)
		sprite.scale = Vector2.ONE * s * FUNKIN_TO_RUBICON
		var tint: Color = COLOR_FROM.lerp(p["tint"], t)
		tint.a = lerpf(float(p["alpha"]), ALPHA_TO, t)
		sprite.modulate = tint
		still.append(p)
	_live = still


func _drag_axis(v: float, drag: float, delta: float) -> float:
	var step: float = drag * delta
	if v > 0.0:
		return maxf(v - step, 0.0) if step > 0.0 else v - step
	if v < 0.0:
		return minf(v + step, 0.0) if step > 0.0 else v + step
	return v


func _world(p: Vector2) -> Vector2:
	return (p + WORLD_OFFSET) * FUNKIN_TO_RUBICON
