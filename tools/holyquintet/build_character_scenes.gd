# Builds Holy Quintet's Adobe Animate characters and animated stage props into Rubicon
# character/prop scenes, read straight from the mod's own Codename XML and Animation.json.
#
#   godot --headless --path . --script tools/holyquintet/build_character_scenes.gd
#
# A HQ character XML declares animations against one Adobe atlas ("SAYAKAATLAS") using
# frame indices ("0..13") - Codename plays ranges of the atlas's stage timeline. gdanimate
# drives the same thing with an AnimateSymbol whose `frame` is an index into that timeline,
# so each library clip keys `symbol` once and `frame` once per atlas frame. Animations
# without indices ("letsgo" pointing at "0 - SAYAKA/sayaka voiceline") are whole symbols.
#
# Funkin negates a character's authored per-anim offset when it applies it (offset.set(-x,
# -y)); that is done on the ROOT animation's offset track - the same way the Animania port
# does, because the inner clip and the root player would otherwise both write the property.
# The base origin (where the character's feet sit in the symbol's space) is MEASURED with
# tools/animania/harness/measure_character.gd and folded into ORIGINS below - not guessed.
extends SceneTree

const CHARACTER_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_character.gd"
const ADOBE_ATLAS_SCRIPT := preload("res://addons/gdanimate/adobe/adobe_atlas.gd")
const ANIMATE_SYMBOL_SCRIPT := preload("res://addons/gdanimate/animate_symbol.gd")
const OUT_CHARS := "res://holyquintet_mod/characters"
const OUT_PROPS := "res://holyquintet_mod/stages/props"
const FPS := 24.0

# name: [atlas_folder, char_xml, flip]
const CHARACTERS := {
	"sayaka-base": {
		"atlas": "res://holyquintet_mod/source/images/characters/sayaka-base",
		"xml": "res://holyquintet_mod/source/data/characters/sayaka-base.xml",
		"flip": false,
		"origin": Vector2(244.5, 725.0),   # MEASURED

	},
	"gf-base": {
		"atlas": "res://holyquintet_mod/source/images/characters/gf-base",
		"xml": "res://holyquintet_mod/source/data/characters/gf-base.xml",
		"flip": true,
		"origin": Vector2(-226.5, 584.0),   # MEASURED

	},
	"kyubey-big-bald": {
		"atlas": "res://holyquintet_mod/source/images/characters/kyubey-big-bald",
		# The mod ships kyubey-big-bald.xml as the credits list (packaging bug), so the
		# anims come from its sibling kyubey-big.xml - both share the KYUBEYATLAS symbol.
		"xml": "res://holyquintet_mod/source/data/characters/kyubey-big.xml",
		"flip": false,
		"origin": Vector2(165.5, 244.0),   # MEASURED

	},
	"madokabg": {
		"atlas": "res://holyquintet_mod/source/images/stages/resonance/madokabg",
		"flip": false,
		"origin": Vector2.ZERO,
		"prop": true,
	},
	"mamibg": {
		"atlas": "res://holyquintet_mod/source/images/stages/resonance/mamibg",
		"flip": false,
		"origin": Vector2.ZERO,
		"prop": true,
	},
}


func _init() -> void:
	for name: String in CHARACTERS:
		var cfg: Dictionary = CHARACTERS[name]
		var atlas := _build_atlas(name, cfg["atlas"])
		if atlas == null:
			quit(1)
			return
		var clips := _build_library(name, cfg, atlas)
		if clips.is_empty():
			push_error("%s: no clips built" % name)
			quit(1)
			return
		if cfg.get("prop", false):
			_build_prop_scene(name, cfg, clips, atlas)
		else:
			_build_character_scene(name, cfg, clips, atlas)
	quit(0)


func _build_atlas(name: String, folder: String) -> Resource:
	# AdobeAtlas.parse() short-circuits to animation_cache.res when one exists, so a run
	# after a parser change would silently re-save the OLD tree. The cache is derived by
	# this same run two lines down.
	var stale_cache: String = "%s/animation_cache.res" % folder
	if FileAccess.file_exists(stale_cache):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stale_cache))

	var atlas = ADOBE_ATLAS_SCRIPT.new()
	atlas.folder_path = folder
	atlas.parse()
	if atlas.symbols.is_empty() and atlas.stage_symbol == "":
		push_error("%s: no symbols parsed from %s" % [name, folder])
		return null
	atlas.cache()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_CHARS))
	var atlas_path := "%s/%s_atlas.tres" % [OUT_CHARS, name]
	var err: int = ResourceSaver.save(atlas, atlas_path)
	if err != OK:
		push_error("%s: could not save %s (%d)" % [name, atlas_path, err])
		return null
	print("OUT %s -> %s (stage symbol=%s)" % [name, atlas_path, atlas.stage_symbol])
	return atlas


func _build_library(name: String, cfg: Dictionary, atlas: Resource) -> Dictionary:
	var library := AnimationLibrary.new()
	if cfg.get("prop", false):
		# An animated stage prop has no character XML: its whole stage symbol IS its
		# animation (resonance.hx does addAnim('bop', '<stage symbol>', 24, false, false)).
		var frames := PackedInt32Array()
		var length: int = atlas.get_length_of(atlas.stage_symbol)
		for f: int in length:
			frames.append(f)
		var clip := Animation.new()
		clip.step = 1.0 / FPS
		clip.length = maxf(float(length) / FPS, clip.step)
		clip.loop_mode = Animation.LOOP_LINEAR
		var sym_track: int = clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(sym_track, ^".:symbol")
		clip.value_track_set_update_mode(sym_track, Animation.UPDATE_DISCRETE)
		clip.track_set_interpolation_type(sym_track, Animation.INTERPOLATION_NEAREST)
		clip.track_insert_key(sym_track, 0.0, String(atlas.stage_symbol))
		var fr_track: int = clip.add_track(Animation.TYPE_VALUE)
		clip.track_set_path(fr_track, ^".:frame")
		clip.value_track_set_update_mode(fr_track, Animation.UPDATE_DISCRETE)
		clip.track_set_interpolation_type(fr_track, Animation.INTERPOLATION_NEAREST)
		for k: int in frames.size():
			clip.track_insert_key(fr_track, float(k) / FPS, frames[k])
		library.add_animation(StringName("bop"), clip)
		var library_path := "%s/%s_library.tres" % [OUT_CHARS, name]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_CHARS))
		var err: int = ResourceSaver.save(library, library_path)
		if err != OK:
			push_error("%s: could not save %s (%d)" % [name, library_path, err])
			return {}
		print("OUT %-24s frames=%-4d len=%.3fs loop=true <- %s (prop)" % [
			"bop", length, clip.length, atlas.stage_symbol])
		print("OUT library %s (1 clip)" % library_path)
		return {&"bop": &"bop"}

	var xml: Dictionary = _parse_character_xml(cfg["xml"])
	if xml.is_empty():
		push_error("%s: could not parse %s" % [name, cfg["xml"]])
		return {}
	var fps: float = atlas.get_framerate()
	var clips: Dictionary = {}
	var missing: PackedStringArray = []
	for anim: Dictionary in xml["anims"]:
		var clip_name := StringName("%s_%s" % [name, anim["name"]])
		var symbol: String = anim["symbol"]
		var is_stage: bool = symbol == atlas.stage_symbol
		if not atlas.symbols.has(StringName(symbol)) and not is_stage:
			missing.append("%s (%s)" % [symbol, anim["name"]])
			continue

		var frames: PackedInt32Array = anim["frames"]
		var length: int = frames.size()
		if length == 0:
			length = atlas.get_length_of(StringName(symbol))
			for f: int in length:
				frames.append(f)

		var animation := Animation.new()
		animation.step = 1.0 / fps
		animation.length = maxf(float(length) / fps, animation.step)
		if anim["loop"]:
			animation.loop_mode = Animation.LOOP_LINEAR

		var symbol_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(symbol_track, ^".:symbol")
		animation.value_track_set_update_mode(symbol_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(symbol_track, Animation.INTERPOLATION_NEAREST)
		animation.track_insert_key(symbol_track, 0.0, symbol)

		var frame_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(frame_track, ^".:frame")
		animation.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(frame_track, Animation.INTERPOLATION_NEAREST)
		for k: int in frames.size():
			animation.track_insert_key(frame_track, float(k) / fps, frames[k])

		library.add_animation(clip_name, animation)
		clips[StringName(anim["name"])] = clip_name
		print("OUT %-24s frames=%-4d len=%.3fs loop=%s <- %s%s" % [
			clip_name, length, animation.length, anim["loop"], symbol,
			" (stage)" if is_stage else ""])

	if not missing.is_empty():
		push_error("%s: symbols not in atlas: %s" % [name, ", ".join(missing)])
		return {}

	# The offset values, keyed by HQ anim name for the root library.
	clips[&"__offsets__"] = _anim_offsets(xml)

	var library_path := "%s/%s_library.tres" % [OUT_CHARS, name]
	var err: int = ResourceSaver.save(library, library_path)
	if err != OK:
		push_error("%s: could not save %s (%d)" % [name, library_path, err])
		return {}
	print("OUT library %s (%d clips)" % [library_path, clips.size() - 1])
	return clips


## XMLParser.get_attribute_value takes an index, not a name, in this Godot build.
func _attr(parser: XMLParser, name: String) -> String:
	for i: int in parser.get_attribute_count():
		if parser.get_attribute_name(i) == name:
			return parser.get_attribute_value(i)
	return ""


## Codename character XML: <character ...><anim name anim indices loop fps x y/></character>
func _parse_character_xml(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parser := XMLParser.new()
	var err := parser.open_buffer(text.to_utf8_buffer())
	if err != OK:
		return {}
	var result: Dictionary = {"anims": []}
	var in_character := false
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		var tag: String = parser.get_node_name()
		if tag == "character":
			in_character = true
			for attr: String in ["x", "y", "camx", "camy", "icon", "color", "flipX", "isPlayer"]:
				if parser.has_attribute(attr):
					result[attr] = _attr(parser, attr)
		elif tag == "anim" and in_character:
			var name := _attr(parser, "name")
			var symbol := _attr(parser, "anim")
			var indices := _attr(parser, "indices")
			var loop := true
			if parser.has_attribute("loop"):
				loop = _attr(parser, "loop").to_lower() == "true"
			var offset := Vector2.ZERO
			if parser.has_attribute("x"):
				offset.x = float(_attr(parser, "x"))
			if parser.has_attribute("y"):
				offset.y = float(_attr(parser, "y"))
			result["anims"].append({
				"name": name, "symbol": symbol,
				"frames": _parse_indices(indices), "loop": loop, "offset": offset,
			})
	return result


func _anim_offsets(xml: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for anim: Dictionary in xml["anims"]:
		out[anim["name"]] = anim["offset"]
	return out


## "0..13" -> [0..13]; "297..310,310,310,315..314" -> held/repeated ranges in order.
func _parse_indices(indices: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if indices == "":
		return out
	for token: String in indices.split(",", false):
		if token.contains(".."):
			var parts := token.split("..")
			if parts.size() != 2:
				continue
			var first := int(parts[0])
			var last := int(parts[1])
			if first <= last:
				for i: int in range(first, last + 1):
					out.append(i)
			else:
				for i: int in range(first, last - 1, -1):
					out.append(i)
		else:
			out.append(int(token))
	return out


## Root scene for a singer/gf/opponent: RubiconCharacter + AnimateSymbol + players.
func _build_character_scene(name: String, cfg: Dictionary, clips: Dictionary,
		atlas: Resource) -> void:
	var xml: Dictionary = _parse_character_xml(cfg["xml"])
	var basename := name.replace("-", "_")
	var all_offsets: Dictionary = clips[&"__offsets__"]

	var root := Node2D.new()
	root.name = basename
	root.set_script(load(CHARACTER_SCRIPT))

	var symbol = ANIMATE_SYMBOL_SCRIPT.new()
	symbol.name = "AnimateSymbol"
	symbol.atlases = [atlas] as Array[AnimateAtlas]
	symbol.atlas_index = 0
	symbol.symbol = String(atlas.stage_symbol)
	symbol.centered = false
	symbol.position = -cfg["origin"]
	if cfg["flip"]:
		symbol.scale.x = -1.0
	root.add_child(symbol)
	symbol.owner = root

	var symbol_player := AnimationPlayer.new()
	symbol_player.name = "AnimationPlayer"
	symbol_player.add_animation_library(&"", load("%s/%s_library.tres" % [OUT_CHARS, name]))
	symbol.add_child(symbol_player)
	symbol_player.owner = root

	# Rubicon dialect: HQ singLEFT -> sing_left, danceLeft/danceRight -> dance_left/right,
	# sing*miss -> miss_*. Missing miss art falls back to the sing clip (Funkin behaviour).
	var root_clips: Dictionary = {}
	var root_offsets: Dictionary = {}
	var sing_map := {
		"singLEFT": "sing_left", "singDOWN": "sing_down", "singUP": "sing_up",
		"singRIGHT": "sing_right",
	}
	for hq: String in sing_map:
		var rubicon: String = sing_map[hq]
		if clips.has(StringName(hq)):
			var miss: String = "miss_%s" % rubicon.trim_prefix("sing_")
			root_clips[StringName(rubicon)] = clips[StringName(hq)]
			root_offsets[StringName(rubicon)] = all_offsets[hq]
			var miss_hq := "%smiss" % hq
			root_clips[StringName(miss)] = clips[StringName(miss_hq)] \
				if clips.has(StringName(miss_hq)) else clips[StringName(hq)]
			root_offsets[StringName(miss)] = all_offsets[miss_hq] \
				if all_offsets.has(miss_hq) else all_offsets[hq]

	var dancing: Array[StringName] = []
	if clips.has(&"danceLeft") and clips.has(&"danceRight"):
		dancing = [&"dance_left", &"dance_right"]
		root_clips[&"dance_left"] = clips[&"danceLeft"]
		root_clips[&"dance_right"] = clips[&"danceRight"]
		root_offsets[&"dance_left"] = all_offsets[&"danceLeft"]
		root_offsets[&"dance_right"] = all_offsets[&"danceRight"]
	if clips.has(&"idle"):
		dancing = [&"dance_idle"]
		root_clips[&"dance_idle"] = clips[&"idle"]
		root_offsets[&"dance_idle"] = all_offsets[&"idle"]

	# Keep the remaining HQ anims reachable by snake_case names through the same root
	# player (healstart/healend/letsgo/bow/...), for events that will ask for them later.
	for hq: StringName in clips:
		if hq == &"__offsets__" or root_clips.has(hq):
			continue
		var rubicon_name := StringName(String(hq).to_snake_case())
		root_clips[rubicon_name] = clips[hq]
		root_offsets[rubicon_name] = all_offsets[hq]

	var root_player := AnimationPlayer.new()
	root_player.name = "RootAnimationPlayer"
	root_player.add_animation_library(&"", _root_library(root_clips, root_offsets,
		^"AnimateSymbol/AnimationPlayer", ^"AnimateSymbol:offset"))
	root_player.autoplay = dancing[0] if not dancing.is_empty() else &"RESET"
	root.add_child(root_player)
	root_player.owner = root

	root.animation_player = root_player
	root.animations = _sing_and_miss_map(root_clips)
	var anim_groups: Dictionary[StringName, int] = {&"sing": 4, &"miss": 4}
	root.mania_anim_groups = anim_groups
	root.dancing_animations = dancing
	root.dancing_force_dance = false
	root.dancing_measure_step = 0.25
	root.singing_sing_to_dance_interval = 8
	root.singing_repeat_loop_point = 2.0 / FPS
	root.transition_update_queued_animations = true

	# XML attrs kept on the root for whoever places the character.
	for attr: String in ["x", "y", "camx", "camy", "icon", "color", "flipX", "isPlayer"]:
		if xml.has(attr):
			root.set_meta(attr, xml[attr])

	_save(root, "%s/chr_%s.tscn" % [OUT_CHARS, basename])


## Animated stage prop (madokabg/mamibg): an AnimateSymbol whose only clip is its bop.
func _build_prop_scene(name: String, cfg: Dictionary, clips: Dictionary,
		atlas: Resource) -> void:
	var clip_names: Array[StringName] = []
	for clip: StringName in clips:
		if clip != &"__offsets__":
			clip_names.append(clip)
	if clip_names.is_empty():
		push_error("%s: prop has no clips" % name)
		return

	var root := Node2D.new()
	root.name = name

	var symbol = ANIMATE_SYMBOL_SCRIPT.new()
	symbol.name = "AnimateSymbol"
	symbol.atlases = [atlas] as Array[AnimateAtlas]
	symbol.atlas_index = 0
	symbol.symbol = String(atlas.stage_symbol)
	symbol.centered = false
	root.add_child(symbol)
	symbol.owner = root

	var symbol_player := AnimationPlayer.new()
	symbol_player.name = "AnimationPlayer"
	symbol_player.add_animation_library(&"", load("%s/%s_library.tres" % [OUT_CHARS, name]))
	symbol.add_child(symbol_player)
	symbol_player.owner = root
	symbol_player.autoplay = clip_names[0]

	_save(root, "%s/%s.tscn" % [OUT_PROPS, name])


func _sing_and_miss_map(clips: Dictionary) -> Dictionary[StringName, StringName]:
	var out: Dictionary[StringName, StringName] = {}
	for candidate: String in ["sing_left", "sing_down", "sing_up", "sing_right",
			"miss_left", "miss_down", "miss_up", "miss_right"]:
		if clips.has(StringName(candidate)):
			out[StringName(candidate)] = StringName(candidate)
	return out


func _root_library(clips: Dictionary, offsets: Dictionary, player_path: NodePath,
		offset_path: NodePath) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.001
	var reset_track: int = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(reset_track, offset_path)
	reset.value_track_set_update_mode(reset_track, Animation.UPDATE_DISCRETE)
	reset.track_insert_key(reset_track, 0.0, Vector2.ZERO)
	library.add_animation(&"RESET", reset)

	for anim_name: StringName in clips:
		var clip: StringName = clips[anim_name]
		var animation := Animation.new()
		animation.length = 0.25
		animation.step = 1.0 / FPS
		var clip_track: int = animation.add_track(Animation.TYPE_ANIMATION)
		animation.track_set_path(clip_track, player_path)
		animation.track_insert_key(clip_track, 0.0, clip)
		# Funkin negates the authored offset when it applies it.
		var offset_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(offset_track, offset_path)
		animation.value_track_set_update_mode(offset_track, Animation.UPDATE_DISCRETE)
		var off := offsets[anim_name] as Vector2 if offsets.has(anim_name) else Vector2.ZERO
		animation.track_insert_key(offset_track, 0.0, -off)
		library.add_animation(anim_name, animation)
	return library


func _save(root: Node, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("could not pack %s (%d)" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
		return
	print("OUT saved %s" % path)
