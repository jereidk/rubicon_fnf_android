extends Control
## HQ Setup — first-time setup flow with multi-step message windows.
## Ports the mod's HQSetup. Key rebinding prompt is included as a
## visual placeholder; actual rebinding is skipped on Android.

var _step: int = 0
var _message_win: Control
var _intro_scene := "res://holyquintet_mod/menus/intro/intro_screen.tscn"
var _msg_scene: PackedScene = preload("res://holyquintet_mod/ui/hq_message_window.tscn")

func _ready() -> void:
	if HQSaves.first_time_setup_done and not HQSaves.see_intro:
		get_tree().change_scene_to_file("res://holyquintet_mod/menus/disclaimer/disclaimer.tscn")
		return
	if HQSaves.first_time_setup_done and HQSaves.see_intro:
		get_tree().change_scene_to_file(_intro_scene)
		return
	_next_step.call_deferred()

func _next_step() -> void:
	_step += 1
	match _step:
		1:
			_show_msg("First-Time Setup",
				"Would you like to do the first time setup?",
				"Skip", "Yes", "warning",
				func(): _skip_to_downscroll(),
				func(): pass)
		2:
			_show_msg("Flashing Lights",
				"Would you like to keep flashing lights enabled?",
				"No", "Yes", "danger",
				func(): pass,
				func(): pass)
		3:
			_show_msg("Control Scheme",
				"Would you like to rebind your controls?\n(Default on Android)",
				"No", "Yes", "warning",
				func(): _skip_to_downscroll(),
				func(): _skip_to_downscroll())
		4:
			_show_msg("Downscroll Preference",
				"Would you like upscroll or downscroll?",
				"Upscroll", "Downscroll", "warning",
				func(): pass,
				func(): pass)

func _show_msg(title: String, body: String, left: String, right: String,
				icon: String, on_left: Callable, on_right: Callable) -> void:
	_message_win = _msg_scene.instantiate()
	_message_win.title_text = title
	_message_win.body_text = body
	_message_win.left_text = left
	_message_win.right_text = right
	_message_win.icon_name = icon
	_message_win.on_left = on_left
	_message_win.on_right = on_right
	_message_win.on_complete = _on_msg_done
	add_child(_message_win)

func _on_msg_done() -> void:
	_message_win = null
	if _step >= 4:
		_finish()
	else:
		_next_step.call_deferred()

func _skip_to_downscroll() -> void:
	_step = 3
	_next_step()

func _finish() -> void:
	HQSaves.first_time_setup_done = true
	HQSaves.save_data()
	get_tree().change_scene_to_file(_intro_scene)
