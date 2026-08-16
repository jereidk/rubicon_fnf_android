extends SceneTree

## The log must report the render scale the viewport uses, not the one asked
## for.
##
## Both places that printed it read Settings.graphics_render_scale, which is
## the request. settings.gd applies it as window.scaling_3d_scale, so anything
## that resets that leaves the log printing 0.50 over a viewport rendering at
## full size - and 1600x720 against 800x360 is four times the pixels, the
## order of the gap this field is being used to reason about.
##
## Chimera holds gpu= at 34ms where the shop sits at 14 with more meshes, more
## lights, and ASTC on all 553 MPx of its textures. 288k pixels at 7x overdraw
## is not 34ms on this GPU, so whether it renders at the scale it claims is
## worth being able to read rather than assume.
##
## Run with:
##   godot --headless --path . --script tools/test_render_scale_report.gd

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

	# Fetched from the tree rather than by the global name: a --script
	# SceneTree does not have autoload identifiers bound at compile time, and
	# naming Settings directly stops this file compiling at all.
	var settings: Node = root.get_node_or_null(^"Settings")
	if settings == null:
		print("FALLO: no existe el autoload Settings")
		quit(1)
		return

	var original: float = root.scaling_3d_scale
	var asked: float = settings.graphics_render_scale

	# Agreeing: one number, no noise.
	root.scaling_3d_scale = asked
	var agree: String = log_node._render_scale()
	_check("cuando coinciden imprime un solo numero",
		not agree.contains("pedido"), agree)

	# Disagreeing: the field has to say so, and lead with what is real.
	root.scaling_3d_scale = 1.0 if not is_equal_approx(asked, 1.0) else 0.5
	var differ: String = log_node._render_scale()
	_check("cuando difieren lo dice", differ.contains("pedido"), differ)
	_check("y empieza por el valor real",
		differ.begins_with("%.2f" % root.scaling_3d_scale), differ)
	_check("sin confundirlo con el pedido",
		not differ.begins_with("%.2f(" % asked) or is_equal_approx(asked, root.scaling_3d_scale),
		differ)

	root.scaling_3d_scale = original

	print("")
	if _checks < 4:
		print("FALLO: solo %d de 4 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el log informa de la escala real")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])
