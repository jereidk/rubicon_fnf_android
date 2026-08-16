extends SceneTree

## The loading bar has to move while the engine's own figure does not.
##
## load_threaded_get_status' fraction is nearly useless on the scenes that
## need a loading screen at all. In the last device log all eight stalls sit
## between 48.6% and 50.0%, and Chimera's load reports 48.6% at three seconds
## and 49.9% at twenty-six - the bar reaches half in the first second and then
## holds still for forty while the game works normally behind it. That is what
## a frozen loading screen looks like even when nothing is frozen.
##
## So the figure is blended with a second measurement: how many of the scene's
## direct dependencies are in the resource cache. What is asserted here is not
## that the number is accurate - neither input is - but the two properties a
## progress bar actually needs. It must advance when one source advances and
## the other is stuck, and it must never go backwards.
##
## Run with:
##   godot --headless --path . --script tools/test_load_progress.gd

const CHANGER := "res://lullaby_mod/scripts/lullaby/loading/lullaby_scene_changer.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var changer := CanvasLayer.new()
	changer.set_script(load(CHANGER))

	# Real paths that are NOT already cached, which matters more than it
	# sounds: the first version of this used .gd files the project loads at
	# boot, so has_cached() answered true for all four before the test loaded
	# anything and the ratio was 1.0 from the first call. It passed "the bar
	# moves" without ever showing the bar move.
	var real: PackedStringArray = PackedStringArray()
	# The quality presets were the obvious pick and they are all cached at
	# boot by Settings, which is how the first attempt ended up with an empty
	# list. These are not loaded until the shop needs them.
	for candidate in [
		"res://lullaby_mod/resources/animations/collector/briefcase_idle.tres",
		"res://lullaby_mod/resources/animations/collector/briefcase_intro.tres",
		"res://lullaby_mod/resources/animations/collector/briefcase_outro.tres",
		"res://lullaby_mod/resources/animations/collector/default_trans.tres",
	]:
		if ResourceLoader.exists(candidate) and not ResourceLoader.has_cached(candidate):
			real.append(candidate)
	_check("hay dependencias sin cachear con las que medir", real.size() >= 3,
		"%d" % real.size())
	# Guarded: without this an empty list indexes real[0] below and the script
	# dies without ever reaching quit(), so the runner hangs instead of
	# reporting a red check. That has already happened once in this session.
	if real.size() < 3:
		print("")
		print("FALLO: no hay recursos sin cachear con los que medir")
		quit(1)
		return

	# Nothing known: the engine's figure is all there is.
	changer._direct_deps = PackedStringArray()
	changer._reported_progress = 0.0
	_check("sin dependencias devuelve la del motor",
		is_equal_approx(changer._blended_progress(0.25), 0.25),
		"%.2f" % changer._blended_progress(0.25))

	# The device's situation: engine stuck at ~0.5, dependencies arriving.
	changer._direct_deps = real
	changer._reported_progress = 0.0

	var stuck: float = 0.20
	var at_start: float = changer._blended_progress(stuck)
	_check("con nada cargado la barra es la del motor",
		is_equal_approx(at_start, stuck), "%.2f" % at_start)

	# One dependency arrives, the engine's figure does not move.
	#
	# The reference has to be held. ResourceLoader.load() whose result is
	# discarded drops the refcount straight back to zero and the resource
	# leaves the cache in the same breath, so has_cached() answered false and
	# the bar never moved - which read as the blend being broken when it was
	# the test throwing away what it had just loaded. During a real threaded
	# load the loader itself is the holder.
	var held: Array[Resource] = []
	held.append(ResourceLoader.load(real[0]))
	var partway: float = changer._blended_progress(stuck)
	_check("una dependencia mueve la barra sin mover el motor",
		partway > at_start and partway < 1.0,
		"motor %.2f fijo -> barra %.2f" % [stuck, partway])

	# The rest arrive.
	for i in range(1, real.size()):
		held.append(ResourceLoader.load(real[i]))
	var blended: float = changer._blended_progress(stuck)
	_check("y sigue subiendo con las demas", blended > partway,
		"%.2f -> %.2f" % [partway, blended])

	# Monotonic: the engine's figure dropping must not drag the bar back.
	var after_drop: float = changer._blended_progress(0.0)
	_check("una caida del motor no la hace retroceder", after_drop >= blended,
		"%.2f -> %.2f" % [blended, after_drop])

	# And a shrinking dependency ratio must not either.
	changer._direct_deps = PackedStringArray()
	var after_loss: float = changer._blended_progress(0.0)
	_check("perder las dependencias tampoco", after_loss >= blended,
		"%.2f" % after_loss)

	_check("nunca pasa de 1.0", changer._blended_progress(5.0) <= 1.0,
		"%.2f" % changer._blended_progress(5.0))

	# The parser: get_dependencies() mixes bare paths with uid::type::path.
	changer._collect_direct_deps("res://lullaby_mod/resources/loading/load_default.tscn")
	var all_paths: bool = true
	for dep in changer._direct_deps:
		if not dep.begins_with("res://"):
			all_paths = false
	_check("las dependencias se leen como rutas res://", all_paths,
		"%d deps" % changer._direct_deps.size())
	_check("y recolectar reinicia el progreso",
		is_equal_approx(changer._reported_progress, 0.0))

	changer.free()

	print("")
	if _checks < 10:
		print("FALLO: solo %d de 10 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - la barra avanza aunque el motor se quede quieto")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-50s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-50s%s" % [label, "  (%s)" % detail if detail else ""])
