class_name LullabyFirstBootSettings extends Node

@export var focus_first: Control
@export var preset_description: Label

func _ready() -> void :
	_on_preset_changed(4)
	focus_first.grab_focus()

func _on_preset_changed(index: int) -> void :
	var text: String = "Whatever you want."
	match index:
		1:
			text = "As low as it gets [No shadows, 0.75x render scale, post-processing off, zero antialiasing]"
		2:
			text = "Bottom-of-the-barrel visuals [Post-proccesing off, zero antialiasing]"
		3:
			text = "For the average computer [Post-processing low, basic antilaliasing]"
		4:
			text = "The intended experience. [Post-processing and antialiasing at its max]"

	preset_description.text = text

func open_settings() -> void :
	Debugger.settings.open()

func apply_and_continue() -> void :
	SaveData.set_flag(&"first_boot_seen", true)
	SaveData.save()

	Settings.apply_settings()
	Settings.save()

	get_tree().change_scene_to_file("res://lullaby_mod/rooms/scn_boot.tscn")
