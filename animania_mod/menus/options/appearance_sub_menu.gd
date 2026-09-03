class_name AppearanceSubMenu
extends "res://animania_mod/menus/options/base_sub_menu.gd"
## Appearance sub-menu — faithful port of animania::states::AppearanceSubMenu.
##
## Options: hints, shaders, lowQuality, showJudges, showHealthbar,
## flashingLights, subtitles, zoomCamera, showNoteSplashes, showTimeBar,
## globalAntialiasing, framerate

const TITLE_PATH := "res://animania_mod/source/images/menus/options/eng/appearance-title.png"


func create_title() -> void:
	_load_title_image(TITLE_PATH)


func create_pref_items() -> void:
	# Hints (bool)
	var hints := OptionBoxBool.new()
	hints.setup("hints", "Hints", true)
	add_option_item(hints)

	# Shaders (bool)
	var shaders := OptionBoxBool.new()
	shaders.setup("allow_shaders", "Shaders", true)
	add_option_item(shaders)

	# Low quality (bool)
	var lowq := OptionBoxBool.new()
	lowq.setup("lowquality", "Low Quality", false)
	add_option_item(lowq)

	# Show judges (bool)
	var judges := OptionBoxBool.new()
	judges.setup("show_judges", "Show Judges", true)
	add_option_item(judges)

	# Show healthbar (bool)
	var health := OptionBoxBool.new()
	health.setup("show_healthbar", "Show Healthbar", true)
	add_option_item(health)

	# Flashing lights (bool)
	var flash := OptionBoxBool.new()
	flash.setup("flashing_lights", "Flashing Lights", true)
	add_option_item(flash)

	# Subtitles (bool)
	var subs := OptionBoxBool.new()
	subs.setup("subtitles", "Subtitles", false)
	add_option_item(subs)

	# Zoom camera (bool)
	var zoom := OptionBoxBool.new()
	zoom.setup("camera_zooming", "Camera Zooming", true)
	add_option_item(zoom)

	# Show note splashes (bool)
	var splashes := OptionBoxBool.new()
	splashes.setup("notesplashes", "Note Splashes", true)
	add_option_item(splashes)

	# Show time bar (bool)
	var timebar := OptionBoxBool.new()
	timebar.setup("timebar", "Show Time Bar", true)
	add_option_item(timebar)

	# Global antialiasing (bool)
	var aa := OptionBoxBool.new()
	aa.setup("antialiasing", "Antialiasing", true)
	add_option_item(aa)

	# Framerate (slider 30 - 240, step 10)
	var fps := OptionBoxSlider.new()
	fps.setup("framerate", "Framerate", 30, 240, 10, 60)
	add_option_item(fps)
