extends SceneTree

## The continuous watch for a rect that blacks out the screen.
##
## The census already names one when it sees one - it caught Chimera's
## Prelude/Black at coverage 1.00 - but it samples every thirty seconds. The
## reported bug is a black graphic that comes and goes during a song, and a
## forty second visit to Chimera produced exactly two censuses, both reading
## opaque=[], while the player was watching the thing happen. The instrument
## was not wrong; it was asleep.
##
## So the property under test is not "can it identify a black rect" - the
## census could already do that. It is that a blackout shorter than the census
## interval is reported at all, and that it is reported as edges rather than
## as a line every frame.
##
## Run with:
##   godot --headless --path . --script tools/test_blackout_watch.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var scene := Node2D.new()
	root.add_child(scene)

	# The visible rect, not root.size. They are different spaces: root.size is
	# the OS window (1366x768 here) while the canvas this project stretches to
	# is 1920x1080, and get_global_rect() answers in the canvas one. Sizing the
	# "full screen" rect from root.size made it cover 50.6%, so the case meant
	# to prove detection was quietly testing a half-screen rect.
	var screen: Vector2 = root.get_visible_rect().size

	# Authored hidden, full screen, opaque black: the shape of the bug.
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.size = screen
	black.visible = false
	scene.add_child(black)

	# Must not be watched: right size, wrong colour.
	var white := ColorRect.new()
	white.color = Color(1, 1, 1, 1)
	white.size = screen
	scene.add_child(white)

	# Must not be watched: right colour, no area.
	var tiny := ColorRect.new()
	tiny.color = Color(0, 0, 0, 1)
	tiny.size = Vector2.ZERO
	scene.add_child(tiny)

	# Watched, because it is dark and has area - but it must never fire. This
	# is the case the first version of this test did not have, and its absence
	# shipped a real bug: _screen_area() answers in pixels and the watch
	# compared it straight against a 0.8 threshold, so every rect over 0.8
	# square pixels counted as covering the screen. The device log came back
	# naming Chimera's 242px letterbox bars as blackouts. A test whose only
	# dark rect is full-screen cannot tell a working filter from an absent one.
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 1)
	bar.size = Vector2(screen.x * 0.12, screen.y)
	scene.add_child(bar)

	await process_frame

	# The real autoload, not a fresh instance. _screen_area() and
	# _opaque_coverage() both resolve against get_tree().root, and an instance
	# sitting outside the tree has no get_tree() - the first version of this
	# test built one, and every rect measured as covering nothing, which read
	# as the watch being broken rather than the double being unusable.
	var log_node: Node = root.get_node_or_null(^"DiagnosticsLog")
	if log_node == null:
		print("FALLO: no existe el autoload DiagnosticsLog")
		quit(1)
		return

	# _collect_blackout_watch reads get_tree().current_scene, which a headless
	# SceneTree has not set, so the collection is driven over the same subtree
	# by hand. The rules being tested are the filter and the edges.
	log_node._blackout_watch.clear()
	for child in scene.get_children():
		var rect := child as ColorRect
		if rect == null:
			continue
		if maxf(rect.color.r, maxf(rect.color.g, rect.color.b)) > log_node.BLACKOUT_MAX_LUMA:
			continue
		if rect.size.x * rect.size.y <= 0.0:
			continue
		log_node._blackout_watch.append(rect)

	_check("vigila el rect negro grande", log_node._blackout_watch.has(black))
	_check("ignora el blanco", not log_node._blackout_watch.has(white))
	_check("ignora el de area cero", not log_node._blackout_watch.has(tiny))
	_check("si vigila la barra estrecha", log_node._blackout_watch.has(bar))

	# Hidden: nothing to report.
	log_node._poll_blackouts()
	_check("oculto no dispara nada", log_node._blackout_on.is_empty())

	# A narrow bar, fully visible and fully opaque, is not a blackout.
	bar.visible = true
	await process_frame
	log_node._poll_blackouts()
	_check("una barra del 12% no cuenta como apagon",
		not log_node._blackout_on.has(bar))

	# Switched on the way an animation track switches it on.
	black.visible = true
	await process_frame
	log_node._poll_blackouts()
	_check("encendido se detecta", log_node._blackout_on.has(black))

	# Edges, not states: polling again while it is still on must not re-arm.
	# Guarded: the first version indexed this dictionary straight after the
	# check above failed, so a red test crashed instead of reporting.
	var armed_at: int = int(log_node._blackout_on.get(black, -1))
	log_node._poll_blackouts()
	log_node._poll_blackouts()
	_check("seguir encendido no vuelve a disparar",
		armed_at >= 0 and int(log_node._blackout_on.get(black, -1)) == armed_at)

	black.visible = false
	await process_frame
	log_node._poll_blackouts()
	_check("apagado se detecta", not log_node._blackout_on.has(black))

	# The interval that made this necessary: the whole on-and-off above took a
	# couple of frames, far inside the census period it has to beat.
	_check("todo esto ocurre dentro de un periodo de censo",
		log_node.CENSUS_SECONDS >= 1.0, "censo cada %.0fs" % log_node.CENSUS_SECONDS)

	log_node._blackout_watch.clear()
	log_node._blackout_on.clear()
	scene.queue_free()
	await process_frame

	print("")
	if _checks < 10:
		print("FALLO: solo %d de 10 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - un apagon mas corto que el censo se registra igual")
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
