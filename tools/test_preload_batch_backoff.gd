extends SceneTree

## The reveal pacer has to see an expensive frame and back off.
##
## It steers a batch size with additive increase and multiplicative decrease:
## reveal one more node per frame while frames are cheap, halve the batch the
## moment one is not. That only works if it can see the frame it just paid for.
##
## It could not. It read Performance.TIME_PROCESS, which is a maximum over the
## last second refreshed once a second - not the previous frame, and across a
## frame lasting seconds it reports whatever it held before the frame began.
## So the pacer never saw a spike, never halved, climbed to MAX_BATCH and put
## 64 nodes on one frame.
##
## The device log measured that: entering the shop compiles 212 render
## pipelines, and the batch landing 47 of them took 6981ms in a single frame,
## past the five seconds Android calls unresponsive.
##
## So this blocks the main thread for real and checks the pacer noticed. The
## old reading cannot notice - that is the whole point of the test - and the
## new one is a wall clock across the gap between two _process calls.
##
## Run with:
##   godot --headless --path . --script tools/test_preload_batch_backoff.gd

const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"

## Comfortably past FRAME_BUDGET_MS without making the test slow.
const SLOW_FRAME_MS := 260

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var script: GDScript = load(CAMERA)
	var camera: Node = Camera3D.new()
	camera.set_script(script)
	root.add_child(camera)

	# _ready() hides the parent's subtree and would free this node outright
	# when there is nothing to reveal, so the state it drives is set up by hand
	# and only _process is exercised. What is under test is the pacing.
	camera._started_msec = Time.get_ticks_msec()
	camera._finished = false
	camera._measured_first_frame = false
	camera._revealed = 0
	var hidden: Array[Node] = []
	for i in 400:
		hidden.append(Node2D.new())
	camera._hidden = hidden

	_check("empieza en el lote inicial", camera._batch == script.FIRST_BATCH,
		"%d" % camera._batch)

	# The baseline frame: a measurement, not a reveal, and where the clock is
	# armed. Nothing may be revealed on it.
	camera._process(0.016)
	_check("el primer frame no revela nada", camera._revealed == 0)
	_check("y arma el reloj", camera._last_frame_usec > 0)

	# The blind frame: whatever this reveals is drawn with no measurement
	# behind it, so it is the one the pacer cannot protect. It used to be
	# FIRST_BATCH + 1 = 5, because the additive increase ran before the reveal
	# and the baseline frame - which reveals nothing - counted as "cheap".
	# 10152-665dedd4 and 10154-8d1ee1ac both log a frame of over seven seconds
	# inside the shop's precache, in a window where RAM and VRAM are flat.
	camera._process(0.016)
	_check("la primera tanda es exactamente FIRST_BATCH",
		camera._revealed == script.FIRST_BATCH,
		"revelo %d, FIRST_BATCH=%d" % [camera._revealed, script.FIRST_BATCH])

	# Cheap frames: the batch climbs.
	for i in 12:
		camera._process(0.016)
	var climbed: int = camera._batch
	_check("con frames baratos el lote sube", climbed > script.FIRST_BATCH,
		"%d -> %d" % [script.FIRST_BATCH, climbed])

	# One genuinely expensive frame. OS.delay_msec blocks the main thread, the
	# same way compiling a pipeline does.
	OS.delay_msec(SLOW_FRAME_MS)
	camera._process(0.016)
	_check("un frame caro reduce el lote a la mitad", camera._batch <= climbed / 2 + 1,
		"%d -> %d tras %dms" % [climbed, camera._batch, SLOW_FRAME_MS])

	# And it recovers afterwards rather than staying pinned at one.
	var after_slow: int = camera._batch
	for i in 6:
		camera._process(0.016)
	_check("y vuelve a subir cuando se abarata", camera._batch > after_slow,
		"%d -> %d" % [after_slow, camera._batch])

	# Catastrophe is not "over budget", it is a different kind of event.
	# Halving from five lands on two, which is still several never-drawn nodes
	# on the next frame - and the device logs show the frames right after the
	# monster are themselves 40-70ms. Past PANIC_FACTOR the only safe next
	# batch is one.
	for i in 8:
		camera._process(0.016)
	var before_panic: int = camera._batch
	OS.delay_msec(int(script.FRAME_BUDGET_MS * script.PANIC_FACTOR) + 120)
	camera._process(0.016)
	_check("un frame catastrofico deja el lote en 1", camera._batch == 1,
		"%d -> %d" % [before_panic, camera._batch])

	# The reading it used to steer on cannot do any of this: it is a per-second
	# maximum, so it does not change across the frames above at all.
	var monitor_a: float = Performance.get_monitor(Performance.TIME_PROCESS)
	OS.delay_msec(SLOW_FRAME_MS)
	var monitor_b: float = Performance.get_monitor(Performance.TIME_PROCESS)
	_check("TIME_PROCESS no ve el frame que acaba de pasar",
		is_equal_approx(monitor_a, monitor_b),
		"%.4f -> %.4f tras bloquear %dms" % [monitor_a, monitor_b, SLOW_FRAME_MS])

	for node in hidden:
		node.free()
	camera._hidden = [] as Array[Node]
	camera.queue_free()
	await process_frame

	print("")
	if _checks < 9:
		print("FALLO: solo %d de 7 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el revelado frena cuando el frame se pone caro")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])
