class_name ExperementalSubMenu
extends "res://animania_mod/menus/options/base_sub_menu.gd"
## Experimental sub-menu — faithful port of animania::states::ExperementalSubMenu.
## (Typo in name preserved from the binary.)
##
## Options: naughtyness, cacheOnGPU

const TITLE_PATH := "res://animania_mod/source/images/menus/options/eng/experemental-title.png"


func create_title() -> void:
	_load_title_image(TITLE_PATH)


func create_pref_items() -> void:
	# Naughtyness (bool)
	var naughty := OptionBoxBool.new()
	naughty.setup("naughtyness", "Naughtyness", false)
	add_option_item(naughty)

	# Cache on GPU (bool)
	var gpu := OptionBoxBool.new()
	gpu.setup("gpu_load", "Cache on GPU", false)
	add_option_item(gpu)
