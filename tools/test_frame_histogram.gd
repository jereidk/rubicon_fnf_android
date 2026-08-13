extends SceneTree

## HEARTBEAT now carries a frame-time histogram and a vsync-alignment
## percentage. This checks both describe the frames they were handed.
##
## They exist to settle one question the log has never been able to answer:
## Safety Lullaby and Chimera both report frame=33.30ms, which is exactly two
## vsync intervals at 60Hz, and median/worst cannot tell a compositor holding
## every frame for an extra interval from work that genuinely costs 25-40ms.
## Those two want opposite fixes. A histogram that miscounted, or an alignment
## figure that called scattered frames aligned, would answer it wrongly and
## confidently - which is the failure this project has already paid for
## several times.
##
## Run with:
##   godot --headless --path . --script tools/test_frame_histogram.gd

var _failures: int = 0
var _log: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	_log = root.get_node_or_null("DiagnosticsLog")
	if _log == null:
		print("FALLO: no encontre el autoload DiagnosticsLog")
		quit(1)
		return

	# Pin the refresh clock so the test does not depend on whatever panel the
	# machine running it happens to have.
	_log._refresh_hz = 60.0
	_log._refresh_ms = 1000.0 / 60.0

	_buckets_case()
	_locked_case()
	_load_case()
	_fast_case()
	_clear_case()

	print("")
	if _failures == 0:
		print("todo OK - el histograma describe los frames")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## One frame in each bucket, so nothing lands one boundary off.
func _buckets_case() -> void:
	_reset()
	for ms in [8.0, 16.7, 24.0, 33.3, 50.0, 80.0, 200.0]:
		_log._record_frame_shape(ms)

	var shape: String = _log._take_frame_shape()
	_check("cada bucket recibe su frame",
		shape.contains("<12:1") and shape.contains("12-20:1")
		and shape.contains("20-28:1") and shape.contains("28-40:1")
		and shape.contains("40-60:1") and shape.contains("60-100:1")
		and shape.contains("100+:1"),
		shape)

## The case the histogram was built for: 30fps because the compositor is
## holding frames, not because the work costs 33ms.
func _locked_case() -> void:
	_reset()
	for i in 100:
		_log._record_frame_shape(33.30)

	var shape: String = _log._take_frame_shape()
	_check("un lock de vsync sale como un solo bucket",
		shape.contains("28-40:100") and not shape.contains("20-28"), shape)
	_check("y como 100% alineado", shape.contains("vsync=100%@60Hz"), shape)

## The other answer to the same 30fps: real work, scattered across the range.
## The 20-28 band is the tell - no vsync-paced frame can land there.
func _load_case() -> void:
	_reset()
	for ms in [22.0, 26.0, 31.0, 24.5, 29.0, 35.0, 27.0, 23.0]:
		_log._record_frame_shape(ms)

	var shape: String = _log._take_frame_shape()
	_check("carga real cae en la banda intermedia", shape.contains("20-28:5"), shape)
	# 31.0 and 35.0 are the only two anywhere near 33.33, and both are well
	# outside the tolerance.
	_check("y no se cuenta como alineada", shape.contains("vsync=0%"), shape)

## A frame faster than one interval cannot have been paced by the compositor,
## so counting it as aligned would inflate the figure on every menu.
func _fast_case() -> void:
	_reset()
	for i in 10:
		_log._record_frame_shape(0.4)

	var shape: String = _log._take_frame_shape()
	_check("un frame mas rapido que un intervalo no cuenta como alineado",
		shape.contains("vsync=0%"), shape)

## Each HEARTBEAT covers the interval since the previous one, so reading the
## histogram must clear it - otherwise every line reports the whole session
## and the numbers only ever grow.
func _clear_case() -> void:
	_reset()
	_log._record_frame_shape(16.7)
	_log._take_frame_shape()

	var shape: String = _log._take_frame_shape()
	_check("leerlo lo vacia", shape.contains("hist=[]") and shape.contains("vsync=0%"), shape)

func _reset() -> void:
	_log._frame_hist.resize(_log.FRAME_BUCKET_LABELS.size())
	_log._frame_hist.fill(0)
	_log._hist_frames = 0
	_log._hist_aligned = 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
