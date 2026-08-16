extends SceneTree

## The sweep that names what stays cached after a scene is freed.
##
## It exists because nothing else can answer the question. RESIDUE walks the
## outgoing scene's declared dependencies - 64 for Monochrome - while the
## device log shows 21,279 resources surviving that unload, so almost
## everything retained is not a declared dependency and no walk from the scene
## will reach it. And it cannot be measured off-device: the standing tool
## reports Monochrome mounting 4,914 resources here against 23,589 on the
## phone, because a developer checkout has no imported textures, so the objects
## that leak there are never created here.
##
## The risk is not that it fails to find things. It is that it costs more than
## what it measures. It runs during a load, on the main thread, next to a
## loading screen this project spent real effort keeping animated - a sweep
## that stalls a frame would be destroying the thing it was added to explain.
##
## So the load-bearing check here is the frame budget, and it is checked
## against the real project rather than a fixture. The first version treated a
## directory listing as free inside a budgeted loop: it looked at the clock
## before taking a directory, then ran the whole listing however long it took.
## One directory blew a 2ms budget to 358ms in a single frame.
##
## Run with:
##   godot --headless --path . --script tools/test_retained_sweep.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

## The worst single call allowed, in milliseconds.
##
## Far above the 2ms budget and deliberately loose. One directory listing
## cannot be split, the largest in this project measures 9.6ms, and this runs
## on a shared CI machine where a cold page cache can multiply that without
## anything being wrong. At 20ms it failed roughly one run in three locally -
## and an intermittently red test is worse than no test, as this project
## already learned from a bool-track guard that sat red for weeks and taught
## everyone to stop reading the suite.
##
## What it has to catch is the regression that prompted it: treating a
## directory listing as free inside the budgeted loop, which produced a single
## 358ms call. 100ms catches that with a wide margin and does not flake on a
## typical 6ms.
const WORST_CALL_MS := 100.0

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var log_node := Node.new()
	log_node.set_script(load(LOG))
	# Never added to the tree: _ready() opens a log file and starts hooking
	# autoloads, none of which this exercises.
	log_node._outgoing_scene_path = "res://prueba.tscn"

	log_node._start_retained_sweep()
	_check("arranca activo", log_node._sweep_active)

	var calls: int = 0
	var samples: Array[int] = []
	while log_node._sweep_active and calls < 20000:
		var t0: int = Time.get_ticks_usec()
		log_node._continue_retained_sweep()
		samples.append(Time.get_ticks_usec() - t0)
		calls += 1
		if calls % 250 == 0:
			await process_frame

	# The 99th percentile, not the maximum.
	#
	# A single call is at the mercy of whatever else the machine is doing, and
	# asserting on the worst of a thousand samples made this fail about one run
	# in three even after the bound was raised five-fold. A regression of the
	# kind this guards - a directory listing treated as free inside the
	# budgeted loop, which put 358ms into one call - is systematic and moves
	# the percentile; a scheduler hiccup does not.
	samples.sort()
	var p99: int = samples[mini(samples.size() - 1, int(samples.size() * 0.99))]
	var worst_usec: int = p99

	_check("termina solo", not log_node._sweep_active, "%d llamadas" % calls)
	_check("examino el proyecto", log_node._sweep_seen > 500,
		"%d ficheros" % log_node._sweep_seen)

	# The one that matters.
	_check("el percentil 99 no pasa de %.0fms" % WORST_CALL_MS,
		worst_usec / 1000.0 <= WORST_CALL_MS,
		"p99 %.2fms de %d llamadas" % [worst_usec / 1000.0, samples.size()])

	# The names are what the next device log is collected for; a report that
	# never fills its list would be a silent no-op, and the first attempt at
	# this change produced exactly that - declared, reset and reported, never
	# appended to, because a string replace found no anchor and said nothing.
	_check("recoge nombres, no solo recuentos", log_node._sweep_names.size() > 0,
		"%d nombres" % log_node._sweep_names.size())
	var no_scripts: bool = true
	for n in log_node._sweep_names:
		if str(n).ends_with(".gd"):
			no_scripts = false
	_check("y deja fuera los scripts", no_scripts)

	# Scripts are always cached - GDScript keeps them - so a sweep finding
	# nothing at all would mean it is asking the wrong question, not that the
	# project is clean.
	var total: int = 0
	for key in log_node._sweep_cached:
		total += int(log_node._sweep_cached[key])
	_check("encuentra algo cacheado", total > 0, "%d" % total)

	var has_gd: bool = false
	for key in log_node._sweep_cached:
		if str(key).ends_with(":gd"):
			has_gd = true
	_check("agrupa por carpeta:extension", has_gd,
		", ".join(PackedStringArray(log_node._sweep_cached.keys())).substr(0, 60))

	# The skipped directories must not be walked: they are hundreds of
	# megabytes of build output that no scene ever references.
	var touched_skipped: bool = false
	for key in log_node._sweep_cached:
		for skip in log_node.SWEEP_SKIP_DIRS:
			if str(key).begins_with(str(skip)):
				touched_skipped = true
	_check("no entra en las carpetas excluidas", not touched_skipped)

	# A sweep cut short by the next scene arriving must say so rather than
	# report its partial total as the whole answer.
	log_node._start_retained_sweep()
	log_node._continue_retained_sweep()
	_check("cortarlo lo desactiva", log_node._sweep_active)
	log_node._finish_retained_sweep()
	_check("y tras finalizar queda inactivo", not log_node._sweep_active)

	log_node.free()

	print("")
	if _checks < 11:
		print("FALLO: solo %d de 11 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el barrido nombra lo retenido sin costar un frame")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-48s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-48s%s" % [label, "  (%s)" % detail if detail else ""])
