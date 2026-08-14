extends SceneTree

## flashing_check.gd is now a suppressor only. This pins both halves of that,
## because the half that was wrong is the half that looks harmless.
##
## The old line was `visible = Settings.get(&"game_flashing_lights")`, which
## reveals as readily as it hides. Every node carrying the script is authored
## visible = false and four of the six are full-screen black ColorRects, so
## with flashing lights on it switched them all on at scene load - which is
## the black graphic covering Chimera.
##
## The suppressing half must keep working exactly as before, or the accessibility
## setting silently stops doing its job and somebody gets a face full of
## strobing. So: flashing off still hides, flashing on no longer reveals.
##
## Run with:
##   godot --headless --path . --script tools/test_flashing_check.gd

const SCRIPT := "res://lullaby_mod/scripts/lullaby/flashing_check.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	# Reached through the tree rather than as a global: the autoload exists at
	# runtime but the identifier does not resolve when compiling a --script
	# tool, and the script under test reads it the same way.
	var settings: Node = root.get_node_or_null("Settings")
	if settings == null:
		print("FALLO: no encontre el autoload Settings")
		quit(1)
		return

	var was: Variant = settings.get(&"game_flashing_lights")

	# Flashing ON: the scene's own visibility has to survive. This is the case
	# that was broken - a hidden black rect was being switched on.
	await _case(settings, true, false, false, "destellos ON, nodo oculto -> sigue oculto")
	await _case(settings, true, true, true, "destellos ON, nodo visible -> sigue visible")

	# Flashing OFF: unchanged behaviour, the whole point of the script.
	await _case(settings, false, true, false, "destellos OFF, nodo visible -> se oculta")
	await _case(settings, false, false, false, "destellos OFF, nodo oculto -> sigue oculto")

	settings.set(&"game_flashing_lights", was)

	print("")
	if _checks < 4:
		print("FALLO: solo %d de 4 comprobaciones corrieron" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - solo oculta, nunca revela")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _case(settings: Node, flashing: bool, authored: bool, want: bool, label: String) -> void:
	settings.set(&"game_flashing_lights", flashing)

	# A full-screen opaque black rect, which is what four of the six real ones
	# are - so a regression here is exactly the reported bug, not an abstraction
	# of it.
	var rect := ColorRect.new()
	rect.set_script(load(SCRIPT))
	rect.color = Color(0, 0, 0, 1)
	rect.visible = authored
	root.add_child(rect)
	await process_frame

	_checks += 1
	var got: bool = rect.visible
	if got == want:
		print("  ok    %-46s (visible=%s)" % [label, got])
	else:
		_failures += 1
		print("  FALLO %-46s (visible=%s, esperado %s)" % [label, got, want])

	rect.queue_free()
	await process_frame
