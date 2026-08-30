# Authors animania_mod/menus/story/story_menu.tscn.
#
#   godot --headless --path . --script tools/animania/build_story_menu.gd
#
# The week list is not written here: it is read from animania_mod/source/data/levels/*.json,
# which are the mod's own level files, vendored. Each gives `name`, `titleAsset`, `songs`
# and `visible`, and `visible: false` keeps a week off the screen - Animania hides
# `KomiCantCommunicate`, and that is respected rather than worked around.
#
# StoryMenu itself is compiled and its layout was NOT recovered, so where the titles sit is
# placed rather than read. It is the classic Funkin shape: the chosen week in the middle and
# the rest above and below.
extends SceneTree

const OUT := "res://animania_mod/menus/story/story_menu.tscn"
const ART := "res://animania_mod/source/images/storymenu"
const LEVELS := "res://animania_mod/source/data/levels"
const SCREEN := Vector2(1920.0, 1080.0)
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

var _root: Node2D


func _init() -> void:
	_root = Node2D.new()
	_root.name = "StoryMenu"
	_root.set_script(load("res://animania_mod/menus/story/story_menu.gd"))

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = SCREEN * 0.5
	_add(camera)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.06, 0.05, 0.10, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(backdrop)
	backdrop.set(&"layout_mode", 0)
	backdrop.size = SCREEN

	var titles := Node2D.new()
	titles.name = "Titles"
	_add(titles)

	# Sorted by file name so the order is stable between runs; the mod's own order is a
	# property of StoryMenu, which is compiled.
	var names: PackedStringArray = DirAccess.get_files_at(LEVELS)
	names.sort()
	var shown: int = 0
	for file_name: String in names:
		if not file_name.ends_with(".json"):
			continue
		var level: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("%s/%s" % [LEVELS, file_name]))
		# `visible` is absent on most of them and absent means shown; only an explicit
		# false hides one.
		if level.get("visible", true) == false:
			print("OUT %-24s oculta (visible: false)" % file_name)
			continue

		var asset: String = "%s/titles/%s.png" % [ART, String(level["titleAsset"]).get_file()]
		if not ResourceLoader.exists(asset):
			print("OUT %-24s sin arte de titulo (%s)" % [file_name, asset])
			continue

		var title := Sprite2D.new()
		title.name = String(level["titleAsset"]).get_file().to_pascal_case()
		title.texture = load(asset)
		title.centered = true
		title.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		var size: Vector2 = title.texture.get_size() * FUNKIN_TO_RUBICON
		# The rect a tap has to land in, in the title's LOCAL space so the list can scroll
		# without the hitbox drifting - the same shape freeplay's disks use.
		title.set_meta(&"hitbox", Rect2(-size * 0.5, size))
		title.set_meta(&"name", String(level["name"]))
		var songs: PackedStringArray = []
		for song: String in (level.get("songs", []) as Array):
			songs.append(song)
		title.set_meta(&"songs", songs)
		titles.add_child(title)
		title.owner = _root
		shown += 1
		print("OUT %-24s %-24s %s" % [file_name, level["name"], songs])

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	_root.set(&"titles", titles)
	_root.set(&"sfx", sfx)

	var packed := PackedScene.new()
	packed.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %d semanas, %s %s" % [shown, "saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)


func _add(node: Node) -> void:
	_root.add_child(node)
	node.owner = _root
