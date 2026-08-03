extends Control

const TEST_SONG_SCENE := "res://songs/test/test.tscn"
const OPTIONS_SCENE := "res://menus/options/options_menu.tscn"

@onready var test_button: Button = %TestButton
@onready var mods_button: Button = %ModsButton
@onready var options_button: Button = %OptionsButton
@onready var exit_button: Button = %ExitButton

func _ready() -> void:
	test_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(TEST_SONG_SCENE))
	mods_button.pressed.connect(Mods.open_menu)
	options_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(OPTIONS_SCENE))
	exit_button.pressed.connect(get_tree().quit)

	test_button.grab_focus()

	# This screen has its own "MODS" entry, so the always-on-top corner button (the
	# Mods autoload's stand-in for when there's no main menu) would be redundant here.
	Mods.set_entry_button_visible(false)

func _exit_tree() -> void:
	Mods.set_entry_button_visible(true)
