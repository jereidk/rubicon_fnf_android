# Builds a stage scene out of a stage JSON, for any stage that is only props.
#
#   godot --headless --path . --script tools/animania/build_stage_from_json.gd -- <name>
#
# This is the generic path, and it exists because build_stage_scene.gd is phoneCallStreet's
# alone: that stage has a .hx that overrides the JSON in four places, a code-added backdrop
# and hidden props, so it earns a hand-written builder. A stage whose JSON is the whole
# truth does not, and most of them are.
#
# Two conventions carried over from that builder and NOT re-derived here:
#
#   * Coordinates stay VERBATIM in Funkin's 1280x720 space. The project's 1.5x belongs on
#     the level camera; putting it here would resample the art and make every number in the
#     scene un-diffable against the JSON.
#   * `zIndex` is the draw order and becomes child order, lowest first.
#
# The characters block is not built into the scene - it is metadata the LEVEL needs (where
# each character stands, and the cameraOffsets the stage adds on top of the character's
# own). It is written onto the scene root as meta so one file carries both.
extends SceneTree

const ART := "res://animania_mod/source/images/stages"
const DATA := "res://animania_mod/source/data/stages"
const OUT_DIR := "res://animania_mod/stages"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: <stage name>")
		quit(1)
		return

	var stage_name: String = args[0]
	var path: String = "%s/%s.json" % [DATA, stage_name]
	if not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		push_error("no stage json at %s" % path)
		quit(1)
		return

	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var root := Node2D.new()
	root.name = stage_name.to_pascal_case()

	# The level reads these: where each character stands and what the stage adds to its
	# camera offsets. Stage_obj::applyCharacterData adds the STAGE's on top of the
	# character JSON's own, which is the thing this port has got wrong twice.
	root.set_meta(&"characters", data.get("characters", {}))
	root.set_meta(&"camera_zoom", float(data.get("cameraZoom", 1.0)))

	var props: Array = data.get("props", [])
	props.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("zIndex", 0)) < int(b.get("zIndex", 0)))

	var built: int = 0
	for prop: Dictionary in props:
		var asset: String = "%s/%s.png" % [ART, String(prop["assetPath"]).get_file()]
		if not ResourceLoader.exists(asset):
			print("OUT %-16s SIN ARTE (%s)" % [prop["name"], asset])
			continue
		var sprite := Sprite2D.new()
		sprite.name = String(prop["name"]).to_pascal_case()
		sprite.texture = load(asset)
		sprite.centered = false
		var position: Array = prop.get("position", [0, 0])
		sprite.position = Vector2(float(position[0]), float(position[1]))
		var scale: Array = prop.get("scale", [1, 1])
		sprite.scale = Vector2(float(scale[0]), float(scale[1]))
		# Funkin's scrollFactor. Rubicon's camera does not read it, so it is kept as meta
		# rather than faked - a prop that should parallax and does not is a known gap, and
		# a wrong number baked into the position would not be.
		sprite.set_meta(&"scroll", prop.get("scroll", [1, 1]))
		root.add_child(sprite)
		sprite.owner = root
		built += 1
		print("OUT %-16s (%.0f, %.0f) x%.2f z=%d" % [
			prop["name"], sprite.position.x, sprite.position.y, sprite.scale.x,
			int(prop.get("zIndex", 0))])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed := PackedScene.new()
	packed.pack(root)
	var out: String = "%s/stg_%s.tscn" % [OUT_DIR, stage_name.to_snake_case()]
	var err: int = ResourceSaver.save(packed, out)
	print("OUT %d props, %s %s" % [built, "saved" if err == OK else "FAILED", out])
	quit(0 if err == OK else 1)
