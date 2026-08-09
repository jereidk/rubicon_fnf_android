extends SceneTree

## The render scale row now shrinks SubViewport render targets too, and this
## checks it shrinks the right thing.
##
## A SubViewport has two sizes: the render target, and the 2D coordinate
## space the Controls inside lay themselves out against. Only the first may
## move. Halve the second and every Control inside reflows - buttons move,
## text wraps differently - which would be a layout change dressed up as a
## performance one.
##
## Run with:
##   godot --headless --path . --script tools/test_subviewport_scale.gd

const AUTHORED := Vector2i(1240, 928)

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var settings: Node = root.get_node_or_null("Settings")
	if settings == null:
		print("FALLO: no encontre el autoload Settings")
		quit(1)
		return

	var was: float = settings.graphics_render_scale

	# A Control inside, to prove the layout it sees does not move.
	var viewport := SubViewport.new()
	viewport.size = AUTHORED
	root.add_child(viewport)

	var inside := Control.new()
	inside.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(inside)
	await process_frame

	var laid_out_at: Vector2 = inside.size

	settings.graphics_render_scale = 0.5
	settings.apply_settings()
	await process_frame

	_check("el destino de render se reduce a la mitad",
		viewport.size == Vector2i(620, 464), "size=%s" % viewport.size)
	_check("el espacio 2D sigue siendo el autorado",
		viewport.size_2d_override == AUTHORED, "override=%s" % viewport.size_2d_override)
	_check("y el Control de dentro no se ha movido",
		inside.size == laid_out_at, "%s -> %s" % [laid_out_at, inside.size])

	# Applying twice must not scale an already-scaled viewport.
	settings.apply_settings()
	await process_frame
	_check("aplicar dos veces no vuelve a encoger",
		viewport.size == Vector2i(620, 464), "size=%s" % viewport.size)

	# And going back up restores the full target.
	settings.graphics_render_scale = 1.0
	settings.apply_settings()
	await process_frame
	_check("volver a 1.0 restaura el tamano completo",
		viewport.size == AUTHORED, "size=%s" % viewport.size)

	# A viewport whose pixels get read rather than looked at opts out.
	var native := SubViewport.new()
	native.size = AUTHORED
	native.add_to_group(settings.SUBVIEWPORT_NATIVE_GROUP)
	root.add_child(native)
	settings.graphics_render_scale = 0.5
	settings.apply_settings()
	await process_frame
	_check("un viewport marcado como nativo se queda igual",
		native.size == AUTHORED, "size=%s" % native.size)

	# A viewport added after the settings were applied still gets scaled -
	# which is every viewport in a scene loaded later, i.e. the shop's.
	var late := SubViewport.new()
	late.size = AUTHORED
	root.add_child(late)
	await process_frame
	_check("uno anadido despues tambien se escala",
		late.size == Vector2i(620, 464), "size=%s" % late.size)

	settings.graphics_render_scale = was
	settings.apply_settings()
	viewport.queue_free()
	native.queue_free()
	late.queue_free()

	print("")
	if _failures == 0:
		print("todo OK - solo encoge el render, no el espacio 2D")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s" % name)
	else:
		_failures += 1
		print("  FALLO %s  (%s)" % [name, detail])
