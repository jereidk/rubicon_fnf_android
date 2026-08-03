extends Control
## Placeholder: Rubicon doesn't have a settings system yet (no volume/keybind/etc.
## resource to edit). This just gives the "OPTIONS" main menu entry somewhere to go
## instead of doing nothing, until a real options system exists.

const MAIN_MENU_SCENE := "res://menus/main_menu/main_menu.tscn"

@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	back_button.grab_focus()
