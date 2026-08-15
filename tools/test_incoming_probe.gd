extends SceneTree

## The incoming-dependency walk now resumes across frames instead of stopping
## at its time budget. This checks it actually reaches the whole graph.
##
## It matters because the capped version produced a confidently wrong reading.
## On the Collector's Shop it stopped at walk=120.1ms with 112 paths, out of a
## graph that is really 512 files, and those 112 were the shallowest ones - so
## the log said "111 of 112 cached" while the load still had sixteen seconds
## and three hundred resources to go. That got read as one slow dependency
## holding everything up, which is not what was happening at all.
##
## Run with:
##   godot --headless --path . --script tools/test_incoming_probe.gd

const SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var log_node: Node = root.get_node_or_null("DiagnosticsLog")
	if log_node == null:
		print("FALLO: no encontre el autoload DiagnosticsLog")
		quit(1)
		return

	if not ResourceLoader.exists(SCENE):
		print("FALLO: no existe %s" % SCENE)
		quit(1)
		return

	# A deliberately tiny budget, so the resumable path is exercised whatever
	# the OS file cache happens to be holding. With the real budget and warm
	# dependency headers the whole graph fits in one pass and this would prove
	# nothing.
	log_node.probe_budget_usec = 200

	log_node._collect_incoming_deps(SCENE)
	var first: int = log_node._incoming_deps.size()
	print("primera pasada: %d rutas en %.1fms" % [first, log_node._incoming_walk_usec / 1000.0])

	# The contract is that a pass YIELDS, not that it lands under a wall-clock
	# bound: the budget can only be checked between calls, and one
	# get_dependencies() on a large .gltf can overrun it on its own. What must
	# never happen is a pass walking the whole graph in one go, which is the
	# frame-long stall this is meant to avoid. (Headless is the pessimistic
	# case at ~9ms per call with nothing imported; the device managed 112
	# paths inside one 120ms budget.)
	_check("la primera pasada cede el frame",
		not log_node._walk_queue.is_empty(),
		"%d rutas, %.0fms, %d en cola" % [
			first, log_node._incoming_walk_usec / 1000.0, log_node._walk_queue.size(),
		])

	# Keep going the way _poll_load_progress() does, once per frame.
	var passes: int = 1
	while not log_node._walk_queue.is_empty() and passes < 3000:
		log_node._continue_incoming_walk()
		passes += 1

	var total: int = log_node._incoming_deps.size()
	print("tras %d pasadas: %d rutas" % [passes, total])

	_check("la segunda pasada encuentra mas", total > first, "%d -> %d" % [first, total])
	_check("el recorrido termina", log_node._walk_queue.is_empty(), "%d pendientes" % log_node._walk_queue.size())
	# The offline walk over the same scene finds 512 files. The engine's
	# get_dependencies() sees a slightly different set - it reports imported
	# paths where the text parse sees sources - so this only pins the order of
	# magnitude, which is the thing that was wrong before.
	_check("llega al grafo real, no a 112", total >= 400, "%d rutas" % total)

	# Every path must be counted once. A resumable walk that re-queues is how
	# a denominator quietly inflates.
	var unique: Dictionary = {}
	for path in log_node._incoming_deps:
		unique[path] = true
	_check("sin duplicados", unique.size() == total, "%d unicas de %d" % [unique.size(), total])

	# _incoming_pending has to track it, or deps=N/M counts against nothing.
	_check("pending sigue al recorrido",
		log_node._incoming_pending.size() == total,
		"%d vs %d" % [log_node._incoming_pending.size(), total])

	log_node.probe_budget_usec = log_node.PROBE_BUDGET_USEC

	print("")
	if _checks < 6:
		print("FALLO: solo %d de 6 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el recorrido llega al grafo entero")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-42s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-42s%s" % [label, "  (%s)" % detail if detail else ""])
