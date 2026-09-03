class_name GameOptions
extends RefCounted
## Settings persistence — faithful port of the Animania options system.
##
## All game options are stored in a JSON file at user://options.json.
## Default values match the binary's initial values.

const SAVE_PATH := "user://options.json"

## Default values for all options, read from the binary's __SetField.
## The key is the internal option name, the value is the default.
static var defaults := {
	# Gameplay
	"general_note_speed": 1.0,
	"camera_shake": true,
	"downscroll": false,
	"autopause": false,
	"open_controls": false,
	"miss_sounds_volume": 0.5,
	"hit_sounds_volume": 0.5,
	# Appearance
	"hints": true,
	"allow_shaders": true,
	"lowquality": false,
	"show_judges": true,
	"show_healthbar": true,
	"flashing_lights": true,
	"subtitles": false,
	"camera_zooming": true,
	"notesplashes": true,
	"timebar": true,
	"antialiasing": true,
	"framerate": 60,
	# Misc
	"language": "en",
	"vsync": "Adaptive",
	"haxeflixel_intro": true,
	"debug_display": false,
	"game_volume": 0.5,
	"game_mute": false,
	# Experimental
	"naughtyness": false,
	"gpu_load": false,
}

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_load()


static func _load() -> void:
	_cache = defaults.duplicate()
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			var err := json.parse(file.get_as_text())
			file.close()
			if err == OK and json.data is Dictionary:
				for key in json.data:
					_cache[key] = json.data[key]
	_loaded = true


static func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_cache, "\t"))
		file.close()


static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return _cache.get(key, defaults.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	_cache[key] = value
	_save()


static func get_float(key: String) -> float:
	return float(get_value(key))


static func get_int(key: String) -> int:
	return int(get_value(key))


static func get_bool(key: String) -> bool:
	return bool(get_value(key))


static func get_string(key: String) -> String:
	return str(get_value(key))
