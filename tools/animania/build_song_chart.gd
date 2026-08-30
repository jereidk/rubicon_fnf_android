# Converts any V-Slice chart to Rubicon's, headlessly.
#
#   godot --headless --path . --script tools/animania/build_song_chart.gd -- <song id>
#
# The rubichart_converter addon drives this from an editor popup, but the converter is a
# static function on a plain script, so it runs fine from a --script run - the same shape
# build_sparrow_character.gd uses to reach the sprite importer's own RefCounted.
#
# It writes <song>-<difficulty>_{Player,Opponent}.tres and Meta.tres beside the chart, one
# pair per difficulty key in `notes`.
extends SceneTree

const VSlice := preload("res://addons/rubichart_converter/converters/vslice.gd")


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: <song id>")
		quit(1)
		return
	var song: String = args[0]
	var dir: String = "res://animania_mod/source/songs/%s" % song

	VSlice.convert_chart([
		"%s/%s-chart.json" % [dir, song], "%s/%s-metadata.json" % [dir, song],
	] as Array[String])

	for name: String in DirAccess.get_files_at(dir):
		if name.ends_with(".tres"):
			print("OUT %s/%s" % [dir, name])
	quit(0)
