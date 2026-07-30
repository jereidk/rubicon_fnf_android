extends Container

## Attach to the container wrapping a rebind Button. lane 0-3 rebinds a
## mania lane (Left/Down/Up/Right); lane -1 rebinds the "special" mechanic
## key instead.

@export var lane: int = -1
@export var button: Button

var _listening := false

func _ready() -> void:
	_refresh_label()
	button.pressed.connect(_on_button_pressed)
	if lane >= 0:
		Settings.key_binding_changed.connect(_on_key_binding_changed)
	else:
		Settings.special_binding_changed.connect(_on_special_binding_changed)

func _on_button_pressed() -> void:
	_listening = true
	button.text = "..."

func _input(event: InputEvent) -> void:
	if not _listening:
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		_listening = false
		if lane >= 0:
			Settings.set_key_binding(lane, event.keycode)
		else:
			Settings.set_special_binding(event.keycode)
		get_viewport().set_input_as_handled()

func _on_key_binding_changed(changed_lane: int, _keycode: Key) -> void:
	if changed_lane == lane:
		_refresh_label()

func _on_special_binding_changed(_keycode: Key) -> void:
	_refresh_label()

func _refresh_label() -> void:
	if lane >= 0:
		button.text = Settings.key_name(Settings.key_bindings[lane])
	else:
		button.text = Settings.key_name(Settings.special_binding)
