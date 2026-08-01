extends FocusArea3D

## FocusAreaRight (this node) zooms the camera into the TV on the first OK,
## same as any other FocusArea3D - that part is untouched, still handled by
## the base class's own trigger(). This just adds a second step: while
## already zoomed in here (is_focused - see CollectorShop.current_area's
## setter), a further OK should open the console directly, with no aiming
## required. The camera can't pan once FOCUSED (see mouse_controller.gd's
## _process(), gated to FREE_LOOK only), so a raycast-based second click
## could only ever reach whatever the zoom animation happened to center -
## fine for the screen itself, but there's no way to *also* reach a
## separate prop like the power console that way (see
## touch_aim_reticle.gd's own doc comment for the fuller story, and the
## dedicated Power button next to this one added for exactly that reason).
##
## Mirrors focus_chimera_photos.gd's own pattern (an is_focused-gated
## _input() on a sibling FocusArea3D), just reacting to the confirm action
## instead of ui_cancel.
@export var console_area: SubmenuArea

func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_pressed():
		return

	if not is_focused:
		return

	if not (event is InputEventAction or event is InputEventJoypadButton):
		return

	if not event.is_action(&"RightClick"):
		return

	if console_area == null:
		return

	console_area.can_interact = true
	console_area.area_triggered.emit()
	console_area.trigger()
