class_name ShopBindUi extends Label

## A Label whose text carries $action_name$ placeholders, each replaced with
## whatever is currently bound to that action. Resolution lives in
## LullabyInputBinds, which lullaby_gameover_prompt.gd shares.

@export_multiline() var format_text: String = "":
	get:
		return _text
	set(val):
		if _text == val:
			return

		_text = val
		_update_text(current_bind_type)

var current_bind_type: int = LullabyInputBinds.BindType.KBM

var _text: String = ""

func _ready() -> void :
	_update_text(current_bind_type)
	Settings.applied.connect(_on_settings_applied)

func _input(event: InputEvent) -> void :
	# -1 for events that say nothing about the device family (a synthetic
	# InputEventAction, a screen touch). Those must not flip the display
	# back to keyboard glyphs for a player holding a gamepad.
	var bind_type: int = LullabyInputBinds.type_of(event)
	if bind_type == -1 or bind_type == current_bind_type:
		return

	current_bind_type = bind_type
	_update_text(bind_type)

func _on_settings_applied() -> void :
	_update_text(current_bind_type)

func _update_text(bind_type: int) -> void :
	var current_text: String = format_text

	var split_text: PackedStringArray = current_text.split("$")
	var inputs: Array[StringName] = []
	for single_text: String in split_text:
		if LullabyInputBinds.has_action(single_text) and not inputs.has(single_text):
			inputs.append(single_text)

	for input: StringName in inputs:
		current_text = current_text.replace(
			"$" + input + "$", LullabyInputBinds.text_for(input, bind_type)
		)

	text = current_text
