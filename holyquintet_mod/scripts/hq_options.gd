extends Node
## Ports funkin.options.Options — the real engine's settings singleton, kept
## in a SEPARATE save file from FlxG.save.data (that's HQSaves here) because
## the real Options class has its own FlxSave ("Options.__save"), distinct
## from the mod's own save. Only the fields HQSettings.hx's own option lists
## actually expose are ported — the real Options class has dozens more
## (editor/charter/QoL settings) with no UI anywhere in this port to reach
## them.
##
## Defaults are the real static field initializers in Options.hx, NOT the
## `defaultValue` written on each entry in HQSettings.hx's own option list
## dictionaries — those are frequently wrong there (several int/float
## entries literally say `defaultValue: false`, a copy-paste leftover from
## the bool entries above them; SettingOptionUI.hx never even reads
## `data.defaultValue` at runtime, only `Reflect.field(Options,
## data.parentValue)|, so those typos are harmless in the real game and
## would only mislead a port that trusted them).
##
## middleScroll/strumUnderlayAlpha/playerStrumScale/resetButtonEnabled/
## mechanics aren't in the base engine's Options.hx at all — they're this
## mod's own extension fields (confirmed real: read directly as
## Options.middleScroll etc. by vexation.hx, Standard.hx, Bullet/Timestop
## Note.hx, Gameplay Configuration.hx), whose own default-value definition
## lives wherever that extension class is, which isn't part of the
## extracted source this port has. Defaulted here to whatever value makes
## the option a no-op (false/0/the slider's own lower bound) — a reasonable
## stand-in, not a verified real default.

const SAVE_PATH := "user://hq_options.json"

# Controls (keyboard-only, matching the real feature exactly — no gameplay
# state exists yet anywhere in this port to actually consume these binds).
var p1_note_left: String = "A"
var p1_note_down: String = "S"
var p1_note_up: String = "W"
var p1_note_right: String = "D"
var p1_left: String = "A"
var p1_down: String = "S"
var p1_up: String = "W"
var p1_right: String = "D"
var p1_dodge: String = "Space"
var p1_accept: String = "Enter"
var p1_back: String = "Backspace"
var p1_pause: String = "Enter"

# Gameplay
var downscroll: bool = false
var middle_scroll: bool = false
var strum_underlay_alpha: int = 0
var player_strum_scale: float = 1.0
var player_strum_speed: float = 1.0
var cam_zoom_on_beat: bool = true
var song_offset: int = 0
var reset_button_enabled: bool = true
var streamed_music: bool = true
var streamed_vocals: bool = false

# Visuals
var flashing_lights: bool = false
var gameplay_shaders: bool = true
var gpu_only_bitmaps: bool = true
var antialiasing: bool = true
var low_memory_mode: bool = false
var splashes_enabled: bool = true
var framerate: int = 120

# Language — stub, see settings_screen.gd's own header comment: no i18n
# system exists in this port yet, so this is saved/shown but retranslates
# nothing (same deliberate scope cut as GameJolt/HQSHOP elsewhere).
var language: String = "en_US"

# Other
var mechanics: bool = true


func _ready() -> void:
	load_data()


func save_data() -> void:
	var data := {
		"p1_note_left": p1_note_left, "p1_note_down": p1_note_down,
		"p1_note_up": p1_note_up, "p1_note_right": p1_note_right,
		"p1_left": p1_left, "p1_down": p1_down, "p1_up": p1_up, "p1_right": p1_right,
		"p1_dodge": p1_dodge, "p1_accept": p1_accept, "p1_back": p1_back, "p1_pause": p1_pause,
		"downscroll": downscroll, "middle_scroll": middle_scroll,
		"strum_underlay_alpha": strum_underlay_alpha,
		"player_strum_scale": player_strum_scale, "player_strum_speed": player_strum_speed,
		"cam_zoom_on_beat": cam_zoom_on_beat, "song_offset": song_offset,
		"reset_button_enabled": reset_button_enabled,
		"streamed_music": streamed_music, "streamed_vocals": streamed_vocals,
		"flashing_lights": flashing_lights, "gameplay_shaders": gameplay_shaders,
		"gpu_only_bitmaps": gpu_only_bitmaps, "antialiasing": antialiasing,
		"low_memory_mode": low_memory_mode, "splashes_enabled": splashes_enabled,
		"framerate": framerate, "language": language, "mechanics": mechanics,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	p1_note_left = str(data.get("p1_note_left", p1_note_left))
	p1_note_down = str(data.get("p1_note_down", p1_note_down))
	p1_note_up = str(data.get("p1_note_up", p1_note_up))
	p1_note_right = str(data.get("p1_note_right", p1_note_right))
	p1_left = str(data.get("p1_left", p1_left))
	p1_down = str(data.get("p1_down", p1_down))
	p1_up = str(data.get("p1_up", p1_up))
	p1_right = str(data.get("p1_right", p1_right))
	p1_dodge = str(data.get("p1_dodge", p1_dodge))
	p1_accept = str(data.get("p1_accept", p1_accept))
	p1_back = str(data.get("p1_back", p1_back))
	p1_pause = str(data.get("p1_pause", p1_pause))
	downscroll = bool(data.get("downscroll", downscroll))
	middle_scroll = bool(data.get("middle_scroll", middle_scroll))
	strum_underlay_alpha = int(data.get("strum_underlay_alpha", strum_underlay_alpha))
	player_strum_scale = float(data.get("player_strum_scale", player_strum_scale))
	player_strum_speed = float(data.get("player_strum_speed", player_strum_speed))
	cam_zoom_on_beat = bool(data.get("cam_zoom_on_beat", cam_zoom_on_beat))
	song_offset = int(data.get("song_offset", song_offset))
	reset_button_enabled = bool(data.get("reset_button_enabled", reset_button_enabled))
	streamed_music = bool(data.get("streamed_music", streamed_music))
	streamed_vocals = bool(data.get("streamed_vocals", streamed_vocals))
	flashing_lights = bool(data.get("flashing_lights", flashing_lights))
	gameplay_shaders = bool(data.get("gameplay_shaders", gameplay_shaders))
	gpu_only_bitmaps = bool(data.get("gpu_only_bitmaps", gpu_only_bitmaps))
	antialiasing = bool(data.get("antialiasing", antialiasing))
	low_memory_mode = bool(data.get("low_memory_mode", low_memory_mode))
	splashes_enabled = bool(data.get("splashes_enabled", splashes_enabled))
	framerate = int(data.get("framerate", framerate))
	language = str(data.get("language", language))
	mechanics = bool(data.get("mechanics", mechanics))


## Real DestroySaveData does Options.__save.erase() separately from
## FlxG.save.erase() — this port's equivalent split (HQOptions vs HQSaves).
func erase_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
