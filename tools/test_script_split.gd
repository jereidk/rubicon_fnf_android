extends SceneTree

## SCRIPTSPLIT must switch the animation mixers off for exactly one frame, and
## put back exactly what it found.
##
## `rest=` - the part of the idle step no counter claims - is the whole of
## Chimera's script cost: p50 5.24ms, p90 24.18ms, max 30.60ms against notes=
## at p50 1.24. Correlating it against every counter the log already keeps
## explains none of it (players playing r=+0.26, nodes with _process +0.14,
## tweens -0.16, bones -0.14), so the only way forward is to measure it, and
## the engine's animation step has no bracket a GDScript node can put around
## it. Switching the mixers off for one frame and subtracting does have one.
##
## The hazards are both in the restore, and both are the sort that read as
## "the song broke halfway through" rather than as a logging bug:
##
##   1. a mixer left inactive freezes whatever it drives for the rest of the
##      scene
##   2. a mixer the scene had deliberately stopped must NOT come back on -
##      Chimera stops players between sequences, and starting them again would
##      play animation nobody asked for
##
## Run with:
##   godot --headless --path . --script tools/test_script_split.gd

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var log_node: Node = root.get_node_or_null(^"DiagnosticsLog")
	if log_node == null:
		print("FALLO: no existe el autoload DiagnosticsLog")
		quit(1)
		return

	# Both splits ship off - they alter the frame the player sees, which is how
	# the GPU one was found: reported from the device as "un flash blanco
	# opaco" in both 3D scenes. Switched on here because what is under test is
	# the probe's behaviour, not its default; test_gpu_split.gd owns the
	# default.
	var settings: Node = root.get_node_or_null(^"Settings")
	if settings == null:
		print("FALLO: no existe el autoload Settings")
		quit(1)
		return
	settings.diagnostics_gpu_split = true

	var scene := Node.new()
	var running := AnimationPlayer.new()
	running.name = "Corriendo"
	var stopped := AnimationPlayer.new()
	stopped.name = "Parado"
	stopped.active = false
	scene.add_child(running)
	scene.add_child(stopped)
	root.add_child(scene)
	current_scene = scene

	var found: Array = log_node.call("_active_mixers")
	_check("solo recoge los mixers activos",
		found.size() == 1 and found[0] == running,
		"encontro %d" % found.size())

	# Force the sample: the gate is twenty seconds of wall clock.
	log_node.set("_time_since_script_split", 1000000.0)
	log_node.set("_last_frame_wall_ms", 16.0)
	log_node.set("_script_usec", 8000)
	log_node.call("_step_script_split")

	_check("el frame de muestra apaga el mixer activo",
		not running.active,
		"active=%s" % running.active)
	_check("y no toca el que ya estaba parado",
		not stopped.active,
		"active=%s" % stopped.active)
	_check("queda en el estado de sonda",
		log_node.get("_script_split_state") == 1,
		"estado=%d" % log_node.get("_script_split_state"))

	# Second call: restore.
	log_node.set("_script_usec", 5000)
	log_node.call("_step_script_split")

	_check("el frame siguiente lo vuelve a encender",
		running.active,
		"active=%s" % running.active)
	_check("y el que estaba parado SIGUE parado",
		not stopped.active,
		"active=%s" % stopped.active)
	_check("vuelve al estado de espera",
		log_node.get("_script_split_state") == 0
			and (log_node.get("_script_split_paused") as Array).is_empty(),
		"estado=%d pendientes=%d" % [log_node.get("_script_split_state"),
			(log_node.get("_script_split_paused") as Array).size()])

	# A scene with nothing animating must not arm the probe, or it would walk
	# the tree on every frame forever waiting for a mixer to appear.
	stopped.queue_free()
	running.queue_free()
	await process_frame
	log_node.set("_time_since_script_split", 1000000.0)
	log_node.call("_step_script_split")
	_check("una escena sin animacion no arma la sonda",
		log_node.get("_script_split_state") == 0
			and log_node.get("_time_since_script_split") == 0.0,
		"estado=%d reloj=%.1f" % [log_node.get("_script_split_state"),
			log_node.get("_time_since_script_split")])

	print("")
	if _checks < 8:
		print("FALLO: solo %d de 8 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - SCRIPTSPLIT mide un frame y devuelve la escena como estaba")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
