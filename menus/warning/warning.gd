extends Control

## Port of Lullaby's scn_warning.tscn. Two stages reusing the same panel:
## first a general content warning, then (on "Continue") a flashing-lights
## warning that lets the player opt out of flash effects.

const MAIN_MENU_SCENE := "res://menus/main/main_menu.tscn"

const CONTENT_WARNING_TEXT := "This game contains [color=9b0000]loud noises, jumpscares, covered partial
nudity, depictions of gore, body horror, and insects.[/color]

If you are sensitive to any of the above, do [color=red]not[/color]
play [color=9b0000]Friday Night Funkin' Lullaby.[/color] Wish to continue?"

const FLASH_WARNING_TEXT := "Furthermore, this mod contains [color=red]FLASHING LIGHTS. [/color]If you are sensitive
 to these, we recommend turning them off.

[color=red]Keep flashing lights on?[/color] This setting can be changed later in settings."

@onready var warning_text: RichTextLabel = %WarningText
@onready var no_button: Button = %NoButton
@onready var yes_button: Button = %YesButton
@onready var press_sound: AudioStreamPlayer = $AudioStreamPlayer
@onready var kill_sound: AudioStreamPlayer = $AudioStreamPlayer2

var _showing_flash_stage := false
var flashing_lights_enabled := true

func _on_no_button_button_down() -> void:
	if not _showing_flash_stage:
		kill_sound.play()
		await kill_sound.finished
		get_tree().quit()
		return

	press_sound.play()
	flashing_lights_enabled = false
	_continue_to_menu()

func _on_yes_button_button_down() -> void:
	press_sound.play()
	if not _showing_flash_stage:
		_show_flash_stage()
	else:
		flashing_lights_enabled = true
		_continue_to_menu()

func _show_flash_stage() -> void:
	_showing_flash_stage = true
	warning_text.text = FLASH_WARNING_TEXT
	no_button.text = "Keep off"
	yes_button.text = "Keep on"

func _continue_to_menu() -> void:
	SceneChanger.change_scene(MAIN_MENU_SCENE)
