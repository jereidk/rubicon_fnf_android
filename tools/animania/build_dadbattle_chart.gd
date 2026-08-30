# Converts Dadbattle's V-Slice chart to Rubicon's, headlessly.
#
#   godot --headless --path . --script tools/animania/build_dadbattle_chart.gd
#
# The rubichart_converter addon drives this from an editor popup, but the converter itself
# is a static function on a plain script, so it runs fine from a --script run - the same
# shape as build_sparrow_character.gd going through the sprite importer's own RefCounted.
#
# It writes <song>_Player.tres, <song>_Opponent.tres and Meta.tres beside the chart, one
# pair per difficulty key in `notes`. Dadbattle has three (easy, normal, hard) where
# phone-call had one, so this is the first chart that exercises that.
extends SceneTree

const VSlice := preload("res://addons/rubichart_converter/converters/vslice.gd")
const DIR := "res://animania_mod/source/songs/dadbattle"


func _init() -> void:
	VSlice.convert_chart([
		"%s/dadbattle-chart.json" % DIR, "%s/dadbattle-metadata.json" % DIR,
	] as Array[String])

	for name: String in DirAccess.get_files_at(DIR):
		if name.ends_with(".tres"):
			print("OUT %s/%s" % [DIR, name])
	quit(0)
