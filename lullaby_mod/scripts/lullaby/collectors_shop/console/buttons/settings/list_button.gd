class_name ListButton extends SettingsButton

@export var property: StringName
@export var display_list: Array[String]
@export var values_list: Array

var index: int
var initial_text: String

func _ready() -> void :
	super._ready()
	index = values_list.find(Settings.get(property))
	initial_text = text
	text = initial_text + str(display_list[index])

func _input(event: InputEvent) -> void :
	var direction: int = 0
	if self.has_focus():
		if event.is_action("ui_right") and not event.is_action_released("ui_right"):
			direction = 1
		elif event.is_action("ui_left") and not event.is_action_released("ui_left"):
			direction = -1

	# Rubicon addition: the real mod only let you change this via keyboard/
	# joypad ui_left/ui_right while focused, leaving it dead on touch. A tap
	# on the left/right half of the button steps the value the same way.
	if direction == 0:
		direction = SettingsButton.get_tap_direction(self, event)

	if direction > 0:
		if index + 1 < values_list.size():
			console.play_sound.emit("sfx_soulroom_click")
			index += 1
			Settings.set(property, values_list[index])
			Settings.apply_settings()
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
			Settings.set(property, values_list[index])
			Settings.apply_settings()
			text = initial_text + str(display_list[index])
			if tween:
				tween.kill()
			tween = create_tween()
			tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_CUBIC)
		else:
			console.play_sound.emit("sfx_soulroom_deny")
