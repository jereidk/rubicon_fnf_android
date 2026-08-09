extends SceneTree

## Measures what a live note costs per frame when nobody is doing anything to
## it - no scrolling, no hits, no spawning. Just the mixers inside it ticking.
##
## The funkin mania note carries three AnimationTrees whose state machines
## decide direction, missed and held. All twelve of their transitions are
## advance_mode = AUTO with an advance_expression, so every one is compiled
## into an Expression and executed once per frame per note, forever - and two
## of them call back into GDScript (was_hit(), was_missed()).
##
## Wall clock is useless here: the settings autoload pins Engine.max_fps to
## the user's target every frame, so every row would read 16.666ms. What is
## timed instead is the idle process pass itself, bracketed by two nodes at
## the extremes of process_priority - the same trick the diagnostics log's
## script= field uses, and the one that showed these frames are main-thread
## busy rather than waiting on the GPU.
##
## Run with:
##   godot --headless --path . --script tools/bench_note_trees.gd

const NOTE := "res://resources/levels/ui/funkin/mania/Note.tscn"
const COUNTS := [0, 1, 8, 24, 48]
const WARMUP := 30
const FRAMES := 240

## Well outside anything the game itself sets, so the bracket really does
## enclose every other _process in the tree.
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

var _holder: Node
var _head: _Head
var _tail: _Tail
var _empty_frame: float = 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load(NOTE)
	if packed == null:
		print("FALLO: no pude cargar %s" % NOTE)
		quit(1)
		return

	_head = _Head.new()
	_head.process_priority = PROCESS_FIRST
	root.add_child(_head)

	_tail = _Tail.new()
	_tail.head = _head
	_tail.process_priority = PROCESS_LAST
	root.add_child(_tail)

	print("nota: %s" % NOTE)
	print("")
	print(" notas |    stock ms/pase |     pump ms/pase | ahorro | us/nota")
	print("-------+------------------+------------------+--------+--------")

	for count: int in COUNTS:
		var on: float = await _measure(packed, count, true)
		var off: float = await _measure(packed, count, false)
		if count == 0:
			# Everything after this is the cost of the notes alone.
			_empty_frame = minf(on, off)
			print("%6d | %16.4f | %16.4f |      - |       -" % [count, on, off])
			continue

		var net_on: float = on - _empty_frame
		var net_off: float = off - _empty_frame
		print("%6d | %16.4f | %16.4f | %5.1f%% | %6.1f" % [
			count, on, off,
			100.0 * (net_on - net_off) / net_on if net_on > 0.0 else 0.0,
			1000.0 * net_on / float(count)])

	print("")
	print("ms/pase es el pase de proceso completo, promediado sobre %d frames" % FRAMES)
	print("tras %d de calentamiento. us/nota descuenta el pase vacio." % WARMUP)
	quit(0)

## Builds `count` notes, lets them settle, then times the idle process pass.
##
## [param stock] restores what the scene file asks for - every tree advancing
## itself once per frame - by handing the pump's trees back. Otherwise the
## notes run as shipped, which is what _ready() already set up.
func _measure(packed: PackedScene, count: int, stock: bool) -> float:
	_holder = Node.new()
	root.add_child(_holder)

	for i in count:
		var note: Node = packed.instantiate()
		# lane_id decides which of the four DirectionTree branches wins, so
		# spread them the way a real strumline does.
		note.lane_id = i % 4
		_holder.add_child(note)
		if stock:
			note._pump.release()

	# Long enough that the pumped notes have gone back to sleep, so what is
	# timed is the steady state rather than the settle.
	for i in WARMUP:
		await process_frame

	_tail.total = 0
	_tail.frames = 0
	_tail.counting = true
	for i in FRAMES:
		await process_frame
	_tail.counting = false

	_holder.queue_free()
	_holder = null
	await process_frame

	if _tail.frames == 0:
		print("FALLO: el bracket no midio ningun frame")
		quit(1)
		return 0.0

	return float(_tail.total) / float(_tail.frames) / 1000.0

func _unused_trees(note: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in note.get_children():
		if child is AnimationTree:
			found.append(child)
	return found
