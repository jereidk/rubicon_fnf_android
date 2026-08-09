extends SceneTree

## Checks that the diagnostics log's script= bracket measures what it claims.
##
## A timer that silently reads zero, or that reports the same number whatever
## the game is doing, is worse than no timer: the next log would be read as
## "the main thread is idle, so the stall is in the GPU" and the search would
## go the wrong way. So this puts a known amount of busy work into the frame
## and checks the bracket follows it.
##
## Run with:
##   godot --headless --path . --script tools/test_script_bracket.gd

## Roughly how long each load step should burn, in milliseconds.
const LOADS := [0.0, 5.0, 15.0]

var _failures: int = 0

class Burner extends Node:
	var burn_ms: float = 0.0

	func _process(_delta: float) -> void:
		if burn_ms <= 0.0:
			return
		var until: int = Time.get_ticks_usec() + int(burn_ms * 1000.0)
		while Time.get_ticks_usec() < until:
			pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame

	var log_node: Node = root.get_node_or_null("LullabyDiagnosticsLog")
	if log_node == null:
		for child in root.get_children():
			if child.get_script() != null and "_script_usec" in child:
				log_node = child
				break
	if log_node == null:
		print("FALLO: no encontre el autoload del log")
		quit(1)
		return

	print("autoload: %s   prioridad=%d" % [log_node.name, log_node.process_priority])
	var tail: Node = log_node.get_node_or_null("ScriptTail")
	if tail == null:
		print("FALLO: no existe ScriptTail")
		quit(1)
		return
	print("cola:     %s   prioridad=%d" % [tail.name, tail.process_priority])
	print("")

	var burner := Burner.new()
	root.add_child(burner)

	print("%12s %14s %14s" % ["carga puesta", "script medido", "diferencia"])
	var previous: float = -1.0
	for load_ms: float in LOADS:
		burner.burn_ms = load_ms
		# Several frames so the reading settles; the bracket is read one
		# frame behind by design.
		for i in 20:
			await process_frame
		var measured: float = float(log_node._script_usec) / 1000.0
		print("%10.1fms %12.2fms %12.2fms" % [load_ms, measured, measured - load_ms])

		if measured <= 0.0:
			_failures += 1
			print("             FALLO: el cronometro lee cero")
		elif load_ms > 0.0 and measured < load_ms * 0.8:
			_failures += 1
			print("             FALLO: mide menos del 80%% de la carga puesta")
		elif previous >= 0.0 and measured <= previous:
			_failures += 1
			print("             FALLO: no sube al subir la carga")
		previous = measured

	print("")
	if _failures == 0:
		print("todo OK")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)
