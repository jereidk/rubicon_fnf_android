extends SceneTree

## Every project setting Godot 4.7 exposes that touches shaders, pipelines or
## render threading, with this project's value and whether it is an override.
##
## The device log shows the shop's precache drawing exactly one frame in 35.6
## seconds, TIME_PROCESS reporting 38147ms for a single process step, and 154
## pipelines compiled in that window. Nothing in [rendering] is set in
## project.godot, so every one of these is at its default - and establishing
## which knobs actually exist in 4.7 has to come before proposing to turn any
## of them, because guessing at an API is how the last few theories died.
##
## Run with:
##   godot --headless --path . --script tools/audit_pipeline_settings.gd

const WORDS: PackedStringArray = [
	"shader", "pipeline", "thread", "ubershader", "precompil", "async", "stall",
]

func _initialize() -> void:
	print("Godot %s" % Engine.get_version_info()["string"])
	print("")

	var seen: Dictionary = {}
	for info in ProjectSettings.get_property_list():
		var name: String = info["name"]
		if seen.has(name):
			continue

		var lower: String = name.to_lower()
		var hit: bool = false
		for word in WORDS:
			if lower.contains(word):
				hit = true
				break
		if not hit:
			continue

		seen[name] = true
		var value: Variant = ProjectSettings.get_setting(name)
		print("%-70s = %-14s%s" % [
			name, str(value), "  <- project.godot" if _overridden(name, value) else "",
		])

	print("")
	print("total: %d ajustes" % seen.size())
	quit(0)

## Whether the value differs from what the engine ships, so an override shows.
func _overridden(name: String, value: Variant) -> bool:
	var initial: Variant = ProjectSettings.property_get_revert(name)
	return initial != null and initial != value
