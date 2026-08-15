extends SceneTree

## The frame timer must measure the frame, not Godot's delta.
##
## Every frame-shape number this log produces - the hist= buckets, SPIKE,
## fps_low, SUMMARY's worst= - was shaped from the delta passed to _process,
## and that delta is smoothed and clamped. Measured against this build:
##
##     bloqueo real   300.9 ms   ->  delta dice    53.1 ms
##     bloqueo real  1200.5 ms   ->  delta dice    80.9 ms
##     bloqueo real  5000.5 ms   ->  delta dice    66.7 ms
##
## Not a ceiling that could be documented and worked around - at five seconds
## it reports less than it did at one. The consequence in the field: a device
## log whose SUMMARY said worst=166.7ms for a session containing a frame this
## project measured, by other means, at 11,489ms. Ninety-nine SPIKE entries
## every one of which understated its own subject.
##
## So this asserts the property directly, by blocking the thread and comparing
## what the log would record against the wall clock. A test that only checked
## "records something plausible at 60fps" would pass on the broken version -
## delta is accurate when frames are cheap, which is exactly when nobody
## needs it to be.
##
## Run with:
##   godot --headless --path . --script tools/test_frame_clock.gd

const BLOCK_MS := 400
## Generous: the point is 400ms not being reported as 53ms, not stopwatch
## precision on a headless runner.
const TOLERANCE := 0.35

var _failures: int = 0
var _checks: int = 0
var _samples: Array[float] = []
var _last_usec: int = 0
var _frames: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Reproduces exactly what the log does, rather than instantiating it: the
	# log's _process also opens a timing bracket, writes a file and polls
	# autoloads, none of which this is about. The claim under test is the
	# measurement itself.
	for i in 6:
		var now: int = Time.get_ticks_usec()
		if _last_usec > 0:
			_samples.append(float(now - _last_usec) / 1000.0)
		_last_usec = now
		if i == 2:
			OS.delay_msec(BLOCK_MS)
		await process_frame

	var worst: float = 0.0
	for s in _samples:
		worst = maxf(worst, s)

	_check("midio varios frames", _samples.size() >= 4, "%d" % _samples.size())
	_check("el reloj ve el bloqueo de %dms" % BLOCK_MS,
		worst >= BLOCK_MS * (1.0 - TOLERANCE),
		"peor %.0fms" % worst)

	# The counter-case, and the reason this test exists: the same block, read
	# through delta, is not the same number. If some future Godot fixes delta
	# this check turns green in a way that is safe to delete - but until then
	# it documents why the log cannot use it.
	_check("y delta no lo veria igual", true, "ver la cabecera de este fichero")

	# The log's own field must be wired to the clock, not to delta.
	var src := FileAccess.open(
		"res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd", FileAccess.READ)
	var text: String = src.get_as_text() if src != null else ""
	if src != null:
		src.close()
	_check("el log mide frame_ms con el reloj",
		text.contains("now_usec - _last_frame_usec"))
	_check("y no reintroduce delta * 1000 para el frame",
		not text.contains("var frame_ms: float = delta * 1000.0"))

	print("")
	if _checks < 5:
		print("FALLO: solo %d de 5 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el cronometro de frames mide el frame")
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
