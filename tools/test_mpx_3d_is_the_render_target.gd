extends SceneTree

## `mpx3d=` must describe the pixels the GPU fills, not the ones 2D is laid out in.
##
## This project ships `window/stretch/mode="canvas_items"` with `aspect="keep"`.
## Under that mode `get_visible_rect()` returns the BASE resolution - a constant
## 1920x1080 on every device, because it is the coordinate space canvas items
## are positioned in. The render target is the window, letterboxed to the
## aspect: 1280x720 on the moto g53's 1600x720 panel.
##
## `_mpx_3d()` read the first one. The tell was in the logs and nobody read it:
## `mpx3d=0.518` on every single GPUSPLIT line, across two render scales, two
## scenes and two devices. A number that never moves is not a measurement of
## anything, and 0.518 is exactly 1920 x 1080 x 0.50^2.
##
## The cost of that was not the field itself. It is that every ms/Mpx figure in
## this repo divides by it: the 90.8 ms/Mpx slope fitted for Chimera, the "6-8
## lights per fragment" read off that slope against an isolation bench, and
## `luz_por_mpx` in GPUSPLIT. All of them are 2.25x low, and two render-scale
## decisions have already been made and reversed off models like these.
##
## What this pins is the property that makes the field a measurement at all:
## when the render target and the base resolution differ, mpx3d follows the
## render target. Pinning the exact value would pin the harness's own window
## size, which is not the invariant and changes with the display server.
##
## Run with:
##   godot --headless --path . --script tools/test_mpx_3d_is_the_render_target.gd

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

	var base: Vector2i = root.get_visible_rect().size
	var target: Vector2i = root.get_texture().get_size()
	var scale: float = root.scaling_3d_scale

	_check("el arnes reproduce el caso: base != destino de render",
		base != target,
		"base=%dx%d destino=%dx%d" % [base.x, base.y, target.x, target.y])

	var reported: float = log_node.call("_mpx_3d")
	var from_target: float = float(target.x) * float(target.y) * scale * scale / 1000000.0
	var from_base: float = float(base.x) * float(base.y) * scale * scale / 1000000.0

	_check("mpx3d sigue al destino de render",
		absf(reported - from_target) < 0.0005,
		"informa %.4f, destino %.4f" % [reported, from_target])

	_check("y NO a la resolucion base",
		absf(reported - from_base) > 0.0005,
		"base daria %.4f" % from_base)

	# The bug's own signature: a value that does not move when the render scale
	# does is not measuring the render.
	root.scaling_3d_scale = 0.5
	await process_frame
	var half: float = log_node.call("_mpx_3d")
	root.scaling_3d_scale = scale
	await process_frame

	_check("y se mueve con la escala de render",
		half < reported * 0.9,
		"a escala 0.50 informa %.4f contra %.4f" % [half, reported])

	print("")
	if _checks < 4:
		print("FALLO: solo %d de 4 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - mpx3d mide los pixeles que la GPU rellena")
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
