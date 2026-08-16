extends SceneTree

## Two menus want the D-pad vertical-only, and either one is enough.
##
## The SHOP/TALK sign had the single slot from the start. The notepad reads
## ui_up, ui_down and ui_accept and nothing else (prp_notepad.gd), so its two
## horizontal arrows have never done anything - and with the arms now hidden
## rather than dimmed, that is the difference between a pad with two arrows
## and a pad with four, two of which are lies.
##
## The trap is the empty slot. A slot that names no node has to mean "no
## opinion", not "false": read as false it would pin the pad to ALL_ZONES on
## every frame and the sign would lose its own restriction, which is how a
## second OR'd slot breaks the first one.
##
## Run with:
##   godot --headless --path . --script tools/test_vertical_only_slots.gd

const OVERLAY := "res://addons/rubicon_mobile_controls/menu_touch_controls.gd"
const DPAD := "res://addons/rubicon_mobile_controls/virtual_dpad.gd"
const SHOP_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var flags := GDScript.new()
	flags.source_code = "extends Node\nvar state: int = 1\nvar flag: bool = false\n"
	flags.reload()

	var overlay: Control = Control.new()
	overlay.set_script(load(OVERLAY))
	var dpad: Control = Control.new()
	dpad.set_script(load(DPAD))
	overlay.add_child(dpad)
	overlay.dpad = dpad

	var sign_double: Node = Node.new()
	sign_double.set_script(flags)
	var notepad_double: Node = Node.new()
	notepad_double.set_script(flags)
	overlay.add_child(sign_double)
	overlay.add_child(notepad_double)

	# active_source has to be something, or _process turns itself off before
	# reaching any of this.
	overlay.active_source = sign_double
	overlay.active_property = &"state"

	# No slot configured at all: the pad keeps whatever it had. Set to
	# something neither branch would produce, so "left alone" is provable.
	dpad.enabled_zones = _zones([1])
	overlay._process(0.0)
	_check("sin slots configurados no toca las zonas",
		dpad.enabled_zones == _zones([1]), str(dpad.enabled_zones))

	overlay.vertical_only_source = sign_double
	overlay.vertical_only_property = &"flag"

	overlay._process(0.0)
	_check("un slot en falso deja las cuatro",
		dpad.enabled_zones == RubiconVirtualDPad.ALL_ZONES, str(dpad.enabled_zones))

	sign_double.flag = true
	overlay._process(0.0)
	_check("el cartel solo deja arriba y abajo",
		dpad.enabled_zones == RubiconVirtualDPad.VERTICAL_ZONES, str(dpad.enabled_zones))

	# The second slot alone, with the first false - the case that breaks if an
	# unconfigured or false slot is allowed to overrule a true one.
	sign_double.flag = false
	overlay.vertical_only_source2 = notepad_double
	overlay.vertical_only_property2 = &"flag"
	notepad_double.flag = true
	overlay._process(0.0)
	_check("la libreta sola tambien",
		dpad.enabled_zones == RubiconVirtualDPad.VERTICAL_ZONES, str(dpad.enabled_zones))

	notepad_double.flag = false
	overlay._process(0.0)
	_check("con los dos en falso vuelven las cuatro",
		dpad.enabled_zones == RubiconVirtualDPad.ALL_ZONES, str(dpad.enabled_zones))

	# Only the second slot configured, the first left empty. Same answer.
	overlay.vertical_only_source = null
	overlay.vertical_only_property = &""
	notepad_double.flag = true
	overlay._process(0.0)
	_check("un primer slot vacio no anula al segundo",
		dpad.enabled_zones == RubiconVirtualDPad.VERTICAL_ZONES, str(dpad.enabled_zones))

	overlay.free()

	_scene_check()

	print("")
	if _checks < 9:
		print("FALLO: solo %d de 9 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - las direcciones muertas no se dibujan")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## A Node-typed @export filled from a scene only resolves if the property is
## named in the node header's node_paths list. Left out, Godot stores a bare
## NodePath the script never reads, and the slot silently does nothing - which
## looks exactly like the feature not being wired at all.
func _scene_check() -> void:
	var text: String = FileAccess.get_file_as_string(SHOP_SCENE)
	_check("la escena declara vertical_only_source2 en node_paths",
		text.contains('"vertical_only_source", "vertical_only_source2"'))
	_check("y lo apunta a la libreta",
		text.contains('vertical_only_source2 = NodePath("../../../Notepad")'))
	_check("por su visibilidad", text.contains('vertical_only_property2 = &"visible"'))

func _zones(values: Array) -> Array[int]:
	var typed: Array[int] = []
	for value in values:
		typed.append(int(value))
	return typed

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
