extends SceneTree

## warm() must not block the frame it is called on.
##
## The shop warms one voiceline per frame from _process, which was added to
## keep 109 .ogg files off its cold load. It did that by calling load()
## straight from the main thread, so the cost moved out of the loading screen
## and into gameplay: the device log's two worst script frames in the shop are
## 111.47ms and 71.90ms, both with every note-system field and anim2d at zero,
## both in the only scene that warms voicelines.
##
## So the property under test is timing, not correctness - get_stream() was
## always going to return the right audio. It is that warm() returns in
## something far short of a frame while the load happens elsewhere.
##
## Run with:
##   godot --headless --path . --script tools/test_voiceline_warm_async.gd

const ENTRY := "res://lullaby_mod/scripts/lullaby/collectors_shop/dialogue/VoicelineEntry.gd"

## A frame at 60fps is 16.7ms. Warming has to be a small fraction of one, and
## generous here because a headless runner is not a phone - what this must
## fail on is a blocking load, which measured tens of milliseconds on device.
const WARM_BUDGET_MS := 5.0

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var path: String = _an_ogg()
	_check("hay un .ogg de voiceline con el que medir", not path.is_empty(), path.get_file())
	if path.is_empty():
		print("")
		print("FALLO: sin audio no se puede medir nada")
		quit(1)
		return

	var entry: Resource = load(ENTRY).new()
	entry.stream_path = path

	_check("empieza en frio", not entry.is_warm())

	# The first warm() only files the request.
	var t0: int = Time.get_ticks_usec()
	entry.warm()
	var first_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	_check("el primer warm() no bloquea", first_ms <= WARM_BUDGET_MS,
		"%.2fms" % first_ms)

	# Subsequent warms collect it once the thread is done, and must stay cheap
	# whether it is ready or not.
	var worst_ms: float = 0.0
	for i in 240:
		var t1: int = Time.get_ticks_usec()
		entry.warm()
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t1) / 1000.0)
		if entry.is_warm():
			break
		await process_frame

	_check("ningun warm() posterior bloquea", worst_ms <= WARM_BUDGET_MS,
		"peor %.2fms" % worst_ms)
	_check("y acaba cargado", entry.is_warm())

	var audio: AudioStream = entry.get_stream()
	_check("get_stream devuelve el audio", audio != null,
		audio.get_class() if audio != null else "null")

	# The urgent path: no warm at all, get_stream must still work. It blocks,
	# and that is deliberate - silence is worse than a stall when the line is
	# about to play.
	var cold: Resource = load(ENTRY).new()
	cold.stream_path = path
	_check("sin warm previo get_stream sigue resolviendo",
		cold.get_stream() != null)

	print("")
	if _checks < 7:
		print("FALLO: solo %d de 7 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - calentar una voiceline no cuesta un frame")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## A real voiceline, taken from the shop's own groups rather than hardcoded,
## so this keeps measuring something that exists after a rename.
func _an_ogg() -> String:
	var dir := DirAccess.open("res://lullaby_mod/resources/audio")
	if dir == null:
		return ""
	var stack: Array[String] = ["res://lullaby_mod/resources/audio"]
	while not stack.is_empty():
		var at: String = stack.pop_back()
		for entry in ResourceLoader.list_directory(at):
			var full: String = at.path_join(str(entry).trim_suffix("/"))
			if str(entry).ends_with("/"):
				stack.append(full)
			elif full.ends_with(".ogg") and not ResourceLoader.has_cached(full):
				return full
	return ""

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-48s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-48s%s" % [label, "  (%s)" % detail if detail else ""])
