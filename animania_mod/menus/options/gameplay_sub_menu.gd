class_name GameplaySubMenu
extends "res://animania_mod/menus/options/base_sub_menu.gd"
## Gameplay sub-menu — faithful port of animania::states::GameplaySubMenu.
##
## Options: generalScrollSpeed, cameraShake, downScroll, autoPause,
## open_controls, missSounds, hitSound

const TITLE_PATH := "res://animania_mod/source/images/menus/options/eng/gameplay-title.png"


func create_title() -> void:
	_load_title_image(TITLE_PATH)


func create_pref_items() -> void:
	# Scroll speed (slider 0.25 - 4.0, step 0.25)
	var speed := OptionBoxSlider.new()
	speed.setup("general_note_speed", "Scroll Speed", 0.25, 4.0, 0.25, 1.0)
	add_option_item(speed)

	# Camera shake (bool)
	var shake := OptionBoxBool.new()
	shake.setup("camera_shake", "Camera Shake", true)
	add_option_item(shake)

	# Downscroll (bool)
	var down := OptionBoxBool.new()
	down.setup("downscroll", "Downscroll", false)
	add_option_item(down)

	# Auto pause (bool)
	var auto := OptionBoxBool.new()
	auto.setup("autopause", "Auto Pause", false)
	add_option_item(auto)

	# Open controls (bool)
	var ctrl := OptionBoxBool.new()
	ctrl.setup("open_controls", "Open Controls", false)
	add_option_item(ctrl)

	# Miss sounds volume (slider 0.0 - 1.0, step 0.05)
	var miss := OptionBoxSlider.new()
	miss.setup("miss_sounds_volume", "Miss Sounds", 0.0, 1.0, 0.05, 0.5)
	add_option_item(miss)

	# Hit sounds volume (slider 0.0 - 1.0, step 0.05)
	var hit := OptionBoxSlider.new()
	hit.setup("hit_sounds_volume", "Hit Sounds", 0.0, 1.0, 0.05, 0.5)
	add_option_item(hit)
