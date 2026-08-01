extends SettingsButton

@export var display_list: Array[String]
@export var values_list: Array

var index: int
var initial_text: String

## display_list/values_list are wired in the .tscn as ["Very Low", "Low",
## "Medium", "High"] / [0, 1, 2, 3] - index order runs weakest to strongest,
## matching the preset match blocks below.
func _ready() -> void :
	super._ready()
	initial_text = text
	if Settings.get_quality_preset():
		match Settings.get_quality_preset():
			Settings.PRESET_VERY_LOW:
				index = 0
			Settings.PRESET_LOW:
				index = 1
			Settings.PRESET_MEDIUM:
				index = 2
			Settings.PRESET_HIGH:
				index = 3
		text = initial_text + str(display_list[index])
	else:
		index = -1
		text = initial_text + "Custom"

func _input(event: InputEvent) -> void :
	var direction: int = 0
	if self.has_focus():
		if event.is_action("ui_right") and not event.is_action_released("ui_right"):
			direction = 1
		elif event.is_action("ui_left") and not event.is_action_released("ui_left"):
			direction = -1

	# Rubicon addition: see SettingsButton.get_tap_direction.
	if direction == 0:
		direction = SettingsButton.get_tap_direction(self, event)

	if direction > 0:
		if index + 1 < values_list.size():
			console.play_sound.emit("sfx_soulroom_click")
			index += 1
			_apply_preset_for_index()
			text = initial_text + str(display_list[index])
			if tween:
				tween.kill()
			tween = create_tween()
			tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_CUBIC)
		else:
			console.play_sound.emit("sfx_soulroom_deny")
	elif direction < 0:
		if index - 1 >= 0:
			console.play_sound.emit("sfx_soulroom_click")
			index -= 1
			_apply_preset_for_index()
			text = initial_text + str(display_list[index])
			if tween:
				tween.kill()
			tween = create_tween()
			tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_CUBIC)
		else:
			console.play_sound.emit("sfx_soulroom_deny")

func _apply_preset_for_index() -> void :
	match index:
		0:
			Settings.PRESET_VERY_LOW.apply(Settings)
		1:
			Settings.PRESET_LOW.apply(Settings)
		2:
			Settings.PRESET_MEDIUM.apply(Settings)
		3:
			Settings.PRESET_HIGH.apply(Settings)

	# Sibling settings buttons (toggle_button.gd, incremental_button.gd,
	# list_button.gd, input_button.gd) all apply live on change - this one
	# only wrote into the Settings singleton's vars, leaving the actual
	# render_scale/shadow/AA effect invisible until the player happened to
	# back all the way out of the Settings submenu (console.gd's
	# back_out(), the only other apply_settings() caller here).
	Settings.apply_settings()
