class_name FocusArea3D extends TriggerArea3D

@export var shop: CollectorShop
@export var sequences: ShopSequences
@export var animation_name: StringName

## Set by CollectorShop.current_area's setter - true on the area the camera
## is currently zoomed into, false on the one it just left.
##
## Has a setter now because losing focus is the only signal an area gets
## that the player has looked away, and the console needs it: Console.focused
## was only ever cleared by Console.back_out(), which can only run while
## SubmenuArea._input() is forwarding input into the console's SubViewport,
## which it only does while this is true. Look at the board instead and the
## flag stayed true with nothing left able to clear it. See
## focus_console.gd's own _focus_changed().
var is_focused: bool = false:
	set(value):
		if value == is_focused:
			return
		is_focused = value
		_focus_changed(value)

## Called when this area gains or loses the camera. Nothing here by design -
## subclasses that keep state of their own outside is_focused override it.
func _focus_changed(_focused: bool) -> void:
	pass

func trigger() -> void :
	if not can_interact:
		return
	sequences.animation_player.play(animation_name)
	sequences.animation_player.seek(0.0, true)



func register_trigger() -> void :
	if not can_interact:
		return
	super ()

	CollectorShop.current_area = self
