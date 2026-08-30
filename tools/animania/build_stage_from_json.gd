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
		# assetPath keeps its folder - two stages have props with the same file name - so
		# the vendored tree mirrors the mod's under images/stages.
		var relative: String = String(prop["assetPath"]).trim_prefix("stages/")
		var asset: String = "%s/%s.png" % [ART, relative]
		if String(prop.get("animType", "")) != "animateatlas" \
				and not ResourceLoader.exists(asset):
			print("OUT %-20s SIN ARTE (%s)" % [prop["name"], asset])
			continue

		# A sparrow prop is a frame of an atlas, not the whole sheet. Most of them have no
		# animations at all and just want frame 0; the ones that do - the curtains, the
		# smoke, the lights - get an AnimatedSprite2D. Drawing the raw PNG instead puts the
		# entire spritesheet on the stage, which is what the first pass of this did.
		var animations: Array = prop.get("animations", [])

		# An Adobe prop is a gdanimate AnimateSymbol, the same as an Adobe character - the
		# atlas and its library are built by build_adobe_character.gd and the prop's
		# `prefix` is the symbol to show. serviceEnterance has four of them: the far city,
		# a pillar, the foreground boxes and the rain.
		if String(prop.get("animType", "")) == "animateatlas":
			var basename: String = relative.get_file().to_snake_case()
			var atlas_path: String = "%s/%s_atlas.tres" % [OUT_DIR, basename]
			if not ResourceLoader.exists(atlas_path):
				print("OUT %-20s sin atlas Adobe (%s)" % [prop["name"], atlas_path])
				continue
			var symbol := AnimateSymbol.new()
			symbol.name = String(prop["name"]).to_pascal_case()
			symbol.atlases = [load(atlas_path)] as Array[AnimateAtlas]
			symbol.atlas_index = 0
			symbol.centered = false
			symbol.symbol = String((animations[0] as Dictionary).get("prefix", "")) \
				if not animations.is_empty() else ""
			_place(symbol, prop)
			root.add_child(symbol)
			symbol.owner = root
			var player := AnimationPlayer.new()
			player.name = "AnimationPlayer"
			player.add_animation_library(&"", load("%s/%s_library.tres" % [OUT_DIR, basename]))
			symbol.add_child(player)
			player.owner = root
			var clip := StringName("%s_loop" % basename)
			if player.has_animation(clip):
				player.get_animation_library(&"").get_animation(clip).loop_mode = \
					Animation.LOOP_LINEAR
				player.autoplay = clip
			built += 1
			print("OUT %-20s adobe '%s' (%.0f, %.0f) z=%d" % [prop["name"], symbol.symbol,
				symbol.position.x, symbol.position.y, int(prop.get("zIndex", 0))])
			continue

		var frames: SpriteFrames = null
		if String(prop.get("animType", "")) == "sparrow":
			var built_frames: String = "%s/%s_frames.tres" % [
				OUT_DIR, relative.get_file().to_snake_case()]
			if ResourceLoader.exists(built_frames):
				frames = load(built_frames)
			# Some props say `sparrow` and ship a bare PNG with no atlas beside it - the
			# stage wall, the posters, the floor, the vignettes. Those are the whole
			# picture and fall through to the plain path below.

		if frames != null:
			var animated := AnimatedSprite2D.new()
			animated.name = String(prop["name"]).to_pascal_case()
			animated.sprite_frames = frames
			var names: PackedStringArray = frames.get_animation_names()
			var wanted: String = names[0] if not names.is_empty() else ""
			# A prop that declares an animation names it by PREFIX, the same way a
			# character does; the importer already split the atlas by prefix.
			if not animations.is_empty():
				var prefix: String = String((animations[0] as Dictionary).get("prefix", ""))
				for candidate: String in names:
					if candidate.begins_with(prefix) or prefix.begins_with(candidate):
						wanted = candidate
			animated.animation = StringName(wanted)
			# Only a prop that ships an animation plays; the rest hold their first frame.
			if animations.is_empty():
				animated.autoplay = ""
			else:
				animated.autoplay = wanted
			_place(animated, prop)
			root.add_child(animated)
			animated.owner = root
			built += 1
			print("OUT %-20s %-22s (%.0f, %.0f) z=%d" % [prop["name"], wanted,
				animated.position.x, animated.position.y, int(prop.get("zIndex", 0))])
			continue

		var sprite := Sprite2D.new()
		sprite.name = String(prop["name"]).to_pascal_case()
		sprite.texture = load(asset)
		sprite.centered = false
		_place(sprite, prop)
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

	_apply_script_overrides(root, stage_name)
	_apply_script_tweens(root, stage_name)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed := PackedScene.new()
	packed.pack(root)
	var out: String = "%s/stg_%s.tscn" % [OUT_DIR, stage_name.to_snake_case()]
	var err: int = ResourceSaver.save(packed, out)
	print("OUT %d props, %s %s" % [built, "saved" if err == OK else "FAILED", out])
	quit(0 if err == OK else 1)


## Position and scale verbatim in Funkin's space, plus the two fields that decide whether a
## prop is scenery or a full-screen black rectangle.
##
## `alpha` and `blend` are easy to miss because most props carry neither. mainStageAmTake's
## two vignettes carry both - vin1 is `alpha: 0` (there but invisible) and vin2 is
## `alpha: 0.8, blend: multiply` - and ignoring them drew two opaque sheets at zIndex 317,
## which is over everything. Half the stage came out black.
func _place(node: Node2D, prop: Dictionary) -> void:
	var position: Array = prop.get("position", [0, 0])
	node.position = Vector2(float(position[0]), float(position[1]))
	var scale: Array = prop.get("scale", [1, 1])
	node.scale = Vector2(float(scale[0]), float(scale[1]))

	if prop.has("alpha"):
		node.modulate.a = float(prop["alpha"])

	var blend: String = String(prop.get("blend", ""))
	if blend.is_empty():
		return
	var material := CanvasItemMaterial.new()
	match blend:
		"multiply":
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		"add", "additive":
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		"subtract":
			material.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
		_:
			print("OUT %-20s blend '%s' sin equivalente, se deja normal"
				% [prop["name"], blend])
			return
	node.material = material


## What a stage's `.hx` does to its props on top of the JSON.
##
## EVERY stage has one - `scripts/stages/<name>.hx` - and this port did not go looking for
## them until dadbattle came out with a pink sheet over the whole screen. The JSON is not
## the whole truth for any stage; phoneCallStreet's builder knew that and the generic one
## did not.
##
## Only the prop tweens are here. The scripts also add FlxBackdrops in code (the drifting
## mists), drive shaders and play ambience, and none of that is ported - it is written down
## rather than half-done.
const SCRIPT_TWEENS := {
	# serviceEnterance.hx:174
	#   FlxTween.tween(getNamedProp("fgRedOverlay"), {alpha: 0.5}, 2,
	#       {ease: FlxEase.sineInOut, type: 4});
	# type 4 is PINGPONG, so the red breathes between the JSON's alpha of 1 and 0.5 instead
	# of sitting at full - the difference between a wash you can see through and one you
	# cannot.
	"serviceEnterance": [["FgRedOverlay", 1.0, 0.5, 2.0]],
}


func _apply_script_tweens(root: Node2D, stage_name: String) -> void:
	if not SCRIPT_TWEENS.has(stage_name):
		return
	var player := AnimationPlayer.new()
	player.name = "ScriptTweens"
	root.add_child(player)
	player.owner = root
	var library := AnimationLibrary.new()
	var first := StringName()

	for entry: Array in SCRIPT_TWEENS[stage_name]:
		var target: Node = root.get_node_or_null(String(entry[0]))
		if target == null:
			print("OUT tween de script sin prop: %s" % entry[0])
			continue
		var animation := Animation.new()
		# There and back: FlxTween's PINGPONG runs the duration each way.
		animation.length = float(entry[3]) * 2.0
		animation.loop_mode = Animation.LOOP_LINEAR
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath("%s:modulate:a" % entry[0]))
		# sineInOut, sampled - the same reason the camera baker samples its eases.
		for i: int in 33:
			var t: float = float(i) / 32.0
			var eased: float = 0.5 - 0.5 * cos(t * TAU)
			animation.track_insert_key(track, t * animation.length,
				lerpf(float(entry[1]), float(entry[2]), eased))
		var clip := StringName(String(entry[0]).to_snake_case())
		library.add_animation(clip, animation)
		if String(first).is_empty():
			first = clip
		print("OUT tween de script: %s alpha %.2f<->%.2f cada %.1fs" % [
			entry[0], entry[1], entry[2], entry[3]])

	player.add_animation_library(&"", library)
	player.autoplay = first


## What a stage's `.hx` sets on its props AT CREATE, which is not what the JSON says.
##
## mainStageAmTake.hx opens with `setLight(true)`, `setSmokeVisible(false)` and then flips
## both vignettes - six props whose JSON values are the wrong ones to build. The lights and
## the smoke come on later, driven by the song; a stage built from the JSON alone starts
## with them already on.
##
## `0.00001` in the script is Flixel's way of keeping a sprite in the draw list while
## invisible; here it is just 0.
const SCRIPT_OVERRIDES := {
	"mainStageAmTake": {
		# mainStageAmTake.hx:73-74 - the JSON has these the other way round.
		"Vin1": 1.0,
		"Vin2": 0.0,
		# setLight(true) at :66, which is :371-374.
		"FloorLights": 0.0,
		"FloorLightsBlendy": 0.0,
		# setSmokeVisible(false) at :67, which is :549.
		"SmokeLf": 0.0,
		"SmokeRf": 0.0,
		"SmokeLb": 0.0,
		"SmokeRb": 0.0,
	},
}


func _apply_script_overrides(root: Node2D, stage_name: String) -> void:
	if not SCRIPT_OVERRIDES.has(stage_name):
		return
	var applied: int = 0
	for prop_name: String in SCRIPT_OVERRIDES[stage_name]:
		var target: CanvasItem = root.get_node_or_null(prop_name) as CanvasItem
		if target == null:
			print("OUT override sin prop: %s" % prop_name)
			continue
		target.modulate.a = float(SCRIPT_OVERRIDES[stage_name][prop_name])
		applied += 1
	print("OUT %d props con el valor del .hx en vez del JSON" % applied)
