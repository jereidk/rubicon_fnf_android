extends SceneTree

## Proves when a bool value track actually changes, for both update modes.
##
## 220 tracks across 28 scenes are about to be rewritten on the strength of
## one claim: that Godot 4.7.1 changes a CONTINUOUS bool track halfway to the
## next key rather than at the key, and that DISCRETE changes it at the key.
## That claim came from reading Variant::interpolate, and reading is not
## measuring - so this drives a real AnimationPlayer and reports the answer.
##
## Run with:
##   godot --headless --path . --script tools/test_bool_track_timing.gd

## Deliberately the shape that broke Monochrome: false at 0, true much later.
const KEY_A := 0.0
const KEY_B := 100.0

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var continuous: float = await _first_true(Animation.UPDATE_CONTINUOUS)
	var discrete: float = await _first_true(Animation.UPDATE_DISCRETE)

	print("clave false en t=%.1f, clave true en t=%.1f" % [KEY_A, KEY_B])
	print("")
	print("  CONTINUOUS cambia en t=%.1f" % continuous)
	print("  DISCRETE   cambia en t=%.1f" % discrete)
	print("")

	var midpoint: float = (KEY_A + KEY_B) / 2.0
	_check("CONTINUOUS cambia en el punto medio, no en la clave",
		is_equal_approx(snappedf(continuous, 1.0), midpoint),
		"esperaba %.1f" % midpoint)
	_check("DISCRETE cambia en la clave",
		is_equal_approx(snappedf(discrete, 1.0), KEY_B),
		"esperaba %.1f" % KEY_B)
	_check("y por tanto no son equivalentes", not is_equal_approx(continuous, discrete))

	print("")
	if _failures == 0:
		print("todo OK - el desfase es real y DISCRETE lo corrige")
	else:
		print("%d fallo(s) - NO apliques el arreglo masivo" % _failures)
	quit(0 if _failures == 0 else 1)

## Seeks across the whole track and returns the first time the property reads
## true. Seeking rather than playing so the answer does not depend on frame
## pacing, and one AnimationPlayer per mode so neither can contaminate the
## other's cache.
func _first_true(mode: Animation.UpdateMode) -> float:
	var target := Node2D.new()
	target.visible = false
	root.add_child(target)

	var player := AnimationPlayer.new()
	target.add_child(player)

	var animation := Animation.new()
	animation.length = KEY_B + 10.0
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	# Relative to the player's root_node, which defaults to its parent -
	# the target itself.
	animation.track_set_path(track, NodePath(".:visible"))
	animation.value_track_set_update_mode(track, mode)
	animation.track_insert_key(track, KEY_A, false)
	animation.track_insert_key(track, KEY_B, true)

	var library := AnimationLibrary.new()
	library.add_animation(&"test", animation)
	player.add_animation_library(&"", library)

	var found: float = -1.0
	var t: float = 0.0
	while t <= KEY_B + 5.0:
		player.play(&"test")
		player.seek(t, true)
		await process_frame
		if target.visible:
			found = t
			break
		t += 1.0

	player.queue_free()
	target.queue_free()
	await process_frame
	return found

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s%s" % [name, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %s%s" % [name, "  (%s)" % detail if detail else ""])
