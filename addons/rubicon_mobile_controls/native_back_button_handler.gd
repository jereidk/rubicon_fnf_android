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
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return

	var press := InputEventAction.new()
	press.action = &"ui_cancel"
	press.pressed = true
	Input.parse_input_event(press)

	await get_tree().process_frame

	var release := InputEventAction.new()
	release.action = &"ui_cancel"
	release.pressed = false
	Input.parse_input_event(release)
