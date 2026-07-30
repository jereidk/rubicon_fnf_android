@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_project_setting("rubicon_mobile_controls/enabled", TYPE_BOOL, PROPERTY_HINT_NONE, "", true)
	add_project_setting("rubicon_mobile_controls/lane_count", TYPE_INT, PROPERTY_HINT_RANGE, "1,9,1", 4)

func add_project_setting(name: String, type: Variant.Type, hint: PropertyHint, hint_string: String, default_value: Variant) -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)

	ProjectSettings.add_property_info({
		"name": name,
		"type": type,
		"hint": hint,
		"hint_string": hint_string
	})

	ProjectSettings.set_initial_value(name, default_value)
	ProjectSettings.set_as_basic(name, true)
