extends SceneTree

## Zooming back out has to leave the camera in no area at all.
##
## CollectorShop.current_area only ever changed when some other area took
## focus. Nothing cleared it on the way back to FREE_LOOK, so the last area the
## player entered kept is_focused true for the rest of the visit, and "the area
## the camera is in" quietly meant "the last area the camera was in".
##
## Two contextual buttons read that, and a device screenshot has both of them
## wrong while the player is walking the room: Power, gated on
## FocusAreaRight.is_focused, and F, gated on Console.in_section_nav, whose
## Console.focused is dropped by FocusArea3D.is_focused's setter calling
## _focus_changed(false) - the mechanism focus_console.gd already exists for,
## reached here from a different direction.
##
## Only FREE_LOOK clears it. BUSY is a menu open inside an area, and the
## console being open is not the camera having left it - that case is in here
## too, because getting it wrong would hide the console's own buttons.
##
## Run with:
##   godot --headless --path . --script tools/test_focus_clears_on_free_look.gd

const SHOP := "res://lullaby_mod/scripts/lullaby/collectors_shop/env_collector_shop.gd"
const AREA := "res://lullaby_mod/scripts/lullaby/collectors_shop/areas/focus_area.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var shop_script: GDScript = load(SHOP)
	var area_script: GDScript = load(AREA)

	var shop: Node = Node3D.new()
	shop.set_script(shop_script)
	root.add_child(shop)

	var area: Node = Area3D.new()
	area.set_script(area_script)
	root.add_child(area)

	shop_script.current_area = null
	shop_script.current_area = area
	_check("entrar en un area la marca enfocada", area.is_focused)

	# FOCUSED is the camera zoomed into that area: it must stay.
	shop.state = shop_script.ShopStates.FOCUSED
	_check("seguir enfocado no la desmarca", area.is_focused)
	_check("y el area sigue siendo la actual", shop_script.current_area == area)

	# BUSY is a menu open inside the area - the console, the briefcase. The
	# camera has not left, so neither has the focus.
	shop.state = shop_script.ShopStates.BUSY
	_check("abrir un menu tampoco la desmarca", area.is_focused,
		"BUSY es la consola abierta, no la camara fuera")

	# Back out to the room.
	shop.state = shop_script.ShopStates.FREE_LOOK
	_check("volver a free look la desmarca", not area.is_focused)
	_check("y deja de haber area actual", shop_script.current_area == null)

	# Re-entering works, so the clear is not a one-way door.
	shop_script.current_area = area
	_check("y se puede volver a entrar", area.is_focused)

	# The chain the F button hangs off: is_focused's setter calls
	# _focus_changed(false), and the console's own area uses that to drop
	# Console.focused. Subclassed here rather than loaded, because
	# focus_console.gd reaches for a shop, sequences and an animation player it
	# has no business needing for this one hook.
	var console_area_script := GDScript.new()
	console_area_script.source_code = """
extends FocusArea3D
var cleared: bool = false
func _focus_changed(focused: bool) -> void:
	if not focused:
		cleared = true
"""
	console_area_script.reload()
	var console_area: Node = Area3D.new()
	console_area.set_script(console_area_script)
	root.add_child(console_area)

	shop_script.current_area = console_area
	_check("la consola toma el foco", console_area.is_focused)
	_check("y no lo ha soltado todavia", not console_area.cleared)

	shop.state = shop_script.ShopStates.FREE_LOOK
	_check("free look avisa al area de que la han dejado", console_area.cleared,
		"_focus_changed(false) es lo que limpia Console.focused")

	shop_script.current_area = null
	area.queue_free()
	console_area.queue_free()
	shop.queue_free()
	await process_frame

	print("")
	if _checks < 10:
		print("FALLO: solo %d de 10 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - salir de un area la deja sin foco")
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
