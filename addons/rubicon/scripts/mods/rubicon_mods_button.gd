extends CanvasLayer
## Always-on-top "Mods" text entry point, auto-added by the Mods autoload since Rubicon
## doesn't have a main menu yet to host it in. Once a real game-specific menu exists,
## call Mods.set_entry_button_visible(false) and add your own button that calls
## Mods.open_menu() instead.

@onready var button: Button = %ModsButton

func _ready() -> void:
	button.pressed.connect(Mods.open_menu)
