extends Node

## Live show/hide for the Mobile settings tab.
##
## "Gameplay Control" picks between the Hitbox options and the Touch
## options; the losing group disappears the moment the value changes. Same
## pattern as quality_preset_button.gd going "Custom" when any sibling
## option moves: everything watches Settings.applied, which every settings
## row emits after apply_settings().
##
## The two groups sit in nested VBoxContainers so the script only toggles
## one Control per mode, and it also re-points the focus chain across the
## boundary - otherwise keyboard/gamepad navigation dead-ends against the
## hidden group (Godot will not jump over an unfocusable neighbour).

@export var game_control: Control
@export var hitbox_options: Control
@export var touch_options: Control
@export var first_hitbox: Control
@export var last_hitbox: Control
@export var first_touch: Control
@export var last_touch: Control
@export var note_layout: Control

func _ready() -> void:
	Settings.applied.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var touch: bool = Settings.lullaby_mobile_control_mode == Settings.MobileControlMode.TOUCH
	hitbox_options.visible = not touch
	touch_options.visible = touch

	var first: NodePath = first_touch.get_path() if touch else first_hitbox.get_path()
	var last: NodePath = last_touch.get_path() if touch else last_hitbox.get_path()
	game_control.focus_neighbor_bottom = first
	note_layout.focus_neighbor_top = last
	last_hitbox.focus_neighbor_bottom = note_layout.get_path()
	last_touch.focus_neighbor_bottom = note_layout.get_path()
