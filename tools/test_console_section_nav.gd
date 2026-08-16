extends SceneTree

## in_section_nav is the state the F button is allowed to appear in.
##
## F switches the cartridge, which only means anything while the player is
## moving between the console's sections - TV, Settings, Training - and that
## is also the only place the F prompt is drawn. It was wired to nothing and
## showed always.
##
## The button's own two conditions are AND'd and neither can be inverted,
## while this state is "focused AND NOT in a submenu AND NOT still booting".
## So it is named on the console instead, and this pins the truth table -
## including booting, which back_out() already refuses to run during and
## which this project has watched get stuck true for a whole scene.
##
## Run with:
##   godot --headless --path . --script tools/test_console_section_nav.gd

const CONSOLE := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/console.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	# Never added to the tree: _ready() reaches for children this double does
	# not have, and the property under test touches none of them.
	var console := Control.new()
	console.set_script(load(CONSOLE))

	for row in [
		# focused, booting, in_submenu, expected
		[true,  false, false, true],
		[false, false, false, false],
		[true,  true,  false, false],
		[true,  false, true,  false],
		[false, true,  true,  false],
	]:
		console.focused = row[0]
		console.booting = row[1]
		console.in_submenu = row[2]
		_check("focused=%s booting=%s submenu=%s -> %s" % [row[0], row[1], row[2], row[3]],
			console.in_section_nav == row[3])

	console.free()

	print("")
	if _checks < 5:
		print("FALLO: solo %d de 5 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - F solo puede verse navegando secciones")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if ok:
		print("  ok    %s" % label)
	else:
		_failures += 1
		print("  FALLO %s" % label)
