extends SceneTree

## What prewarming the note pool actually costs.
##
## The device log says the prewarm is far larger than the song ever uses.
## POOL_PREWARM_MAX is 48 per handler per note type, and a mania song runs
## eight handlers, so Monochrome allocates 384 notes - 8064 nodes, matching
## the orphans=8065 the log reports one frame after the song loads. Over the
## whole song only 55 of them are ever drawn out of the pool. Safety Lullaby
## allocates 313 and uses 31; Chimera allocates 115 and uses 27.
##
## Three separate costs could follow from that, and they are worth very
## different amounts of effort, so this measures rather than argues:
##
##   memory       - the log shows a +37.0MB single-frame jump on exactly the
##                  frame the orphan count appears.
##   time         - it happens in one frame at song start, which is added to
##                  a load the player already waits through.
##   resources    - the open question. res= climbs from 1877 to 23574 when
##                  Monochrome loads and never comes back down; the next shop
##                  load then takes 17.9s against 5.5s cold. If most of those
##                  ~21000 resources belong to the pool, the oversized pool
##                  and the slow reloads are the same bug. If the count barely
##                  moves per instance, they are unrelated and this only ever
##                  buys back RAM.
##
## Run with:
##   godot --headless --path . --script tools/measure_note_pool_cost.gd

const NOTE_SCENE := "res://addons/rubicon_mania/resources/skins/default/Note.tscn"

## What one mania song actually allocates: eight handlers at the cap.
const HANDLERS := 8
const PREWARM_PER_HANDLER := 48

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var packed: PackedScene = load(NOTE_SCENE)
	if packed == null:
		print("FALLO: no pude cargar %s" % NOTE_SCENE)
		quit(1)
		return

	# One instance first, so the per-instance figures are not diluted by the
	# scene's own load.
	var warm: Node = packed.instantiate()
	var node_count: int = _count_nodes(warm)
	warm.free()
	await process_frame

	var total: int = HANDLERS * PREWARM_PER_HANDLER
	print("Note.tscn: %d nodos por instancia" % node_count)
	print("prewarm de una cancion: %d x %d = %d notas = %d nodos" % [
		HANDLERS, PREWARM_PER_HANDLER, total, total * node_count,
	])
	print("")

	var res_before: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var mem_before: int = OS.get_static_memory_usage()
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var began: int = Time.get_ticks_usec()

	var pool: Array[Node] = []
	for i in total:
		pool.append(packed.instantiate())

	var spent_ms: float = float(Time.get_ticks_usec() - began) / 1000.0
	var res_after: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var mem_after: int = OS.get_static_memory_usage()
	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	var res_delta: int = res_after - res_before
	var mem_delta: float = float(mem_after - mem_before) / 1048576.0

	print("instanciar %d notas:" % total)
	print("  tiempo    : %.1f ms  (%.3f ms por nota)" % [spent_ms, spent_ms / float(total)])
	print("  memoria   : %+.1f MB  (%.1f KB por nota)" % [
		mem_delta, mem_delta * 1024.0 / float(total),
	])
	print("  huerfanos : %+d  (esperado %d)" % [
		orphans_after - orphans_before, total * node_count,
	])
	print("  recursos  : %+d  (%.1f por nota)" % [res_delta, float(res_delta) / float(total)])
	print("")

	# The device's own numbers, for the comparison this exists to make.
	print("en el dispositivo Monochrome reporta:")
	print("  huerfanos = 8065 al arrancar, 6910 al terminar -> 55 notas usadas de 384")
	print("  MEMORY    = +37.0 MB en un frame, en el frame en que aparecen")
	print("  res       = 1877 antes de cargar -> 23574 despues (+21697)")
	print("")

	if res_delta >= 10000:
		print("VEREDICTO: el pool explica la mayor parte de los ~21000 recursos.")
		print("           Reducirlo ataca tambien las recargas de 18s.")
	elif res_delta >= 1000:
		print("VEREDICTO: el pool aporta una parte de los ~21000 recursos, no todo.")
	else:
		print("VEREDICTO: el pool NO explica los ~21000 recursos - son otra cosa.")
		print("           Reducirlo solo recupera RAM y el tiron del arranque.")

	# What a right-sized pool would cost instead. PARK_MAX is 24 per handler
	# and the log peaks at ~22 notes alive across every lane at once, so the
	# working set is nowhere near the cap.
	var used: int = 55
	print("")
	print("si el pool cubriera lo que la cancion usa (%d notas):" % used)
	print("  memoria   : %.1f MB en vez de %.1f MB" % [
		mem_delta * float(used) / float(total), mem_delta,
	])
	print("  tiempo    : %.1f ms en vez de %.1f ms" % [
		spent_ms * float(used) / float(total), spent_ms,
	])

	for note in pool:
		note.free()
	pool.clear()

	quit(0)

func _count_nodes(root_node: Node) -> int:
	var n: int = 1
	for child in root_node.get_children():
		n += _count_nodes(child)
	return n
