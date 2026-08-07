extends SceneTree

## Reports animation tracks that will not resolve at runtime.
##
## Godot drops a track whose NodePath points at nothing, or whose property the
## target node does not have, **without saying a word** - the animation just
## quietly does less than it was authored to do. This project has been bitten
## by that repeatedly: 86% of the Collector's and Hex's bone tracks were being
## discarded because the glTF importer renamed the bones, and Hypno's three
## tracks driving `dancing_measure_step` vanished when this fork renamed the
## property out from under scenes authored against the mod's Rubicon.
##
##   python3 tools/collect_animation_tracks.py > tracks.json
##   godot --headless --script tools/audit_animation_tracks.gd -- tracks.json
##
## What each track type is checked for:
##
##   value / bezier            target node exists AND has the property
##   animation                 target node exists and is an AnimationPlayer
##   audio                     target node exists and is an AudioStreamPlayer*
##   method                    target node exists (the method name lives in the
##                             keys, not the path)
##   position/rotation/scale_3d, blend_shape
##                             target node exists (the subname is a bone or
##                             blend shape, not a property)
##
## Nodes the collector could not type are reported separately, not as findings -
## an unknown class would make every property on it look missing. The skipped
## count is broken down by reason so the coverage is auditable rather than a
## number to trust.
##
## **A track pointing at a node created at runtime is reported as unresolved,
## and that is not a bug.** Monochrome's `scene` animation drives
## `../BloodCutscene/...`, `../BoyfriendScream` and `../MonoCloseup`, none of
## which are in the .tscn - `BloodCutsceneLoader` instantiates all three from
## uid paths when the song reaches them. There is no way to tell that apart
## from a genuinely dead path statically, so read this section, do not gate on
## it.

## Animation.TrackType, for the tracks read out of external libraries.
const TRACK_TYPE_NAMES: Array[String] = [
	"value", "position_3d", "rotation_3d", "scale_3d", "blend_shape",
	"method", "bezier", "audio", "animation",
]

## Property names Godot builds at runtime, which ClassDB cannot see. Same
## reasoning as audit_authored_properties.gd - left in, they are most of the
## output and the real findings become unfindable.
const DYNAMIC_PREFIXES: Array[String] = [
	"surface_material_override/", "bones/", "blend_shapes/", "parameters/",
	"theme_override", "shader_parameter/", "libraries/", "next/", "metadata/",
]

## Returned by _resolve() when a path cannot be followed from text at all, as
## opposed to resolving to nothing.
const UNRESOLVABLE := "?"

var _property_cache: Dictionary = {}
var _dynamic_script_cache: Dictionary = {}

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "tracks.json"

	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		print("OUT cannot read ", path)
		quit()
		return

	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		print("OUT bad json")
		quit()
		return

	var tracks_checked: int = 0
	var unknown_class: int = 0
	var skipped: Dictionary = {
		"unique_name_path": 0, "opaque_subtree": 0, "unknown_class": 0,
		"dynamic_script": 0,
	}
	var missing_node: Array = []
	var missing_prop: Array = []
	var wrong_type: Array = []

	for scene_entry: Dictionary in data["scenes"]:
		var scene: String = scene_entry["scene"]
		var tree: Dictionary = scene_entry["tree"]

		for player: Dictionary in scene_entry["players"]:
			var root: String = _resolve(player["path"], player["root_node"])
			if root == "" or root == UNRESOLVABLE:
				# root_node points above the scene root; nothing here can be
				# checked, and it is legal (the player is meant to be reparented).
				continue

			var animations: Array = []
			animations.append_array(player["animations"])
			for lib_path: String in player["external_libraries"]:
				animations.append_array(_read_library(lib_path))

			for anim: Dictionary in animations:
				for track: Dictionary in anim["tracks"]:
					tracks_checked += 1
					var raw_path: String = track["path"]
					var node_part: String = raw_path
					var sub: String = ""
					var colon: int = raw_path.find(":")
					if colon >= 0:
						node_part = raw_path.substr(0, colon)
						sub = raw_path.substr(colon + 1)

					var target: String = _resolve(root, node_part)
					var where: String = "%s :: %s/%s '%s' -> %s" % [
						scene, player["path"], anim["name"], raw_path, target,
					]

					if target == UNRESOLVABLE:
						unknown_class += 1
						skipped["unique_name_path"] += 1
						continue
					if target == "":
						missing_node.append(where)
						continue
					# Most of this project's bone tracks aim inside a skeleton
					# that came from a .gltf, which the collector cannot read.
					# Those are unchecked, not broken.
					if _under_opaque(tree, target):
						unknown_class += 1
						skipped["opaque_subtree"] += 1
						continue
					if not tree.has(target):
						missing_node.append(where)
						continue

					var info: Dictionary = tree[target]
					var type: String = str(info.get("type", ""))
					var script_path: String = str(info.get("script", ""))

					var kind: String = track["type"]
					if kind == "animation" or kind == "audio":
						if type.is_empty():
							unknown_class += 1
						elif kind == "animation" and type != "AnimationPlayer":
							wrong_type.append(where + "  (animation track on " + type + ")")
						elif kind == "audio" and not type.begins_with("AudioStreamPlayer"):
							wrong_type.append(where + "  (audio track on " + type + ")")
						continue

					if kind != "value" and kind != "bezier":
						continue
					if sub.is_empty():
						continue

					# A node whose class the collector could not name has to be
					# skipped, not guessed at: falling back to the script's own
					# base type made Chimera's `hex` - RubiconCharacter, which
					# extends Node, on a .gltf-instanced Node3D - report its
					# perfectly valid `visible`, `position` and `rotation` as
					# missing.
					if type.is_empty():
						unknown_class += 1
						skipped["unknown_class"] += 1
						continue

					# `position:x` animates a component; only the property
					# itself has to exist.
					var prop: String = sub.split(":")[0]
					if _is_dynamic(prop):
						continue

					# A script with its own _get_property_list() declares
					# properties nothing static can enumerate. RubiconCharacter
					# builds sing_left/miss_up/... that way from
					# mania_anim_aliases, and the pck's does too - 45 tracks
					# driving them are correct on both engines.
					if _has_dynamic_properties(script_path):
						unknown_class += 1
						skipped["dynamic_script"] += 1
						continue

					var valid: Dictionary = _valid_properties(type, script_path)
					if valid.is_empty():
						unknown_class += 1
						continue

					if not valid.has(prop):
						missing_prop.append(where + "  (no '" + prop + "' on " + type
							+ (" + " + script_path.get_file() if not script_path.is_empty() else "") + ")")

	print("OUT tracks_checked=", tracks_checked,
		" unresolved_node=", missing_node.size(),
		" missing_property=", missing_prop.size(),
		" wrong_target_type=", wrong_type.size(),
		" skipped=", unknown_class)
	print("OUT skipped breakdown: unique_name_path=", skipped["unique_name_path"],
		" opaque_subtree=", skipped["opaque_subtree"],
		" unknown_class=", skipped["unknown_class"],
		" dynamic_script=", skipped["dynamic_script"])

	_report("UNRESOLVED NODE", missing_node)
	_report("MISSING PROPERTY", missing_prop)
	_report("WRONG TARGET TYPE", wrong_type)
	quit()

func _report(label: String, rows: Array) -> void:
	if rows.is_empty():
		return
	print("OUT")
	print("OUT === ", label, " (", rows.size(), ") ===")
	rows.sort()
	for r: String in rows:
		print("OUT   ", r)

## Whether [param path] is, or lives under, a node the collector marked opaque
## (an instance of a .gltf/.scn, whose children are not readable from text).
func _under_opaque(tree: Dictionary, path: String) -> bool:
	var segs: PackedStringArray = path.split("/", false)
	var walked: String = ""
	for seg: String in segs:
		walked = seg if walked.is_empty() else walked + "/" + seg
		var info: Variant = tree.get(walked)
		if info is Dictionary and bool(info.get("opaque", false)):
			return true
	return false

func _is_dynamic(prop: String) -> bool:
	for prefix: String in DYNAMIC_PREFIXES:
		if prop.begins_with(prefix):
			return true
	return false

## Whether [param script_path] implements _get_property_list(), i.e. exposes
## properties that only exist on a live instance.
func _has_dynamic_properties(script_path: String) -> bool:
	if script_path.is_empty():
		return false
	if _dynamic_script_cache.has(script_path):
		return _dynamic_script_cache[script_path]

	var found: bool = false
	if ResourceLoader.exists(script_path):
		var script := load(script_path) as Script
		while script != null and not found:
			for m: Dictionary in script.get_script_method_list():
				if m["name"] == "_get_property_list":
					found = true
					break
			script = script.get_base_script()

	_dynamic_script_cache[script_path] = found
	return found

## Walks [param rel] from [param base], both as "/"-joined scene paths where
## "." is the scene root. Returns "" if it walks above the root.
##
## A "%Name" segment is a unique-name lookup resolved against the scene owner
## at runtime, which cannot be followed from text - those return "" and are
## counted as unresolvable rather than reported as a broken path.
func _resolve(base: String, rel: String) -> String:
	if rel.contains("%"):
		return UNRESOLVABLE
	var segs: Array = []
	if base != "." and not base.is_empty():
		segs = Array(base.split("/", false))

	for seg: String in rel.split("/", false):
		if seg == ".":
			continue
		if seg == "..":
			if segs.is_empty():
				return ""
			segs.pop_back()
			continue
		segs.append(seg)

	if segs.is_empty():
		return "."
	return "/".join(PackedStringArray(segs))

## Animations of an external AnimationLibrary, in the same shape the collector
## emits for the ones embedded in a scene.
func _read_library(res_path: String) -> Array:
	if not ResourceLoader.exists(res_path):
		return []
	var lib := load(res_path) as AnimationLibrary
	if lib == null:
		return []

	var out: Array = []
	for name: StringName in lib.get_animation_list():
		var anim: Animation = lib.get_animation(name)
		if anim == null:
			continue
		var tracks: Array = []
		for t in anim.get_track_count():
			var type_index: int = anim.track_get_type(t)
			tracks.append({
				"type": TRACK_TYPE_NAMES[type_index] if type_index < TRACK_TYPE_NAMES.size() else "unknown",
				"path": str(anim.track_get_path(t)),
			})
		out.append({"name": str(name), "tracks": tracks})
	return out

func _valid_properties(type: String, script_path: String) -> Dictionary:
	var key: String = type + "|" + script_path
	if _property_cache.has(key):
		return _property_cache[key]

	var out: Dictionary = {}
	if not type.is_empty() and ClassDB.class_exists(type):
		for p: Dictionary in ClassDB.class_get_property_list(type):
			out[p["name"]] = true

	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		var script := load(script_path) as Script
		while script != null:
			for p: Dictionary in script.get_script_property_list():
				out[p["name"]] = true
			var base: String = script.get_instance_base_type()
			if not base.is_empty() and ClassDB.class_exists(base):
				for p: Dictionary in ClassDB.class_get_property_list(base):
					out[p["name"]] = true
			script = script.get_base_script()

	_property_cache[key] = out
	return out
