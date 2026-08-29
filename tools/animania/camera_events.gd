@tool
extends RefCounted
## Turns the chart's events into animation tracks on the level clock's player.
##
## Funkin drives its camera in two stages, and reproducing both is what makes this look
## like the original rather than approximately like it:
##
##   1. an event TWEENS a target - `currentCameraZoom`, or `cameraFollowPoint` - over a
##      duration, with a named ease;
##   2. every frame the camera lerps toward that target at a fixed rate
##      (`FlxMath.lerp(target, current, 0.95)`, which at 60fps is a Godot
##      `position/zoom_interpolate_speed` of about 3.0 - near enough to Rubicon's own
##      default of 3.125 that the second stage needs no porting at all).
##
## So only stage 1 is baked here, into `position_interpolate_target` and
## `zoom_interpolate_target`, and the camera's own lerp does stage 2 exactly as Flixel's
## does. The eases are BAKED as sampled linear keys rather than mapped onto Godot's
## per-key transition exponent: a transition curve cannot express elasticInOut at all, and
## sampling reproduces every one of them without having to argue about which is close
## enough.
##
## This deliberately does not use RubiconPositionSetter. That node picks between NAMED
## points, which is the right shape for a level that alternates between two singers on the
## measure; this song authors 20 camera moves with their own offsets, durations and eases,
## which is strictly more than a name can carry.
##
## No class_name on purpose: Godot's global class cache only updates on an editor import,
## and everything in tools/animania/ runs headless, so this is loaded by path.

# 152 BPM, 4/4. Funkin measures a camera event's `duration` in STEPS, not seconds or beats.
const STEP_SECONDS := 60.0 / 152.0 / 4.0

# Funkin is 1280x720 and this project is 1920x1080. Camera OFFSETS are distances on
# screen, so unlike the world coordinates elsewhere in this port they do scale.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## How finely a tween is sampled. 50ms is 20 keys a second - finer than the eye, and finer
## than the camera's own lerp can follow anyway.
const SAMPLE_SECONDS := 0.05
const MAX_SAMPLES := 96

## How far before the next event a value is pinned.
##
## Not smaller, and the reason is worth writing down: Animation::_insert decides two keys
## are the same key with Math::is_equal_approx, whose tolerance is RELATIVE -
## CMP_EPSILON * abs(time), floored at CMP_EPSILON - so the further into a song a key sits,
## the wider the window in which it silently overwrites its neighbour. At t = 97.89 the
## tolerance is 0.00098 and a 0.001 gap survives; at t = 104.21 it is 0.00104 and the same
## gap collapses into one key. That is exactly where this port started dropping its pins:
## every camera event before ~100s was fine and every one after it drifted, because the
## pin had been eaten by the key it was supposed to sit in front of. Measured, not guessed:
## two keys 0.001 apart give 2 keys at t=97.8947 and 1 key at t=104.2105.
const HOLD_MARGIN := 0.005

## Funkin's own per-frame camera lerp, in Godot's terms.
const FUNKIN_LERP_SPEED := 3.0

## `ease: "INSTANT"` means the camera is already there.
const INSTANT_SPEED := 1000.0

const CAMERA := ^"../RubiconInterpolatedCamera2D"
## The node the method tracks call into; the punch track already points here.
const CAMERA_EVENTS := ^"../PhoneCallEvents"

## phone-call.script's onBeatHit, the parts that are structure rather than tweens and
## modcharts. Beat 232 is standUP(): both characters swap to their standing versions and
## every prop on the stage inverts its visibility.
const SCRIPT_BEATS := [
	# onCreatePost, and case 0: black screen, no HUD, and the two strumlines swapped over
	# with the opponent's parked off the right edge.
	[0, "opening", []],
	# The title card fades up, and out again ten beats later.
	[1, "intro_show_text", []],
	[11, "intro_hide_text", []],
	# The cover comes off and tadano walks in.
	[13, "intro_reveal", []],
	# camGame.shake(.0005, .8) - a rumble on three beat accents.
	[16, "shake", [0.0005, 0.8]],
	[19, "shake", [0.0005, 0.8]],
	[23, "shake", [0.0005, 0.8]],
	# The HUD arrives, twenty milliseconds before the first player note.
	[31, "hud_in", []],
	# The opponent's lanes fly in from off-screen; tadano slides into the offset the
	# chart's FocusCamera on the same beat already carries.
	[166, "opponent_lanes_in", []],
	[168, "boyfriend_slide", []],
	# Both characters swap to their standing versions and the stage inverts. The opponent's
	# lanes finish arriving in the same call: two method keys at one time collapse into one.
	[232, "stand_up", []],
	# The HUD leaves, and then the screen does.
	[332, "hud_out", []],
	[348, "fade_out", [3.0]],
]


var _focus_points: Dictionary = {}
var _stand_focus_points: Dictionary = {}
var _stand_from: float = INF
var _base_zoom: float = 1.0
var _bar_scale: float = FUNKIN_TO_RUBICON


func _init(focus_points: Dictionary, base_zoom: float,
		stand_focus_points: Dictionary = {}, stand_from: float = INF) -> void:
	# Keyed by Funkin's `char` index: 0 boyfriend, 1 dad, 2 girlfriend. Each value is the
	# point the camera aims at with no event offset - the character's midpoint plus its
	# own cameraOffsets.
	_focus_points = focus_points
	# After standUP() the same `char` index means a DIFFERENT character standing somewhere
	# else. Funkin gets this for free, since the camera follows getBoyfriend()/getDad() and
	# those now return the standing pair; a baked track has to switch tables by time.
	_stand_focus_points = stand_focus_points
	_stand_from = stand_from
	_base_zoom = base_zoom


## Builds the clock's "scene" animation out of the chart's events.
func build(events: Array, length: float) -> Animation:
	var animation := Animation.new()
	animation.length = length
	animation.step = 0.01

	var position_track: int = _value_track(animation, NodePath("%s:position_interpolate_target" % CAMERA))
	# An INSTANT focus is a ONE-SHOT, so it cannot be a value track. A value track writes
	# its property every frame - between keys it interpolates, and past its last key it
	# clamps - so a `:position` track does not snap the camera, it PINS it: it overwrote
	# the interpolated camera every frame all song, and at 9.2s left it 579px from its own
	# target, still sliding toward the next INSTANT nineteen events away. Measured against
	# a capture of the original that put the whole stage 706px off.
	#
	# A method key fires once and then leaves the property alone, which is what a snap is.
	# It gets a track of its own rather than sharing the punch track: the chart's two
	# INSTANT focuses land at 0.0s and 91.5789s, which are exactly `opening` and `stand_up`
	# on the script-beat table, and two method keys at one time on ONE track collapse into
	# one. Two tracks keep both.
	var snap_track: int = animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(snap_track, CAMERA_EVENTS)
	var zoom_track: int = _value_track(animation, NodePath("%s:zoom_interpolate_target" % CAMERA))
	var speed_track: int = _value_track(animation, NodePath("%s:position_interpolate_speed" % CAMERA))
	var top_track: int = _value_track(animation, ^"../CinematicBars/Top:size")
	var bottom_track: int = _value_track(animation, ^"../CinematicBars/Bottom:size")
	var bottom_y_track: int = _value_track(animation, ^"../CinematicBars/Bottom:position")

	var punch_track: int = animation.add_track(Animation.TYPE_METHOD)
	animation.track_set_path(punch_track, CAMERA_EVENTS)

	# Every track here is LINEAR, so a value has to be PINNED at the end of its tween or it
	# slides straight on toward the next event's first key. That is not a rounding error:
	# a CLASSIC focus, which is a single key with no tween at all, was arriving 211px short
	# of its target because the track had already started interpolating away from it.
	# _hold() writes the flat segment between one event and the next of its kind.
	#
	# When Funkin starts a tween it CANCELS the one already running on that property, so a
	# baked tween has to stop where the next event of its kind begins. Without this the old
	# tween's remaining keys keep writing past the new event and the two interleave on the
	# track - which is what made the first version of this drift by up to 200px on a focus
	# and 0.13 on a zoom. The value carried forward is the truncated one, because that is
	# where Funkin's next tween starts from too.
	var next_of_kind: Dictionary = {}
	for i: int in range(events.size() - 1, -1, -1):
		var kind_at: String = events[i]["e"]
		next_of_kind[i] = float(next_of_kind.get("last_%s" % kind_at, INF))
		next_of_kind["last_%s" % kind_at] = float(events[i]["t"]) / 1000.0

	# phone-call.script acts on beats as well as on chart events, and those beats are not in
	# the chart at all - standUP() at 232 is the biggest thing that happens in the song and
	# nothing in phone-call-chart.json mentions it. 152bpm, so a beat is 60/152 seconds.
	for entry: Array in SCRIPT_BEATS:
		animation.track_insert_key(punch_track, float(entry[0]) * 60.0 / 152.0, {
			"method": StringName(entry[1]), "args": entry[2],
		})

	var counts: Dictionary = {}
	var focus: Vector2 = _focus_points[1]
	var zoom: float = _base_zoom
	var speed: float = FUNKIN_LERP_SPEED

	# No snap key here: the camera scene is already built sitting on the opponent's point,
	# and the chart's first event is an INSTANT focus at 0.0s that would collide with it.
	animation.track_insert_key(position_track, 0.0, focus)
	animation.track_insert_key(zoom_track, 0.0, Vector2.ONE * zoom)
	animation.track_insert_key(speed_track, 0.0, speed)
	_bars(animation, top_track, bottom_track, bottom_y_track, 0.0, 0.0, 0.0, 0.0, "linear")

	for index: int in events.size():
		var event: Dictionary = events[index]
		var kind: String = event["e"]
		var time: float = float(event["t"]) / 1000.0
		var value: Dictionary = event["v"]
		# A tween is also cut short by the end of the song: the chart's last FocusCamera and
		# ZoomCamera both run 96 steps (9.5s) from 135.8s, and the instrumental stops 6.4s
		# into them. Clamping here spends the sampling on the part that actually plays.
		var cutoff: float = minf(float(next_of_kind[index]), length)
		counts[kind] = int(counts.get(kind, 0)) + 1

		match kind:
			"FocusCamera":
				var character: int = int(value.get("char", 0))
				if not _focus_points.has(character):
					push_error("FocusCamera nombra char=%d, que no existe" % character)
					continue

				var points: Dictionary = _stand_focus_points \
					if time >= _stand_from and _stand_focus_points.has(character) \
					else _focus_points
				# The event's x/y are WORLD offsets in Funkin pixels, and this port keeps
				# world coordinates verbatim - the 1.5 lives on the camera's zoom. They were
				# being scaled by it, which put every focus 1.5x its own offset from the
				# character it names; the largest in this chart is 350, so up to 175px out.
				var target: Vector2 = points[character] + Vector2(
					float(value.get("x", 0)), float(value.get("y", 0)))
				var ease_name: String = str(value.get("ease", "CLASSIC"))
				var duration: float = float(value.get("duration", 4)) * STEP_SECONDS

				if ease_name == "INSTANT":
					# Writing `position` sets where the camera IS; _process carries on
					# lerping from there, so target plus position is a real snap.
					animation.track_insert_key(position_track, time, target)
					animation.track_insert_key(snap_track, time, {
						"method": &"snap_camera", "args": [target],
					})
					focus = target
				elif ease_name == "CLASSIC":
					# Funkin's classic follow has no tween: the target jumps and the
					# camera's own lerp is the whole of the movement.
					animation.track_insert_key(position_track, time, target)
					focus = target
				else:
					focus = _bake(animation, position_track, time, duration, focus, target,
						ease_name, str(value.get("easeDir", "Out")), cutoff)
				_hold(animation, position_track, cutoff, focus)

			"ZoomCamera":
				# mode is "stage" on every one of this chart's 55, i.e. the game camera and
				# not the HUD. The zoom value is a MULTIPLIER on the stage's own
				# cameraZoom, which is why they all sit around 1.0.
				if str(value.get("mode", "stage")) != "stage":
					continue
				var target_zoom: float = _base_zoom * float(value.get("zoom", 1.0))
				var duration: float = float(value.get("duration", 4)) * STEP_SECONDS
				var ease_name: String = str(value.get("ease", "cube"))

				if ease_name == "INSTANT":
					animation.track_insert_key(zoom_track, time, Vector2.ONE * target_zoom)
					zoom = target_zoom
				else:
					zoom = _bake_zoom(animation, zoom_track, time, duration, zoom,
						target_zoom, ease_name, str(value.get("easeDir", "Out")), cutoff)
				_hold(animation, zoom_track, cutoff, Vector2.ONE * zoom)

			"AddCameraZoom":
				# A one-shot punch, not a setting: the bumper's own bump does `zoom +=`,
				# and _process eases it back. The giveaway is that the first one is 0.05
				# at 6.5s, during the stretch where SetCameraBop has the automatic bop
				# turned off - a manual accent where the automatic one cannot reach.
				animation.track_insert_key(punch_track, time, {
					"method": &"punch",
					"args": [float(value.get("gameZoom", 0.015)),
						float(value.get("hudZoom", 0.03))],
				})

			"SetCameraBop":
				animation.track_insert_key(punch_track, time, {
					"method": &"set_bop",
					"args": [int(value.get("rate", 4)), float(value.get("intensity", 1.0))],
				})

			"PlayAnimation":
				animation.track_insert_key(punch_track, time, {
					"method": &"play_character_animation",
					"args": [StringName(str(value.get("target", "dad"))),
						StringName(str(value.get("anim", "idle"))),
						bool(value.get("force", false))],
				})

			"SetProperty":
				# The only one this chart uses is boyfriend.idleSuffix, and it is what pulls
				# tadano's whole alt pose set into play for the back half of the song.
				var property: String = str(value.get("target", ""))
				if not property.ends_with(".idleSuffix"):
					push_warning("SetProperty sin traducir: %s" % property)
					continue
				animation.track_insert_key(punch_track, time, {
					"method": &"set_idle_suffix",
					"args": [StringName(property.get_slice(".", 0)),
						str(value.get("value", ""))],
				})

			"CinematicBars":
				_bars(animation, top_track, bottom_track, bottom_y_track, time,
					float(value.get("upY", 0)), float(value.get("upTime", 0.5)),
					float(value.get("downY", 0)), str(value.get("upEase", "linear")),
					cutoff)

	for kind: String in counts:
		print("OUT %-16s x%d" % [kind, counts[kind]])
	return animation


func _value_track(animation: Animation, path: NodePath) -> int:
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	return track


## Returns the value the tween actually reached, which is the target unless it was cut
## short by the next event of the same kind.
func _bake(animation: Animation, track: int, time: float, duration: float,
		from: Vector2, to: Vector2, ease_name: String, direction: String,
		cutoff: float) -> Vector2:
	var span: float = _span(time, duration, cutoff)
	var samples: int = clampi(ceili(span / SAMPLE_SECONDS), 2, MAX_SAMPLES)
	var reached: Vector2 = from
	for i: int in range(samples + 1):
		var ratio: float = float(i) / float(samples)
		reached = from.lerp(to, _ease(ratio * span / duration, ease_name, direction))
		animation.track_insert_key(track, time + span * ratio, reached)
	return reached


func _bake_zoom(animation: Animation, track: int, time: float, duration: float,
		from: float, to: float, ease_name: String, direction: String,
		cutoff: float) -> float:
	var span: float = _span(time, duration, cutoff)
	var samples: int = clampi(ceili(span / SAMPLE_SECONDS), 2, MAX_SAMPLES)
	var reached: float = from
	for i: int in range(samples + 1):
		var ratio: float = float(i) / float(samples)
		reached = lerpf(from, to, _ease(ratio * span / duration, ease_name, direction))
		animation.track_insert_key(track, time + span * ratio, Vector2.ONE * reached)
	return reached


## Pins a track's value flat from wherever its last key is up to the moment the next event
## of that kind takes over. Without it a LINEAR track starts sliding toward the next
## event's first key the instant the current tween's last key passes.
func _hold(animation: Animation, track: int, until: float, value: Variant) -> void:
	var count: int = animation.track_get_key_count(track)
	if count == 0:
		return

	var end: float = until if until < INF else animation.length
	var last: float = animation.track_get_key_time(track, count - 1)
	if end - HOLD_MARGIN <= last:
		return

	animation.track_insert_key(track, end - HOLD_MARGIN, value)


func _span(time: float, duration: float, cutoff: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(cutoff - time, 0.0, duration)


## Letterbox bars. upY and downY are the two bar heights in Funkin pixels; in this chart
## they are equal in all seven events, but they are kept separate because the format allows
## them to differ. The bottom bar is a ColorRect anchored at the top of the screen, so it
## has to be moved as well as resized.
func _bars(animation: Animation, top: int, bottom: int, bottom_y: int, time: float,
		up_height: float, duration: float, down_height: float, ease_name: String,
		cutoff: float = INF) -> void:
	var span: float = _span(time, duration, cutoff)
	var samples: int = clampi(ceili(span / SAMPLE_SECONDS), 2, MAX_SAMPLES)
	var previous_top: Vector2 = _last_size(animation, top, time)
	var previous_bottom: Vector2 = _last_size(animation, bottom, time)
	var screen := Vector2(1920.0, 1080.0)

	for i: int in range(samples + 1):
		var ratio: float = float(i) / float(samples)
		var eased: float = _ease(ratio * span / maxf(duration, 0.0001), ease_name, "Out")
		var at: float = time + span * ratio

		var top_size := Vector2(screen.x,
			lerpf(previous_top.y, up_height * _bar_scale, eased))
		var bottom_size := Vector2(screen.x,
			lerpf(previous_bottom.y, down_height * _bar_scale, eased))

		animation.track_insert_key(top, at, top_size)
		animation.track_insert_key(bottom, at, bottom_size)
		animation.track_insert_key(bottom_y, at, Vector2(0.0, screen.y - bottom_size.y))

		if i < samples:
			continue
		_hold(animation, top, cutoff, top_size)
		_hold(animation, bottom, cutoff, bottom_size)
		_hold(animation, bottom_y, cutoff, Vector2(0.0, screen.y - bottom_size.y))


func _last_size(animation: Animation, track: int, before: float) -> Vector2:
	var count: int = animation.track_get_key_count(track)
	if count == 0:
		return Vector2.ZERO
	for i: int in range(count - 1, -1, -1):
		if animation.track_get_key_time(track, i) <= before:
			return animation.track_get_key_value(track, i)
	return animation.track_get_key_value(track, 0)


## Flixel's FlxEase names. `direction` is the event's easeDir; Funkin defaults an ease
## with no direction to Out, which is why that is the default everywhere above.
func _ease(ratio: float, ease_name: String, direction: String) -> float:
	var t: float = clampf(ratio, 0.0, 1.0)
	match ease_name:
		"linear", "CLASSIC", "INSTANT":
			return t
		"smoothStep":
			return _directional(t, direction, func(x: float) -> float:
				return x * x * (3.0 - 2.0 * x))
		"smoothStepInOut":
			return t * t * (3.0 - 2.0 * t)
		"smootherStep":
			return _directional(t, direction, func(x: float) -> float:
				return x * x * x * (x * (x * 6.0 - 15.0) + 10.0))
		"cube", "cubeOut":
			var power_direction: String = "Out" if ease_name == "cubeOut" else direction
			return _directional(t, power_direction, func(x: float) -> float:
				return x * x * x)
		"quart":
			return _directional(t, direction, func(x: float) -> float:
				return x * x * x * x)
		"elastic", "elasticInOut":
			return _elastic_in_out(t)
		_:
			push_warning("ease sin traducir: %s" % ease_name)
			return t


func _directional(t: float, direction: String, curve: Callable) -> float:
	match direction:
		"Out":
			return 1.0 - float(curve.call(1.0 - t))
		"InOut":
			if t < 0.5:
				return float(curve.call(t * 2.0)) * 0.5
			return 1.0 - float(curve.call((1.0 - t) * 2.0)) * 0.5
		_:
			return curve.call(t)


## FlxEase.elasticInOut, transcribed.
func _elastic_in_out(t: float) -> float:
	if t < 0.5:
		return 0.5 * sin(13.0 * PI * 0.5 * (2.0 * t)) * pow(2.0, 10.0 * ((2.0 * t) - 1.0))
	return 0.5 * (sin(-13.0 * PI * 0.5 * ((2.0 * t - 1.0) + 1.0))
		* pow(2.0, -10.0 * (2.0 * t - 1.0)) + 2.0)
