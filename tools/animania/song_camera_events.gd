@tool
extends RefCounted
## Bakes a chart's camera events into the level clock's "scene" animation, for any song.
##
## camera_events.gd is phone-call's: it hardcodes 152 BPM and carries that song's own
## script beats, its title card and its punch track. This one carries nothing but the
## chart, and takes the tempo as an argument - so dadbattle's 98 events work the same way
## phone-call's 103 do without either builder learning about the other.
##
## Funkin drives the camera in two stages and only the FIRST is baked here:
##
##   1. an event tweens a target - `cameraFollowPoint`, `currentCameraZoom` - over a
##      duration with a named ease;
##   2. every frame the camera lerps toward that target at a fixed rate, which Rubicon's
##      interpolated camera already does with a near-identical default.
##
## The eases are baked as SAMPLED linear keys rather than mapped onto Godot's per-key
## transition exponent: a transition curve cannot express elasticInOut at all, and sampling
## reproduces every one of them without having to argue about which is close enough.

## How finely an eased tween is sampled. 24 keys a second is the art's own frame rate and
## is finer than the camera's own lerp can resolve.
const SAMPLES_PER_SECOND := 24.0
const SCREEN := Vector2(1920.0, 1080.0)
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

var _focus_points: Dictionary
var _base_zoom: float
var _step_seconds: float


## `focus_points` is keyed by Funkin's `char` index: 0 boyfriend, 1 dad, 2 girlfriend.
## `step_seconds` is one sixteenth of a beat - Funkin measures an event's `duration` in
## STEPS, not seconds or beats, which is the single easiest thing to get wrong here.
func _init(focus_points: Dictionary, base_zoom: float, bpm: float) -> void:
	_focus_points = focus_points
	_base_zoom = base_zoom
	_step_seconds = 60.0 / bpm / 4.0


func build(events: Array, length: float, into: Animation) -> Animation:
	into.length = length

	var focus := _track(into, ^"../RubiconInterpolatedCamera2D:position_interpolate_target")
	var zoom := _track(into, ^"../RubiconInterpolatedCamera2D:zoom_interpolate_target")
	var angle := _track(into, ^"../RubiconInterpolatedCamera2D:rotation_interpolate_target")
	# A shake moves the camera OFF its target rather than moving the target, which is what
	# FlxCamera.shake does - and it means a shake and a focus move can happen at once
	# without one eating the other.
	var shake := _track(into, ^"../RubiconInterpolatedCamera2D:position_interpolate_offset")
	into.track_insert_key(shake, 0.0, Vector2.ZERO)
	into.track_insert_key(angle, 0.0, 0.0)
	# The letterbox, and the two things SetCameraBop sets on the beat bump.
	var bar_top := _track(into, ^"../CinematicBars/Top:size")
	var bar_bottom := _track(into, ^"../CinematicBars/Bottom:size")
	var bop_rate := _track(into, ^"../SongCamera:bump_every_beats")
	var bop_scale := _track(into, ^"../SongCamera:bump_scale")
	into.track_insert_key(bar_top, 0.0, Vector2(SCREEN.x, 0.0))
	into.track_insert_key(bar_bottom, 0.0, Vector2(SCREEN.x, 0.0))

	var at_position: Vector2 = _focus_points.get(1, Vector2.ZERO)
	var at_zoom: float = _base_zoom
	var at_angle: float = 0.0
	var at_bar_top: float = 0.0
	var at_bar_bottom: float = 0.0
	var shakes: int = 0
	var wrote_focus: int = 0
	var wrote_zoom: int = 0

	# The chart's own order is not guaranteed to be by time.
	var sorted: Array = events.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))

	for event: Dictionary in sorted:
		var time: float = float(event.get("t", 0.0)) / 1000.0
		var values: Dictionary = event.get("v", {})
		var seconds: float = float(values.get("duration", 0)) * _step_seconds
		var ease_name: String = String(values.get("ease", "linear"))
		var ease_dir: String = String(values.get("easeDir", "In"))

		match String(event.get("e", "")):
			"FocusCamera":
				var base: Vector2 = _focus_points.get(
					int(values.get("char", 1)), at_position)
				# The event's x/y are world-space pixels and this port keeps world
				# coordinates verbatim - the 1.5 lives on the camera's zoom, so these are
				# NOT scaled. Scaling them was what put empty stage in frame in phone-call.
				var to: Vector2 = base + Vector2(
					float(values.get("x", 0.0)), float(values.get("y", 0.0)))
				wrote_focus += _sample(into, focus, time, seconds, at_position, to,
					ease_name, ease_dir)
				at_position = to
			"ZoomCamera":
				var to_zoom: float = float(values.get("zoom", 1.0)) * _base_zoom
				wrote_zoom += _sample(into, zoom, time, seconds,
					Vector2.ONE * at_zoom, Vector2.ONE * to_zoom, ease_name, ease_dir)
				at_zoom = to_zoom
			"AngleCamera":
				# Funkin's angle is degrees and Godot's rotation is radians. The delay is
				# part of the event, not of the tween.
				var to_angle: float = deg_to_rad(float(values.get("angle", 0.0)))
				var delay: float = float(values.get("delay", 0)) * _step_seconds
				_sample_float(into, angle, time + delay, seconds, at_angle, to_angle,
					ease_name, ease_dir)
				at_angle = to_angle
			"ScreenShake":
				# FlxCamera.shake(intensity, duration): the intensity is a FRACTION of the
				# camera's size, not pixels, so it is against Funkin's 1280x720 - and this
				# port keeps world coordinates verbatim, so it stays in that space.
				var strength: float = float(values.get("gameIntensity", 0.0)) * 1280.0
				var span: float = float(values.get("gameTime", 0.0))
				shakes += _shake(into, shake, time, span, strength)
			"SetCameraBop":
				# Discrete: a rate is a whole number of beats and there is nothing to ease.
				into.track_insert_key(bop_rate, time, int(values.get("rate", 4)))
				into.track_insert_key(bop_scale, time,
					float(values.get("intensity", 1.0)))
			"CinematicBars":
				# upTime/downTime are SECONDS here, not steps - 1.25 and 0.5 are what the
				# chart carries and no tempo makes those a whole number of sixteenths. The
				# bars are screen-space, so their height IS scaled by the 1.5.
				var top_to: float = float(values.get("upY", 0.0)) * FUNKIN_TO_RUBICON
				var bottom_to: float = float(values.get("downY", 0.0)) * FUNKIN_TO_RUBICON
				_sample_size(into, bar_top, time, float(values.get("upTime", 0.0)),
					at_bar_top, top_to, String(values.get("upEase", "linear")),
					String(values.get("easeDirup", "In")))
				_sample_size(into, bar_bottom, time, float(values.get("downTime", 0.0)),
					at_bar_bottom, bottom_to, String(values.get("downEase", "linear")),
					String(values.get("easeDirdown", "In")))
				at_bar_top = top_to
				at_bar_bottom = bottom_to
			"AddCameraZoom":
				# A punch, not a move: it adds and the camera's own lerp takes it back.
				var punch: float = at_zoom * (1.0 + float(values.get("gameZoom", 0.0)))
				into.track_insert_key(zoom, time, Vector2.ONE * punch)
				into.track_insert_key(zoom, time + 0.25, Vector2.ONE * at_zoom)
				wrote_zoom += 2

	print("OUT camara horneada: %d claves de foco, %d de zoom, %d de sacudida"
		% [wrote_focus, wrote_zoom, shakes])
	return into


func _track(animation: Animation, path: NodePath) -> int:
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	return track


## One eased tween, as sampled linear keys. A zero-length one is a single key.
func _sample(animation: Animation, track: int, time: float, seconds: float,
		from: Vector2, to: Vector2, ease_name: String, ease_dir: String) -> int:
	if seconds <= 0.0:
		animation.track_insert_key(track, time, to)
		return 1
	var steps: int = maxi(2, int(ceil(seconds * SAMPLES_PER_SECOND)))
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		animation.track_insert_key(track, time + seconds * t,
			from.lerp(to, _ease(t, ease_name, ease_dir)))
	return steps + 1


## The eases the charts actually name. Anything unrecognised stays linear rather than being
## approximated by whichever curve looks closest - a wrong curve is harder to notice than a
## straight line, and this prints so it can be added.
static var _warned: Dictionary = {}


func _ease(t: float, name: String, dir: String) -> float:
	match name.to_lower():
		"linear", "classic", "classiclerp":
			return t
		"sine":
			return _directed(t, dir, func(x: float) -> float:
				return 1.0 - cos(x * PI * 0.5))
		"quad":
			return _directed(t, dir, func(x: float) -> float: return x * x)
		"cubic", "cube":
			return _directed(t, dir, func(x: float) -> float: return x * x * x)
		"quart":
			return _directed(t, dir, func(x: float) -> float: return x * x * x * x)
		"expo":
			return _directed(t, dir, func(x: float) -> float:
				return 0.0 if is_zero_approx(x) else pow(2.0, 10.0 * (x - 1.0)))
		"circ":
			return _directed(t, dir, func(x: float) -> float:
				return 1.0 - sqrt(1.0 - x * x))
		"instant":
			# Not a curve: the target jumps at the start and stays.
			return 1.0
		"smoothstep":
			return t * t * (3.0 - 2.0 * t)
		"smootherstep":
			return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
		_:
			if not _warned.has(name):
				_warned[name] = true
				print("OUT ease '%s' sin portear, se hornea lineal" % name)
			return t


## Funkin names the direction separately: In is the curve, Out is its mirror, InOut is the
## two halves.
func _directed(t: float, dir: String, curve: Callable) -> float:
	match dir.to_lower():
		"out":
			return 1.0 - float(curve.call(1.0 - t))
		"inout":
			return 0.5 * float(curve.call(t * 2.0)) if t < 0.5 \
				else 1.0 - 0.5 * float(curve.call((1.0 - t) * 2.0))
		_:
			return curve.call(t)


## The same sampler for a scalar track.
func _sample_float(animation: Animation, track: int, time: float, seconds: float,
		from: float, to: float, ease_name: String, ease_dir: String) -> void:
	if seconds <= 0.0:
		animation.track_insert_key(track, time, to)
		return
	var steps: int = maxi(2, int(ceil(seconds * SAMPLES_PER_SECOND)))
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		animation.track_insert_key(track, time + seconds * t,
			lerpf(from, to, _ease(t, ease_name, ease_dir)))


## A shake, baked. Flixel picks a new random offset every frame and fades it out over the
## duration; this samples the same thing at 24 a second and lands back on zero, so a shake
## that is interrupted by the next event does not leave the camera off its mark.
func _shake(animation: Animation, track: int, time: float, seconds: float,
		strength: float) -> int:
	if seconds <= 0.0 or is_zero_approx(strength):
		return 0
	var rng := RandomNumberGenerator.new()
	# Seeded off the event time so a rebuild produces the same shake, which keeps the
	# scene diffable.
	rng.seed = int(time * 1000.0)
	var steps: int = maxi(2, int(ceil(seconds * SAMPLES_PER_SECOND)))
	for i: int in steps:
		var t: float = float(i) / float(steps)
		var fade: float = 1.0 - t
		animation.track_insert_key(track, time + seconds * t, Vector2(
			rng.randf_range(-strength, strength) * fade,
			rng.randf_range(-strength, strength) * fade))
	animation.track_insert_key(track, time + seconds, Vector2.ZERO)
	return steps + 1


## A bar's height, as a size on a full-width rect.
func _sample_size(animation: Animation, track: int, time: float, seconds: float,
		from: float, to: float, ease_name: String, ease_dir: String) -> void:
	if seconds <= 0.0:
		animation.track_insert_key(track, time, Vector2(SCREEN.x, to))
		return
	var steps: int = maxi(2, int(ceil(seconds * SAMPLES_PER_SECOND)))
	for i: int in steps + 1:
		var t: float = float(i) / float(steps)
		animation.track_insert_key(track, time + seconds * t,
			Vector2(SCREEN.x, lerpf(from, to, _ease(t, ease_name, ease_dir))))
