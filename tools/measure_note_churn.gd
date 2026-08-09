extends SceneTree

## Runs a song scene for a while and reports what note churn cost, using the
## same counters the diagnostics log reads on device.
##
## The point is not the absolute milliseconds - this is a desktop under Xvfb
## with a different renderer and a much faster CPU than a moto g53 - but that
## the counters move at all, that inst= stays at zero (the pool is doing its
## job), and that the before/after of a change to spawn_note/despawn_note can
## be compared on identical input.
##
## Run with:
##   xvfb-run -a --server-args="-screen 0 1280x800x24" \
##     godot --path . --script tools/measure_note_churn.gd [scene] [seconds]

const DEFAULT_SCENE := "res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn"
const DEFAULT_SECONDS := 25.0
const SAMPLE_SECONDS := 1.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = args[0] if args.size() > 0 else DEFAULT_SCENE
	var seconds: float = float(args[1]) if args.size() > 1 else DEFAULT_SECONDS

	print("escena: ", scene_path)
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("no se pudo cargar %s" % scene_path)
		quit(1)
		return

	var song: Node = packed.instantiate()
	root.add_child(song)
	await process_frame

	# Drain whatever the first frames cost to set up, so the sample is of the
	# song running rather than of it starting.
	for i in 30:
		await process_frame
	RubiconLevelNoteHandler.take_churn_stats()

	print("")
	print("%6s %8s %9s %6s %6s %9s %11s %7s %7s" % [
		"t", "spawn", "despawn", "park", "inst", "churn_ms", "churn_max",
		"nodes", "orph"])

	var elapsed: float = 0.0
	var totals := {
		"spawned": 0, "despawned": 0, "unparked": 0, "instantiated": 0,
		"usec": 0,
	}
	var worst_usec: int = 0

	while elapsed < seconds:
		# SceneTree.process_frame carries no arguments, so awaiting it yields
		# null rather than a delta; the window has to be timed off the clock.
		var began: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - began < int(SAMPLE_SECONDS * 1000.0):
			await process_frame
		var window: float = float(Time.get_ticks_msec() - began) / 1000.0
		elapsed += window

		var churn: Dictionary = RubiconLevelNoteHandler.take_churn_stats()
		for key in totals:
			totals[key] += int(churn[StringName(key)])
		worst_usec = maxi(worst_usec, int(churn[&"peak_usec"]))

		print("%6.1f %8d %9d %6d %6d %9.2f %11.2f %7d %7d" % [
			elapsed,
			int(churn[&"spawned"]), int(churn[&"despawned"]),
			int(churn[&"unparked"]), int(churn[&"instantiated"]),
			float(churn[&"usec"]) / 1000.0,
			float(churn[&"peak_usec"]) / 1000.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		])

	print("")
	print("total  spawn=%d despawn=%d park=%d inst=%d" % [
		totals["spawned"], totals["despawned"], totals["unparked"],
		totals["instantiated"]])
	print("       churn=%.1fms sobre %.0fs  (%.2fms por segundo de canción)" % [
		float(totals["usec"]) / 1000.0, elapsed,
		float(totals["usec"]) / 1000.0 / maxf(elapsed, 0.001)])
	print("       peor frame=%.2fms" % (float(worst_usec) / 1000.0))
	if totals["spawned"] > 0:
		print("       coste medio por nota=%.3fms" % [
			float(totals["usec"]) / 1000.0 / float(totals["spawned"] + totals["despawned"])])
	quit()
