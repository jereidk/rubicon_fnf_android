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
			# HQSetup.hx case 1 (Message/Header/FirstTimeSetup, Message/FirstTimeSetup).
			# Real leftAction sets step=4 THEN calls progressSetup() (step+=1=5),
			# landing straight on case 5 (finish) — "No" skips flashing lights,
			# control scheme AND downscroll entirely, not just the first two.
			_show_msg("Setup Settings?",
				"This looks like your first time opening the mod.\nQuickly setup important settings?",
				"No", "Yes", "warning",
				func(): _step = 4,  # _on_msg_done sees _step >= 4 and finishes right away
				func(): pass)       # rightAction: progressSetup() (step 2)
		2:
			# HQSetup.hx case 2 (Message/Header/KeepFlashingLights, Message/KeepFlashingLights)
			_show_msg("Keep Flashing Lights?",
				"Some scenes has flashing lights, which may be uncomfortable for people with epilepsy.\nKEEP the flashing lights?",
				"No", "Yes", "danger",
				func(): ProjectSettings.set_setting("application/run/flashing", false),
				func(): ProjectSettings.set_setting("application/run/flashing", true))
		3:
			# HQSetup.hx case 3 (Message/Header/SetControlScheme, Message/SetControlScheme).
			# Both real branches just call progressSetup() once (step 3->4, same
			# as any other step) after their side effect: leftAction sets
			# Options.flashingLights = true (a copy-paste bug from case 2 — control
			# scheme has nothing to do with flashing lights — deliberately NOT
			# reproduced), rightAction opens promptKeyChange(0), a 4-step "press
			# any key to rebind <note>" flow for a physical keyboard that isn't
			# applicable to Android's touch controls. Neither needs a skip helper:
			# _on_msg_done's normal advance already takes 3 -> 4.
			_show_msg("Set Control Scheme",
				"Set up your control scheme?",
				"No", "Yes", "warning",
				func(): pass,
				func(): pass)
		4:
			# HQSetup.hx case 4 (Message/Header/DownscrollPreference, Message/DownscrollPreference)
			_show_msg("Note Scroll Option",
				"Which scroll direction would you like to use?",
				"Upscroll", "Downscroll", "warning",
				func(): ProjectSettings.set_setting("application/run/downscroll", false),
				func(): ProjectSettings.set_setting("application/run/downscroll", true))

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

func _finish() -> void:
	HQSaves.first_time_setup_done = true
	HQSaves.save_data()
	get_tree().change_scene_to_file(_intro_scene)
