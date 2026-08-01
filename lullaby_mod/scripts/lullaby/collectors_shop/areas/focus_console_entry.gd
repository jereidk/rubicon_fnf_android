class_name FocusConsoleEntry
extends FocusArea3D

## FocusAreaRight (this node, "focus_right" animation) zooms the camera
## into the TV, same as the book/shop-front/exit triggers do for their own
## areas - but unlike those, the console is rendered in a SubViewport that
## only ever receives input via SubmenuArea's own _input() forwarding
## (focus_submenu.gd), gated on *console_area's* is_focused, and its
## focus_console.gd override needs its own trigger() to run too (grabs GUI
## focus on the Home tab's default icon, sets Console.focused - see
## env_collector_shop.gd's own ui_cancel gate on that same flag). Nothing
## ever activated console_area on entry, so the TV powered on and was
## reachable by camera but stayed completely unresponsive to the dpad/OK -
## the player's only option was backing back out.
##
## Mirrors exactly what MouseController._input() does for whatever it
## directly raycasts onto (area_triggered.emit() then trigger()), just
## chained onto this node's own trigger() instead of a second player tap.
@export var console_area: SubmenuArea

func trigger() -> void:
	super()

	if console_area == null:
		return

	console_area.can_interact = true
	console_area.area_triggered.emit()
	console_area.trigger()
