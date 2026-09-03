# Generates animania_mod/menus/story/story_menu.tscn from level JSON data.
#
#   godot --headless --path . --script tools/animania/build_story_menu.gd

extends SceneTree

const OUT := "res://animania_mod/menus/story/story_menu.tscn"
const ART := "res://animania_mod/source/images/storymenu"
const LEVELS := "res://animania_mod/source/data/levels"
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const TITLE_CENTRE := Vector2(400.0, 540.0)
const TITLE_SPACING := 180.0


func _init() -> void:
	var existing := load(OUT) as PackedScene
	if existing == null:
		print("ERROR: Cannot load %s" % OUT)
		quit(1)
		return

	var instance := existing.instantiate()
	var titles_container: Node2D = instance.get_node("Titles")
	if titles_container == null:
		print("ERROR: No Titles node")
		quit(1)
		return

	for child: Node in titles_container.get_children():
		child.queue_free()

	var names: PackedStringArray = DirAccess.get_files_at(LEVELS)
	names.sort()
	var shown: int = 0
	for file_name: String in names:
		if not file_name.ends_with(".json"):
			continue
		var raw: String = FileAccess.get_file_as_string("%s/%s" % [LEVELS, file_name])
		var level: Dictionary = JSON.parse_string(raw)
		if level.get("visible", true) == false:
			continue

		var title_asset: String = String(level.get("titleAsset", ""))
		var asset_path: String = "%s/titles/%s.png" % [ART, title_asset.get_file()]
		if not ResourceLoader.exists(asset_path):
			print("OUT %-24s no art" % file_name)
			continue

		var title := Sprite2D.new()
		title.name = title_asset.get_file().to_pascal_case()
		title.texture = load(asset_path)
		title.centered = true
		title.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		var size: Vector2 = title.texture.get_size() * FUNKIN_TO_RUBICON
		title.set_meta(&"hitbox", Rect2(-size * 0.5, size))
		title.set_meta(&"name", String(level.get("name", "")))
		title.set_meta(&"level_id", file_name.get_basename())
		title.set_meta(&"background", String(level.get("background", "#0F0D1A")))
		title.set_meta(&"force_freeplay_visible", bool(level.get("forceFreeplayVisible", false)))
		title.set_meta(&"props_data", level.get("props", []))

		var songs: PackedStringArray = []
		for song: String in (level.get("songs", []) as Array):
			songs.append(song)
		title.set_meta(&"songs", songs)
		titles_container.add_child(title)
		title.owner = instance
		shown += 1
		print("OUT %-24s %-24s %s" % [file_name, level.get("name", ""), songs])

	var packed := PackedScene.new()
	packed.pack(instance)
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %d weeks, %s %s" % [shown, "saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)
