extends SceneTree

## Hiding a contextual button must close its gap, not leave a hole.
##
## The shop's four buttons are authored at -410, -200, +10 and +220, each 190
## tall with a 20 gap - a centred column of four. Each is pinned to its own
## absolute slot, so hiding one leaves a 190 pixel hole and moves nothing.
## PowerButton already hides itself correctly through visible_source; what the
## player sees is the hole it leaves.
##
## Driven through real Controls with the real script rather than the shop
## scene, which would drag the whole room in for a layout rule.
##
## Run with:
##   godot --headless --path . --script tools/test_action_column.gd

const COLUMN := "res://addons/rubicon_mobile_controls/action_column.gd"
const BUTTON := "res://addons/rubicon_mobile_controls/action_button.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var host := Control.new()
	root.add_child(host)

	# The authored slots, in scene order.
	var slots := [-410.0, -200.0, 10.0, 220.0]
	var buttons: Array[Control] = []
	for top in slots:
		var b := Button.new()
		b.set_script(load(BUTTON))
		b.offset_top = top
		b.offset_bottom = top + 190.0
		host.add_child(b)
		buttons.append(b)

	var column := Node.new()
	column.set_script(load(COLUMN))
	host.add_child(column)
	await process_frame

	_check("encuentra los cuatro", column._buttons.size() == 4,
		"%d" % column._buttons.size())
	_check("y en el orden autorizado",
		column._buttons.size() == 4 and is_equal_approx(column._buttons[0].offset_top, -410.0))

	# Nothing may move while all four are shown.
	var unchanged: bool = true
	for i in buttons.size():
		if not is_equal_approx(buttons[i].offset_top, slots[i]):
			unchanged = false
	_check("con los cuatro visibles nada se mueve", unchanged,
		"%.0f %.0f %.0f %.0f" % [buttons[0].offset_top, buttons[1].offset_top,
			buttons[2].offset_top, buttons[3].offset_top])

	# Hide the first: three left, still centred, no gap.
	buttons[0].visible = false
	await process_frame
	var span: float = buttons[3].offset_bottom - buttons[1].offset_top
	_check("ocultar uno deja tres pegados", is_equal_approx(span, 3 * 190.0 + 2 * 20.0),
		"%.0f" % span)
	_check("y centrados", is_equal_approx(buttons[1].offset_top + span * 0.5, 0.0),
		"centro %.0f" % (buttons[1].offset_top + span * 0.5))
	_check("sin hueco entre ellos",
		is_equal_approx(buttons[2].offset_top - buttons[1].offset_bottom, 20.0),
		"%.0f" % (buttons[2].offset_top - buttons[1].offset_bottom))

	# Hide Power too: the middle pair, centred.
	buttons[3].visible = false
	await process_frame
	var pair: float = buttons[2].offset_bottom - buttons[1].offset_top
	_check("con dos siguen centrados", is_equal_approx(buttons[1].offset_top + pair * 0.5, 0.0),
		"centro %.0f" % (buttons[1].offset_top + pair * 0.5))

	# Restoring puts the authored layout back exactly.
	buttons[0].visible = true
	buttons[3].visible = true
	await process_frame
	var restored: bool = true
	for i in buttons.size():
		if not is_equal_approx(buttons[i].offset_top, slots[i]):
			restored = false
	_check("volver a mostrarlos restaura lo autorizado", restored,
		"%.0f %.0f %.0f %.0f" % [buttons[0].offset_top, buttons[1].offset_top,
			buttons[2].offset_top, buttons[3].offset_top])

	host.queue_free()
	await process_frame

	print("")
	if _checks < 8:
		print("FALLO: solo %d de 8 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - la columna se cierra y sigue centrada")
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
