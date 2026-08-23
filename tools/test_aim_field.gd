extends SceneTree

## `mira=` has to distinguish "the aim never moved" from "the aim is on
## something", because that is the whole question it exists to answer.
##
## The report was "no puedo apuntar al sombrero del coleccionista, siempre es
## al medio", and three readings of the scene were wrong before this existed.
## What got ruled out with numbers, and is therefore NOT what the field is
## for: the hat sits on the same collision layer as the Kollectadex and the
## board, both desk animations set its can_interact true, and projecting its
## box through the desk camera pose (-0.529, 2, 2.074 / yaw -0.575 / fov 55)
## puts it at 7.5% of the screen, clear above the Collector rather than buried
## inside him.
##
## The same projection says the screen CENTRE at that pose hits neither of
## them. So the signature to look for in a device log is a FOCUSED line
## reading `centrada` with `obj=-`: the aim never left the middle, which means
## the tap that should have latched it never reached _unhandled_input.
##
## Run with:
##   godot --headless --path . --script tools/test_aim_field.gd

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

	# Nothing to report outside the shop, which is every other scene.
	log_node.set("_aim_controller", null)
	_check("sin MouseController el campo es un guion",
		log_node.call("_aim_summary") == "-",
		log_node.call("_aim_summary"))

	# A stand-in with the same surface the real one exposes. The real
	# MouseController needs a whole shop under it; what the field reads is
	# these six members.
	var fake := _Aim.new()
	root.add_child(fake)
	log_node.set("_aim_controller", fake)

	fake.root = _Shop.new()
	fake.root.state = 2
	fake.aim = Vector2(960, 540)
	fake.touch_aim = Vector2.INF

	var centred: String = log_node.call("_aim_summary")
	_check("el caso reportado sale como centrada y sin objeto",
		centred.contains("estado=2") and centred.contains("centrada")
			and centred.contains("obj=-"),
		centred)

	# And once a tap lands on the hat.
	fake.touch_aim = Vector2(520, 210)
	fake.aim = Vector2(520, 210)
	fake.ray = _Ray.new()
	fake.ray.target = "FocusAreaHat"
	fake.colliding = true
	fake.can_click = true

	var latched: String = log_node.call("_aim_summary")
	_check("con el toque enganchado dice fijada",
		latched.contains("fijada") and not latched.contains("centrada"),
		latched)
	_check("y nombra lo que hay debajo",
		latched.contains("obj=FocusAreaHat"),
		latched)
	_check("y que un confirmar haria algo",
		latched.contains("clic=si"),
		latched)
	_check("con la posicion real, no la del centro",
		latched.contains("pos=520,210"),
		latched)

	# A pointer on something that refuses interaction is the other half: it
	# looks identical to a hit unless clic= says otherwise.
	fake.can_click = false
	_check("apuntando pero sin poder pulsar, clic=no",
		log_node.call("_aim_summary").contains("clic=no"),
		log_node.call("_aim_summary"))

	print("")
	if _checks < 7:
		print("FALLO: solo %d de 7 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - mira= separa 'nunca se movio' de 'esta sobre algo'")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

class _Shop extends Node:
	var state: int = 1

class _Ray extends Node:
	var target: String = ""
	func is_colliding() -> bool: return target != ""
	func get_collider() -> Object:
		if target == "":
			return null
		var n := Node.new()
		n.name = target
		return n

class _Aim extends Node:
	var root: Node = null
	var aim: Vector2 = Vector2.ZERO
	var touch_aim: Vector2 = Vector2.INF
	var ray_cast: Node = null
	var colliding: bool = false
	var can_click: bool = false
	var ray: Node:
		set(value):
			ray_cast = value
		get:
			return ray_cast
	func get_aim_position() -> Vector2: return aim
	func is_touch_controls_active() -> bool: return true

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-48s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-48s%s" % [label, "  (%s)" % detail if detail else ""])
