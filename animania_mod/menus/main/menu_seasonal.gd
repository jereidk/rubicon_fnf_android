extends Node2D
## `animania.states.SeasonalEmitter`: what falls past the main menu, and when.
##
## WHEN is exact. MainMenuScreen.getCurrentSeason() reads Cardinal.currentMonth and returns
## one of three names - the months are `> 11` and `1..2` for `winter`, `9..11` for `autum`
## (five letters, the mod's own spelling) and everything else for `summer`. Only two of the
## three have art: seasonal/snow and seasonal/leafs. Summer gets nothing.
##
## WHAT it does is initParticle, which is compiled. The numbers below are its own, lifted
## from the doubles it loads: 250, +/-25, +/-65, 0.7, 0.8, 0.9, 1.0, 1.1 and 75. Which
## number lands in which field is this port's reading, the same way title_props.gd is - and
## each one says so.

## Derived exactly: the only large positive constant, and the only one that can be a speed.
const FALL_SPEED := 250.0
## The +/- pair that reads as a sideways drift.
const DRIFT := 25.0
## The other +/- pair, an order of magnitude bigger, which is degrees per second.
const SPIN := 65.0
## The four factors between 0.7 and 1.1, read as the range a particle is scaled by and the
## range it is faded by.
const SCALE_RANGE := Vector2(0.7, 1.1)
const ALPHA_RANGE := Vector2(0.8, 1.0)
## The remaining constant. Read here as how far above the top edge one starts.
const SPAWN_ABOVE := 75.0

## createSeasonalEffects builds the emitter from an anon (0x1808b5d) whose fields are
## `particleName`, `maxParticles`, `scaleMult`, `particleSpritePath` and `spawnValue`. Of
## those, scaleMult is readable straight off its Variant: 0.75 for autumn's leaves, and it
## multiplies the range initParticle picks.
const SCALE_MULT := 0.75

## STILL not derived: how many are in the air and how often one is let go. `maxParticles`
## and `spawnValue` are in that anon, but their Variants are passed by reference and the
## dump does not resolve them, so these two stay this port's.
const POOL := 24
const SPAWN_INTERVAL := 0.25

@export var snow_frames: SpriteFrames
@export var leaf_frames: SpriteFrames
## The screen the particles fall down. Set by the builder.
@export var area: Vector2 = Vector2(1920.0, 1080.0)
## Forced season for a harness; empty means "ask the calendar".
@export var season_override: String = ""

var _particles: Array[AnimatedSprite2D] = []
var _velocity: PackedVector2Array = []
var _spin: PackedFloat32Array = []
var _timer: float = 0.0
var _live: int = 0


## getCurrentSeason(), month for month.
static func season_of(month: int) -> String:
	if month > 11 or month <= 2:
		return "winter"
	if month > 8:
		return "autum"
	return "summer"


## The season this node is actually running, honouring the override. main_menu.gd asks for
## it so the camera grade and the falling art cannot end up disagreeing about the month.
func current_season() -> String:
	return season_override if not season_override.is_empty() \
		else season_of(Time.get_date_dict_from_system().get("month", 1))


func _ready() -> void:
	var season: String = current_season()
	var frames: SpriteFrames = snow_frames if season == "winter" \
		else (leaf_frames if season == "autum" else null)
	if frames == null:
		# Summer. The mod ships no art for it, so nothing falls.
		return

	for i: int in POOL:
		var particle := AnimatedSprite2D.new()
		particle.sprite_frames = frames
		particle.animation = frames.get_animation_names()[0]
		particle.visible = false
		particle.play()
		add_child(particle)
		_particles.append(particle)
		_velocity.append(Vector2.ZERO)
		_spin.append(0.0)


func _process(delta: float) -> void:
	if _particles.is_empty():
		return

	_timer += delta
	if _timer >= SPAWN_INTERVAL:
		_timer -= SPAWN_INTERVAL
		_spawn()

	for i: int in _particles.size():
		var particle: AnimatedSprite2D = _particles[i]
		if not particle.visible:
			continue
		particle.position += _velocity[i] * delta
		particle.rotation_degrees += _spin[i] * delta
		# recycleParticle: off the bottom is the end of it.
		if particle.position.y > area.y + SPAWN_ABOVE:
			particle.visible = false
			_live -= 1


## spawnParticle + initParticle: one is let go from above the top edge, somewhere across the
## width, drifting and spinning.
func _spawn() -> void:
	for i: int in _particles.size():
		var particle: AnimatedSprite2D = _particles[i]
		if particle.visible:
			continue
		particle.position = Vector2(randf_range(0.0, area.x), -SPAWN_ABOVE)
		particle.rotation_degrees = randf_range(0.0, 360.0)
		particle.scale = Vector2.ONE * randf_range(SCALE_RANGE.x, SCALE_RANGE.y) * SCALE_MULT
		particle.modulate.a = randf_range(ALPHA_RANGE.x, ALPHA_RANGE.y)
		particle.frame = randi_range(0, maxi(0, particle.sprite_frames.get_frame_count(
			particle.animation) - 1))
		particle.visible = true
		_velocity[i] = Vector2(randf_range(-DRIFT, DRIFT), FALL_SPEED)
		_spin[i] = randf_range(-SPIN, SPIN)
		_live += 1
		return
