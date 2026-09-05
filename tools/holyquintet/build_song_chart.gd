# Converts every Holy Quintet codename chart to Rubicon's format, headlessly.
#
#   godot --headless --path . --script tools/holyquintet/build_song_chart.gd -- <song id>
#
# Reads holyquintet_mod/source/songs/<song>/charts/<difficulty>.json + meta.json, runs
# the codename converter, then moves its outputs into songs/<song>/data/ under the names
# the level scene expects (<song>-<diff>_Player.tres / _Opponent.tres / Meta.tres).
#
# The codename converter saves one .tres per strumline using its POSITION name
# (dad/boyfriend/gf). Rubicon lanes are single-side, so we map dad -> Opponent and
# boyfriend -> Player. A side with several strumlines (partea's chorus, meguca's dual
# player) keeps its first chart here; the extras are preserved beside it for later.
extends SceneTree

const Codename := preload("res://addons/rubichart_converter/converters/codename.gd")

const SIDE_MAP := {
	"dad": "Opponent",
	"boyfriend": "Player",
}


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: <song id>")
		quit(1)
		return
	var song := args[0]
	var source_dir := "res://holyquintet_mod/source/songs/%s" % song
	var out_dir := "res://songs/%s/data" % song

	var meta_parse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/meta.json" % source_dir))
	var difficulties: Array = meta_parse.get("difficulties", ["hard"])
	if difficulties.is_empty():
		difficulties = ["hard"]

	for diff: String in difficulties:
		var chart_path := "%s/charts/%s.json" % [source_dir, diff]
		if not FileAccess.file_exists(chart_path):
			push_warning("no chart for %s/%s" % [song, diff])
			continue
		Codename.convert_chart([chart_path, "%s/meta.json" % source_dir] as Array[String])

		var chart_parse: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chart_path))
		var seen: Dictionary = {}
		for strumline: Dictionary in chart_parse["strumLines"]:
			var position: String = strumline["position"]
			if not SIDE_MAP.has(position):
				push_warning("%s/%s: strumline position '%s' has no lane side, skipping" % [song, diff, position])
				continue
			var side: String = SIDE_MAP[position]
			var idx: int = seen.get(side, 0)
			seen[side] = idx + 1
			var src := "%s/charts/%s_%s.tres" % [source_dir, diff, position]
			var dst := "%s/%s-%s_%s.tres" % [out_dir, song, diff, side]
			if idx > 0:
				dst = "%s/%s-%s_%s_%d.tres" % [out_dir, song, diff, side, idx]
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst)) != OK:
				push_error("copy failed %s -> %s" % [src, dst])
				quit(1)
			print("OUT %s" % dst)

		var meta_src := "%s/charts/meta.tres" % source_dir
		var meta_dst := "%s/Meta.tres" % out_dir
		DirAccess.make_dir_recursive_absolute(meta_dst.get_base_dir())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(meta_src), ProjectSettings.globalize_path(meta_dst))
		print("OUT %s" % meta_dst)

	quit(0)
