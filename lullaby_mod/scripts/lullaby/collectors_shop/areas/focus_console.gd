extends SubmenuArea


@export var console: Console


## Drops Console.focused when the player looks somewhere else.
##
## The flag has exactly one other writer, Console.back_out(), and that can
## only ever run while this area is_focused - SubmenuArea._input() forwards
## input into the console's SubViewport under precisely that condition, and
## the viewport is rendered onto a 3D screen mesh, so it gets no window input
## of its own. Leave the console by focusing another area (the board, the
## plushes, the Unown list) and back_out() is unreachable, so the flag stayed
## true for the rest of the session.
##
## Two things broke on that, and both are in the device log 1a8527cd:
## CollectorShop._input() hands Back to the console whenever the flag is set,
## so the shop never zoomed out - forty consecutive presses at
## state=FOCUSED area=FocusBoard console_focused=true, none of them doing
## anything - and trigger() below early-returns on the same flag, so coming
## back to the console skipped the music fade and the Cartridges grab_focus.
func _focus_changed(focused: bool) -> void:
	if focused or console == null:
		return
	console.focused = false

func trigger() -> void :
	if not ShopConsolePower.on:
		return
	if not can_interact:
		return

	super ()

	if console.focused:
		return

	shop.stop_voiceline()

	console.focused = true
	console.other_sounds.volume_linear = 1.0
	console.music_fader.play(&"fade_in")

	var carts: Control = console.get_node_or_null(^"%Cartridges")
	if carts:
		carts.grab_focus.call_deferred()
