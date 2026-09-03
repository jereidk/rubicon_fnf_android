class_name MiscSubMenu
extends "res://animania_mod/menus/options/base_sub_menu.gd"
## Misc sub-menu — faithful port of animania::states::MiscSubMenu.
##
## Options: language, vsync, showHaxeFlixel, showDebugDisplay,
## game_volume, game_mute

const TITLE_PATH := "res://animania_mod/source/images/menus/options/eng/misc-title.png"


func create_title() -> void:
	_load_title_image(TITLE_PATH)


func create_pref_items() -> void:
	# Language (choice)
	var lang := OptionBoxChoice.new()
	lang.setup("language", "Language", ["en", "ru"], 0)
	add_option_item(lang)

	# VSync (choice)
	var vsync := OptionBoxChoice.new()
	vsync.setup("vsync", "VSync", ["Off", "Adaptive", "On"], 1)
	add_option_item(vsync)

	# Show HaxeFlixel intro (bool)
	var hxf := OptionBoxBool.new()
	hxf.setup("haxeflixel_intro", "HaxeFlixel Intro", true)
	add_option_item(hxf)

	# Show debug display (bool)
	var debug := OptionBoxBool.new()
	debug.setup("debug_display", "Debug Display", false)
	add_option_item(debug)

	# Game volume (slider 0.0 - 1.0, step 0.05)
	var vol := OptionBoxSlider.new()
	vol.setup("game_volume", "Game Volume", 0.0, 1.0, 0.05, 0.5)
	add_option_item(vol)

	# Game mute (bool)
	var mute := OptionBoxBool.new()
	mute.setup("game_mute", "Mute", false)
	add_option_item(mute)
