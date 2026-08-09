extends SceneTree

## Does a song give its resources back when you leave it?
##
## The device log says no, and says what it costs. Loading Monochrome takes
## the resource count from 240 to 23,695. Leaving it does not bring the count
## down, and the next load of the shop - the same scene that took 5.0s the
## first time, when 1,071 resources were resident - takes 18.4s, with 16.3 of
## those seconds inside a single phase that only adds 1,244 resources. That
## is 13ms per resource against roughly 0.2ms the first time.
##
## Two possible stories, and they need opposite fixes: either something holds
## references so the resources genuinely stay, or they are released and the
## cost is elsewhere. This checks by loading a scene, freeing it, and asking
## the engine what is still resident.
##
## Run with:
##   godot --headless --path . --script tools/measure_scene_residency.gd

const SCENES := [
	"res://lullaby_mod/songs/monochrome/sng_monochrome.tscn",
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for path: String in SCENES:
		await _measure(path)
	quit(0)

func _measure(path: String) -> void:
	await process_frame
	var before: int = _resources()
	var before_mem: int = _memory()

	var began: int = Time.get_ticks_msec()
	var packed: PackedScene = load(path)
	if packed == null:
		print("no pude cargar %s" % path)
		return
	var load_ms: int = Time.get_ticks_msec() - began

	var after_load: int = _resources()

	var instance: Node = packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var live: int = _resources()
	var live_mem: int = _memory()

	# Everything a scene change does: the node goes, and the PackedScene
	# reference this script holds goes with it.
	instance.queue_free()
	packed = null
	await process_frame
	await process_frame
	await process_frame

	var after_free: int = _resources()
	var after_free_mem: int = _memory()

	print("")
	print("=== %s" % path.get_file())
	print("  cargar                 %6d ms" % load_ms)
	print("  recursos antes         %6d" % before)
	print("  tras load()            %6d   (+%d)" % [after_load, after_load - before])
	print("  con la escena montada  %6d   (+%d)" % [live, live - before])
	print("  tras liberarla         %6d   (+%d sobre el inicio)" % [after_free, after_free - before])
	print("")
	print("  memoria antes          %6.1f MB" % (before_mem / 1048576.0))
	print("  montada                %6.1f MB" % (live_mem / 1048576.0))
	print("  tras liberarla         %6.1f MB" % (after_free_mem / 1048576.0))
	print("")

	var kept: int = after_free - before
	var pct: float = 100.0 * float(kept) / float(maxi(1, live - before))
	if kept <= 0:
		print("  -> lo devuelve todo.")
	else:
		print("  -> retiene %d recursos (%.0f%% de los que cargo) despues de liberarla." % [kept, pct])
		print("     Eso es lo que sigue residente cuando vuelves a la tienda.")

func _resources() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))

func _memory() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))
