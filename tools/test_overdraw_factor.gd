extends SceneTree

## The census now reports an overdraw factor - how many times the frame is
## painted. This checks it counts what is drawn and nothing else.
##
## It is the last standing explanation for Safety Lullaby and Chimera sitting
## at 30fps with 40 draw calls and 890 primitives. Script, shaders, lights,
## presentation, thermal throttling and texture weight were each ruled out
## with numbers from the device - Monochrome carries three times Chimera's
## texture load and holds 60fps - so what is left is painting the same pixels
## many times over.
##
## A metric that over-reports would send this somewhere wrong, which has
## happened enough times already. The cases that could do it: something
## hanging off the edge of the screen, something hidden, and a bare Node2D
## whose children are counted separately.
##
## Run with:
##   godot --headless --path . --script tools/test_overdraw_factor.gd

var _failures: int = 0
var _log: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	_log = root.get_node_or_null("DiagnosticsLog")
	if _log == null:
		print("FALLO: no encontre el autoload DiagnosticsLog")
		quit(1)
		return

	var screen: Vector2 = root.get_visible_rect().size
	var full: float = screen.x * screen.y
	print("pantalla: %s  (%.0f px)" % [screen, full])
	print("")

	await _case("a pantalla completa cuenta 1x", screen, Vector2.ZERO, 1.0)
	await _case("la mitad de ancho cuenta 0.5x", Vector2(screen.x * 0.5, screen.y), Vector2.ZERO, 0.5)

	# Half of it hangs off the right edge, so only half is painted.
	await _case("lo que sale de pantalla no cuenta",
		screen, Vector2(screen.x * 0.5, 0.0), 0.5)

	# Entirely off screen.
	await _case("fuera de pantalla cuenta 0",
		screen, Vector2(screen.x * 2.0, 0.0), 0.0)

	await _hidden_case(screen)
	await _node2d_case()

	print("")
	if _failures == 0:
		print("todo OK - cuenta lo que se pinta")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _case(label: String, size: Vector2, offset: Vector2, want: float) -> void:
	var rect := ColorRect.new()
	rect.size = size
	rect.position = offset
	root.add_child(rect)
	await process_frame

	var got: float = _log._screen_area(rect) / _log._screen_px()
	_check(label, is_equal_approx(snappedf(got, 0.01), want), "%.2fx" % got)

	rect.queue_free()
	await process_frame

## Hidden things are not painted, so they must not be counted - the census
## only calls _screen_area on visible items, and this pins that contract.
func _hidden_case(screen: Vector2) -> void:
	var rect := ColorRect.new()
	rect.size = screen
	rect.visible = false
	root.add_child(rect)
	await process_frame

	_check("lo oculto no llega al contador", not rect.is_visible_in_tree())

	rect.queue_free()
	await process_frame

## A bare Node2D draws nothing itself; its children are walked separately, so
## counting it as well would double every sprite under it.
func _node2d_case() -> void:
	var holder := Node2D.new()
	root.add_child(holder)
	await process_frame

	var got: float = _log._screen_area(holder)
	_check("un Node2D pelado no suma area", is_zero_approx(got), "%.1f px" % got)

	holder.queue_free()
	await process_frame

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %-40s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-40s%s" % [label, "  (%s)" % detail if detail else ""])
