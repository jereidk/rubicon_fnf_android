extends Node

## Android's hardware/gesture Back button normally force-quits the app
## outright via Godot's own quit_on_go_back project setting (disabled in
## project.godot specifically so this script can intercept it instead).
## With that setting off, Godot sends NOTIFICATION_WM_GO_BACK_REQUEST
## instead of quitting - this notification reaches every node in the tree,
## same as NOTIFICATION_WM_CLOSE_REQUEST does for
## trigger_exit.gd's own (unrelated, desktop-window-close) handling.
##
## Dispatches the same press+release pair RubiconActionButton uses for the
## on-screen Back button (see action_button.gd's _dispatch(), and
## menu_touch_controls.tscn's CancelButton which sets action=&"ui_cancel"),
## so every existing ui_cancel listener across the game reacts exactly like
## a real Back button tap - closing the current menu/submenu instead of
## killing the app.
##
## Also dispatches funkin_pause, the action the three song pause menus
## (kalos_pause_menu.gd, gb_pause_menu.gd, chimera_pause_menu.gd) listen
## for directly - there's no touch/ui_cancel path into pausing a song
## otherwise. Harmless everywhere else: nothing outside an active song
## scene has a funkin_pause listener, so it's a silent no-op there, same
## as ui_cancel already is outside a menu/submenu.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return

	_dispatch(&"ui_cancel")
	_dispatch(&"funkin_pause")

func _dispatch(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)

	await get_tree().process_frame

	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
