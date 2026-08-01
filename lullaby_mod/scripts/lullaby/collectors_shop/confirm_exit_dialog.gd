class_name ConfirmExitDialog
extends CanvasLayer

## Confirmation popup for trigger_exit.gd's shop-exit trigger - walking up
## and interacting with the shop's exit used to immediately kick off the
## leaving sequence with no way back if it was an accidental tap.

signal confirmed
signal cancelled

@export var yes_button: Button
@export var no_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	yes_button.pressed.connect(_on_yes_pressed)
	no_button.pressed.connect(_on_no_pressed)
	no_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_no_pressed()

func _on_yes_pressed() -> void:
	confirmed.emit()
	queue_free()

func _on_no_pressed() -> void:
	cancelled.emit()
	queue_free()
