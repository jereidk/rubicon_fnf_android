extends SceneTree

## Hiding one action button must re-centre the others.
##
## They used to sit at hardcoded offsets anchored to the right edge - F at
## -410..-220, Enter at -200..-10, Back at 10..200 - so hiding one left a 190
## pixel hole where it had been and moved nothing. On a screen where the
## cartridge bag is unavailable that reads as Enter and Back sitting low and
## off-centre against an empty space.
##
## What is asserted is the behaviour, not the node type: that all three are
## centred on the column while shown, that hiding one re-centres the rest, and
## that nothing moves when all three are visible - a layout change that
## silently shifted the buttons in the normal case would be a regression even
## if the reflow worked.
##
## Run with:
##   godot --headless --path . --script tools/test_action_column_reflow.gd

const SCENE := "res://addons/rubicon_mobile_controls/menu_touch_controls.tscn"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var controls: Control = load(SCENE).instantiate()
	root.add_child(controls)
	controls.size = Vector2(1920, 1080)
	# Containers sort on NOTIFICATION_SORT_CHILDREN, which is queued rather
	# than immediate. Two frames was not enough after a resize and every
	# position read back as zero, which looked like the container not working.
	await _settle()

	var column: Control = controls.get_node_or_null(^"ActionColumn")
	_check("existe la columna", column != null)
	if column == null:
		_finish()
		return

	var f: Control = column.get_node_or_null(^"SwitchCartridgeButton")
	var enter: Control = column.get_node_or_null(^"AcceptButton")
	var back: Control = column.get_node_or_null(^"CancelButton")
	_check("los tres botones estan en ella", f != null and enter != null and back != null)
	if f == null or enter == null or back == null:
		_finish()
		return

	_check("conservan su tamano autorizado",
		is_equal_approx(f.size.x, 190.0) and is_equal_approx(f.size.y, 190.0),
		"%.0fx%.0f" % [f.size.x, f.size.y])

	# Centred as a group, with all three shown.
	var group_mid: float = (f.position.y + back.position.y + back.size.y) * 0.5
	_check("el grupo esta centrado en la columna",
		absf(group_mid - column.size.y * 0.5) <= 2.0,
		"centro %.0f de %.0f" % [group_mid, column.size.y])

	var enter_before: float = enter.position.y

	# Hide the one the shop hides when the cartridge bag is unavailable.
	f.visible = false
	await _settle()

	_check("ocultar F mueve a Enter", not is_equal_approx(enter.position.y, enter_before),
		"%.0f -> %.0f" % [enter_before, enter.position.y])

	var two_mid: float = (enter.position.y + back.position.y + back.size.y) * 0.5
	_check("y los dos que quedan vuelven a centrarse",
		absf(two_mid - column.size.y * 0.5) <= 2.0,
		"centro %.0f de %.0f" % [two_mid, column.size.y])

	_check("sin hueco entre ellos",
		absf((back.position.y - (enter.position.y + enter.size.y)) - 20.0) <= 1.0,
		"separacion %.0f" % (back.position.y - (enter.position.y + enter.size.y)))

	# And back again: restoring it must restore the original layout exactly.
	f.visible = true
	await _settle()
	_check("volver a mostrarla restaura la posicion",
		is_equal_approx(enter.position.y, enter_before),
		"%.0f" % enter.position.y)

	controls.queue_free()
	await process_frame
	_finish()

## Layout settles over a few frames; waiting on one is a race.
func _settle() -> void:
	for i in 6:
		await process_frame

func _finish() -> void:
	print("")
	if _checks < 8:
		print("FALLO: solo %d de 8 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - la columna se reacomoda y sigue centrada")
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
