extends SceneTree

## What a whole strumline costs per frame, stock against pumped.
##
## Two player-facing barlines of four lanes each is what Monochrome puts on
## screen in Showcase, and the diagnostics log's census peaks at 24 notes
## alive across them. Every one of those objects carries state machines whose
## transitions are advance_mode = AUTO with an advance_expression: 24 per
## lane, 12 per note. None of them can move unless lane_id, lane_state,
## was_hit() or was_missed() changed, which is what RubiconMixerPump uses to
## decide whether to advance the tree at all.
##
## Timed the same way the diagnostics log times script=: two nodes at the
## extremes of process_priority bracketing the idle process pass. Wall clock
## would only measure the settings autoload's fps cap.
##
## Run with:
##   godot --headless --path . --script tools/bench_strumline.gd

const LANE := "res://resources/levels/ui/funkin/mania/Lane.tscn"
const NOTE := "res://resources/levels/ui/funkin/mania/Note.tscn"

const LANES := 8
## Empty, the census figure for Monochrome, and a dense section.
const NOTE_COUNTS := [0, 12, 24, 48]

const WARMUP := 40
const FRAMES := 300

const PROCESS_FIRST := -100000
const PROCESS_LAST := 100000

class _Head extends Node:
	var began: int = 0
	func _process(_delta: float) -> void:
		began = Time.get_ticks_usec()

class _Tail extends Node:
	var head: _Head
	var total: int = 0
	var frames: int = 0
	var counting: bool = false
	func _process(_delta: float) -> void:
		if not counting:
			return
		total += Time.get_ticks_usec() - head.began
		frames += 1

var _head: _Head
var _tail: _Tail

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lane_scene: PackedScene = load(LANE)
	var note_scene: PackedScene = load(NOTE)
	if lane_scene == null or note_scene == null:
		print("FALLO: no pude cargar las escenas")
		quit(1)
		return

	_head = _Head.new()
	_head.process_priority = PROCESS_FIRST
	root.add_child(_head)

	_tail = _Tail.new()
	_tail.head = _head
	_tail.process_priority = PROCESS_LAST
	root.add_child(_tail)

	print("%d lanes + N notas, pase de proceso en ms" % LANES)
	print("")
	print(" notas |     stock |      pump | ahorro |  ms menos")
	print("-------+-----------+-----------+--------+----------")

	for count: int in NOTE_COUNTS:
		var stock: float = await _measure(lane_scene, note_scene, count, true)
		var pumped: float = await _measure(lane_scene, note_scene, count, false)
		print("%6d | %9.4f | %9.4f | %5.1f%% | %8.4f" % [
			count, stock, pumped,
			100.0 * (stock - pumped) / stock if stock > 0.0 else 0.0,
			stock - pumped])

	print("")
	print("Promedio de %d frames tras %d de calentamiento." % [FRAMES, WARMUP])
	print("En reposo: nadie pulsa nada, que es el caso mas comun por frame.")
	quit(0)

func _measure(lane_scene: PackedScene, note_scene: PackedScene, notes: int,
		stock: bool) -> float:
	var holder := Node.new()
	root.add_child(holder)

	var lanes: Array[RubiconLevelManiaNoteHandler] = []
	for i in LANES:
		var lane: RubiconLevelManiaNoteHandler = lane_scene.instantiate()
		lane.lane_id = i % 4
		holder.add_child(lane)
		if stock:
			lane._pump.release()
		lanes.append(lane)

	for i in notes:
		var lane: RubiconLevelManiaNoteHandler = lanes[i % LANES]
		var note: RubiconLevelManiaNote = note_scene.instantiate()
		note.lane_id = lane.lane_id
		lane.add_child(note)
		if stock:
			note._pump.release()

	for i in WARMUP:
		await process_frame

	_tail.total = 0
	_tail.frames = 0
	_tail.counting = true
	for i in FRAMES:
		await process_frame
	_tail.counting = false

	holder.queue_free()
	await process_frame

	if _tail.frames == 0:
		print("FALLO: el bracket no midio ningun frame")
		quit(1)
		return 0.0

	return float(_tail.total) / float(_tail.frames) / 1000.0
