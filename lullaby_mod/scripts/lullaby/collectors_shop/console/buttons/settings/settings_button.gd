extends Button
class_name SettingsButton

@export var console: Control
@export_multiline() var tooltip: String
var tooltip_node: Label
var tween: Tween

func _ready() -> void :
	tooltip_node = %Tooltip
	pivot_offset_ratio.y = 0.5
	self.focus_entered.connect(_on_focus_entered)
	self.focus_exited.connect(_on_focus_exited)
	self.pressed.connect(_on_button_pressed)

func _on_focus_entered():
	tooltip_node.text = tooltip
	console.play_sound.emit("sfx_soulroom_click")
	modulate = Color.YELLOW
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.25).set_trans(Tween.TRANS_CUBIC)

func _on_focus_exited():
	modulate = Color.WHITE
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_CUBIC)

func _on_button_pressed():
	pass

## Rubicon addition: several settings rows (list_button.gd,
## incremental_button.gd) only ever responded to ui_left/ui_right while
## keyboard-focused, so a touch-only player had no way to change them.
## Tapping the left/right half of the row steps the value the same
## direction a keyboard press would, without needing focus first.
## Returns -1/1 for a tap on the left/right half, 0 if the event isn't a
## relevant tap on this button.
static func get_tap_direction(button: Control, event: InputEvent) -> int:
	var pos: Vector2
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	else:
		return 0

	var rect: Rect2 = button.get_global_rect()
	if not rect.has_point(pos):
		return 0

	return -1 if pos.x < rect.position.x + rect.size.x * 0.5 else 1
