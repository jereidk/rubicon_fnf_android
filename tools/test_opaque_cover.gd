extends SceneTree

## The census now names any visible, opaque, full-frame CanvasItem. This
## checks it names the right ones.
##
## The reason it exists: Chimera puts a plain black ColorRect over its own
## song and no counter in the log could see it. fx= only looks at items
## carrying a shader, and these have none. Every other explanation for that
## black screen has now been ruled out with evidence, so the next log has to
## be able to answer "what is on top" directly instead of by elimination.
##
## The case worth getting right is the false positive: an opaque rect inside
## a parent faded to nothing hides nothing at all, and a counter that reports
## it would send the next investigation somewhere wrong - which is the exact
## failure mode this whole hunt has been suffering from.
##
## Run with:
##   godot --headless --path . --script tools/test_opaque_cover.gd

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var log_node: Node = root.get_node_or_null("DiagnosticsLog")
	if log_node == null:
		print("FALLO: no encontre el autoload DiagnosticsLog")
		quit(1)
		return

	var screen: Vector2 = root.get_visible_rect().size
	print("pantalla: %s" % screen)

	# Opaque, full-frame: the thing being hunted.
	await _case(log_node, "negro opaco a pantalla completa", screen, Color(0, 0, 0, 1), 1.0, 1.0, true)

	# The same rect, faded out by its own colour.
	await _case(log_node, "el mismo con alpha 0 en el color", screen, Color(0, 0, 0, 0), 1.0, 1.0, false)

	# Faded by its own modulate.
	await _case(log_node, "opaco pero con modulate 0", screen, Color(0, 0, 0, 1), 0.0, 1.0, false)

	# The false positive that matters: opaque, but its parent is invisible.
	await _case(log_node, "opaco dentro de un padre a modulate 0", screen, Color(0, 0, 0, 1), 1.0, 0.0, false)

	# Half faded - visible, but not a cover.
	await _case(log_node, "medio transparente no cuenta", screen, Color(0, 0, 0, 0.5), 1.0, 1.0, false)

	# Too small to hide the game.
	await _case(log_node, "pequeno no cuenta", screen * 0.3, Color(0, 0, 0, 1), 1.0, 1.0, false)

	print("")
	if _failures == 0:
		print("todo OK - nombra lo que tapa y solo lo que tapa")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _case(log_node: Node, label: String, size: Vector2, color: Color,
		modulate_a: float, parent_a: float, want: bool) -> void:
	var parent := Control.new()
	parent.modulate = Color(1, 1, 1, parent_a)
	root.add_child(parent)

	var rect := ColorRect.new()
	rect.color = color
	rect.modulate = Color(1, 1, 1, modulate_a)
	rect.size = size
	parent.add_child(rect)

	await process_frame
	await process_frame

	# What the census asks of every CanvasItem it walks.
	var big: bool = log_node._covers_screen(rect)
	var opacity: float = log_node._opaque_coverage(rect)
	var visible_now: bool = rect.is_visible_in_tree()
	var counted: bool = big and visible_now and opacity >= 0.95

	if counted == want:
		print("  ok    %-38s tapa=%s cobertura=%.2f" % [label, counted, opacity])
	else:
		_failures += 1
		print("  FALLO %-38s tapa=%s esperaba=%s cobertura=%.2f" % [label, counted, want, opacity])

	parent.queue_free()
	await process_frame
