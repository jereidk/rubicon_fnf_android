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

	# free(), not queue_free(): the deferred queue is never pumped inside a
	# --script _init(), so a queue_free'd child is still there when the scene
	# is packed. The rebuild then APPENDS to the old titles instead of
	# replacing them, and the menu comes out with every week twice.
	for child: Node in titles_container.get_children():
		titles_container.remove_child(child)
		child.free()

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

	_fix_stale_animations(instance)

	var packed := PackedScene.new()
	packed.pack(instance)
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %d weeks, %s %s" % [shown, "saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)


## The scene was authored against base Funkin's storymenu/ui/arrows, whose atlas
## has leftIdle/leftConfirm/rightIdle/rightConfirm. The menu now wears the mod's
## diff-selector, which carries ONE animation ("difficulty arrow"), so the names
## left in `animation` and `autoplay` name nothing: every instantiate printed
## "Animation 'leftIdle' doesn't exist" before a line of the menu's own script
## ran, and every difficulty change printed four more.
##
## Their real names cannot be hardcoded here either - they come from whatever
## atlas the node ends up with - so this asks the SpriteFrames.
func _fix_stale_animations(root: Node) -> void:
	for node: Node in root.find_children("*", "AnimatedSprite2D", true, false):
		var sprite: AnimatedSprite2D = node as AnimatedSprite2D
		var frames: SpriteFrames = sprite.sprite_frames
		if frames == null or frames.get_animation_names().is_empty():
			continue
		if frames.has_animation(sprite.animation):
			continue
		var first: StringName = StringName(frames.get_animation_names()[0])
		print("OUT %-16s %s -> %s" % [sprite.name, sprite.animation, first])
		sprite.animation = first
		if sprite.autoplay != "" and not frames.has_animation(StringName(sprite.autoplay)):
			sprite.autoplay = String(first)
