extends SceneTree

## Reports every property a scene authors that the node's class does not
## actually have.
##
## This is the check for the port's worst failure mode. Our engine is not the
## Rubicon (or gdanimate) the mod's scenes were authored against, so a property
## our fork renamed or never had is not an error - Godot stores it in the scene
## and drops it on load, in silence. That is how AnimateSymbol.offset went
## missing and put Gold's back-turned intro pose in the wrong place, and how
## the misplay subsystem sat dead in all three songs.
##
## Run tools/collect_authored_properties.py first; it walks every .tscn as text
## (fast, and without pulling in each scene's dependencies) and writes the
## node/class/script/property table this reads.
##
##   godot --headless --script tools/audit_authored_properties.gd -- <json_in>
##
## Properties are checked against ClassDB for the node's class plus the whole
## script inheritance chain. A name this cannot resolve is either a real gap or
## a property declared through _get_property_list(), which ClassDB cannot see -
## so treat the output as a list to read, not a build gate.

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "authored.json"

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

	var valid_cache: Dictionary = {}
	var findings: Dictionary = {}
	var checked: int = 0
	var skipped: int = 0

	for entry: Dictionary in data["entries"]:
		var type: String = str(entry.get("type", ""))
		var script_path: String = str(entry.get("script", ""))
		var key: String = type + "|" + script_path

		if not valid_cache.has(key):
			valid_cache[key] = _valid_properties(type, script_path)
		var valid: Dictionary = valid_cache[key]

		if valid.is_empty():
			skipped += 1
			continue
		checked += 1

		for prop: String in entry["props"]:
			# Scene-file bookkeeping, not node properties.
			if prop in ["script", "metadata", "unique_name_in_owner"]:
				continue
			if _is_dynamic(prop):
				continue
			if valid.has(prop):
				continue

			var fkey: String = "%s :: %s" % [key, prop]
			if not findings.has(fkey):
				findings[fkey] = {"type": type, "script": script_path, "prop": prop, "where": []}
			var where: Array = findings[fkey]["where"]
			if where.size() < 4:
				where.append("%s/%s" % [entry["scene"], entry["node"]])

	print("OUT checked=", checked, " skipped_unknown_class=", skipped,
		" distinct_findings=", findings.size())

	var keys: Array = findings.keys()
	keys.sort()
	for k: String in keys:
		var f: Dictionary = findings[k]
		print("OUT MISSING ", f["prop"], "  on ", f["type"],
			("" if f["script"].is_empty() else " + " + f["script"].get_file()))
		for w: String in f["where"]:
			print("OUT      at ", w)

	quit()

## Property names Godot builds at runtime through _get_property_list() or
## _validate_property(), which ClassDB does not know about - per-item entries on
## OptionButton/PopupMenu, per-joint tuning on PhysicalBone3D, AudioStreamPlayer
## playback parameters, and so on. They are real properties that would all be
## reported missing, so they are filtered here rather than each becoming a
## finding to re-dismiss on every run.
const DYNAMIC_PREFIXES: Array[String] = [
	"metadata/", "libraries/", "next/", "theme_override", "shader_parameter/",
	"input/", "bones/", "surface_material_override/", "autoplay/", "popup/",
	"item_", "joint_constraints/", "parameters/", "blend_shapes/",
]

## Exact names in the same category as DYNAMIC_PREFIXES.
const DYNAMIC_NAMES: Array[String] = [
	"bone_name", "blend_times",
]

func _is_dynamic(prop: String) -> bool:
	if DYNAMIC_NAMES.has(prop):
		return true
	for prefix: String in DYNAMIC_PREFIXES:
		if prop.begins_with(prefix):
			return true
	return false

## Every property name reachable on [param type] plus [param script_path]'s
## whole inheritance chain.
func _valid_properties(type: String, script_path: String) -> Dictionary:
	var out: Dictionary = {}

	if not type.is_empty() and ClassDB.class_exists(type):
		for p: Dictionary in ClassDB.class_get_property_list(type):
			out[p["name"]] = true

	if not script_path.is_empty() and ResourceLoader.exists(script_path):
		var script := load(script_path) as Script
		while script != null:
			for p: Dictionary in script.get_script_property_list():
				out[p["name"]] = true
			# A script's own base class contributes too when the scene node
			# type is unknown (an override inside an instance, say).
			var base: String = script.get_instance_base_type()
			if not base.is_empty() and ClassDB.class_exists(base):
				for p: Dictionary in ClassDB.class_get_property_list(base):
					out[p["name"]] = true
			script = script.get_base_script()

	return out
