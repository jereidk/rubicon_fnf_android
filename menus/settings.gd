class_name LullabySettings
extends Node

## Autoload matching Lullaby's real LullabySettings
## (lullaby_mod/scripts/lullaby/settings/lullaby_settings.gd), so the ported
## Cabinet of Novelties console settings screens work against real property
## names via Settings.get(property)/Settings.set(property, value).
##
## The QualityPreset enum/apply_quality_preset()/key_bindings block below is
## Rubicon's own First Boot Settings screen (2D onboarding), kept separate
## from Lullaby's graphics_/audio_/game_ properties since it predates this
## port and First Boot Settings is deliberately simpler than the full console.

signal applied
signal volume_changed(bus: StringName, value: float)

# --- First Boot Settings (Rubicon's onboarding screen) ---

enum QualityPreset { CUSTOM, LOW, MEDIUM, HIGH }

signal key_binding_changed(lane: int, keycode: Key)
signal special_binding_changed(keycode: Key)

var quality_preset: QualityPreset = QualityPreset.HIGH

var key_bindings: Dictionary = {
	0: KEY_Z,
	1: KEY_F,
	2: KEY_J,
	3: KEY_K,
}
var special_binding: Key = KEY_SPACE

func apply_quality_preset(preset: QualityPreset) -> void:
	quality_preset = preset
	match preset:
		QualityPreset.LOW:
			get_viewport().msaa_2d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		QualityPreset.MEDIUM:
			get_viewport().msaa_2d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		QualityPreset.HIGH:
			get_viewport().msaa_2d = Viewport.MSAA_2X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

func set_key_binding(lane: int, keycode: Key) -> void:
	key_bindings[lane] = keycode
	key_binding_changed.emit(lane, keycode)
	if RubiconTouchInput.lane_to_keycode.has(lane):
		RubiconTouchInput.lane_to_keycode[lane] = keycode

func set_special_binding(keycode: Key) -> void:
	special_binding = keycode
	special_binding_changed.emit(keycode)

func key_name(keycode: Key) -> String:
	return OS.get_keycode_string(keycode)

# --- Real Lullaby settings (Cabinet of Novelties console) ---

const SAVE_PATH: String = "user://settings.ini"

const MASTER_VOLUME_BUS: int = 0
const MUSIC_VOLUME_BUS: int = 1
const SOUND_EFFECTS_VOLUME_BUS: int = 2
const VOCALS_VOLUME_BUS: int = 3

const PRESET_HIGH: LullabyQualityPreset = preload("res://lullaby_mod/resources/quality_presets/qol_high.tres")
const PRESET_MEDIUM: LullabyQualityPreset = preload("res://lullaby_mod/resources/quality_presets/qol_medium.tres")
const PRESET_LOW: LullabyQualityPreset = preload("res://lullaby_mod/resources/quality_presets/qol_low.tres")

const DEFAULT_GAME_INPUTS: RubiconLevelNoteInputMap = preload("res://addons/rubicon_mania/resources/default_input_map.tres")
const INPUT_EXCLUSIONS: Array[StringName] = [
	&"ui_accept", &"ui_select", &"ui_cancel", &"ui_left", &"ui_right", &"ui_up", &"ui_down",
	&"ui_focus_next", &"ui_focus_prev", &"ui_page_up", &"ui_page_down", &"ui_home", &"ui_end",
]

enum PostProcessing { NONE = 0, LOW = 1, HIGH = 2 }

var display_window_mode: Window.Mode = Window.Mode.MODE_FULLSCREEN
var display_resolution: Vector2i = Vector2i(1366, 768)
var display_vsync: DisplayServer.VSyncMode = DisplayServer.VSyncMode.VSYNC_DISABLED
var display_target_fps: int = 60

var graphics_scaling_mode: Viewport.Scaling3DMode = Viewport.Scaling3DMode.SCALING_3D_MODE_BILINEAR
var graphics_render_scale: float = 1.0
var graphics_fsr_sharpness: float = 1.0
var graphics_positional_shadow_atlas_size: int = 4096
var graphics_positional_shadow_filter_quality: int = 2
var graphics_screen_space_aa_quality: Viewport.ScreenSpaceAA = Viewport.ScreenSpaceAA.SCREEN_SPACE_AA_SMAA
var graphics_msaa_3d_quality: Viewport.MSAA = Viewport.MSAA.MSAA_4X
var graphics_ssao: bool = true
var graphics_ssil: bool = true
var graphics_post_processing: PostProcessing = PostProcessing.HIGH

var audio_master_volume: float = 1.2:
	set(v):
		v = clampf(v, 0, 1.2)
		if audio_master_volume != v:
			audio_master_volume = v
			volume_changed.emit(&"Master", v)

var audio_music_volume: float = 1.0:
	set(v):
		v = clampf(v, 0, 1.0)
		if audio_music_volume != v:
			audio_music_volume = v
			volume_changed.emit(&"Music", v)

var audio_sfx_volume: float = 1.0:
	set(v):
		v = clampf(v, 0, 1.0)
		if audio_sfx_volume != v:
			audio_sfx_volume = v
			volume_changed.emit(&"SoundEffects", v)

var audio_vox_volume: float = 1.0:
	set(v):
		v = clampf(v, 0, 1.0)
		if audio_vox_volume != v:
			audio_vox_volume = v
			volume_changed.emit(&"Voice", v)

var game_offset: float = 0.0
var game_visual_offset: float = 0.0
var game_flashing_lights: bool = true
var game_autoplay: bool = false
var game_speed_multiplier: float = 1.0
var game_downscroll: bool = false
var game_ghost_tapping: bool = true
var game_centered: bool = false

var lullaby_baby_mode: bool = false

var input_game: Dictionary = {}
var input_map: Dictionary = {}

var _level_note_inputs: RubiconLevelNoteInputMap = RubiconLevelNoteInputMap.new()

func _ready() -> void:
	if load_from(SAVE_PATH) == ERR_FILE_NOT_FOUND:
		reset_input_map()
		save(SAVE_PATH)

	apply_settings()

func _input(event: InputEvent) -> void:
	if event.is_pressed() and event.is_action(&"fullscreen_toggle"):
		var window: Window = get_window()

		if display_window_mode != Window.MODE_FULLSCREEN:
			display_window_mode = Window.MODE_FULLSCREEN
		else:
			display_window_mode = Window.MODE_WINDOWED

		save(SAVE_PATH)

		window.mode = display_window_mode

		if window.mode == Window.MODE_WINDOWED:
			window.size = display_resolution
			window.move_to_center()

func get_level_note_inputs() -> RubiconLevelNoteInputMap:
	return _level_note_inputs

func get_quality_preset() -> LullabyQualityPreset:
	if PRESET_HIGH.is_matching(self):
		return PRESET_HIGH
	elif PRESET_MEDIUM.is_matching(self):
		return PRESET_MEDIUM
	elif PRESET_LOW.is_matching(self):
		return PRESET_LOW

	return null

func apply_settings() -> void:
	var window: Window = get_window()

	window.mode = display_window_mode
	if window.mode != Window.MODE_FULLSCREEN:
		window.size = display_resolution

	if window.mode == Window.MODE_WINDOWED:
		window.move_to_center()

	DisplayServer.window_set_vsync_mode(display_vsync, window.get_window_id())
	Engine.max_fps = display_target_fps

	window.scaling_3d_mode = graphics_scaling_mode
	window.scaling_3d_scale = graphics_render_scale
	window.fsr_sharpness = graphics_fsr_sharpness
	window.positional_shadow_atlas_size = graphics_positional_shadow_atlas_size
	ProjectSettings.set("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", graphics_positional_shadow_filter_quality)

	window.msaa_3d = graphics_msaa_3d_quality
	window.screen_space_aa = graphics_screen_space_aa_quality

	AudioServer.set_bus_volume_linear(MASTER_VOLUME_BUS, audio_master_volume)
	AudioServer.set_bus_volume_linear(MUSIC_VOLUME_BUS, audio_music_volume)
	AudioServer.set_bus_volume_linear(SOUND_EFFECTS_VOLUME_BUS, audio_sfx_volume)

	_level_note_inputs.inputs.clear()
	for action_name: StringName in input_game:
		for input_event: InputEvent in input_game[action_name]:
			_level_note_inputs.inputs[input_event] = action_name

	for action_name: StringName in input_map:
		InputMap.action_erase_events(action_name)
		for input_event: InputEvent in input_map[action_name]:
			InputMap.action_add_event(action_name, input_event)

	applied.emit()

func get_input_name(action: StringName) -> String:
	if not input_map.has(action):
		return ""

	for event in input_map[action]:
		return event.as_text()

	return ""

func reset_input_map() -> void:
	input_map.clear()
	input_game.clear()

	for input_action: InputEvent in DEFAULT_GAME_INPUTS.inputs:
		var value: StringName = DEFAULT_GAME_INPUTS.inputs[input_action]

		if not input_game.has(value):
			input_game[value] = []

		input_game[value].append(input_action)

	for action_name: StringName in InputMap.get_actions():
		if INPUT_EXCLUSIONS.has(action_name):
			continue
		if String(action_name).begins_with("ui_"):
			continue

		var input_events: Array = InputMap.action_get_events(action_name)
		input_map[action_name] = input_events

func save(path: String = SAVE_PATH) -> void:
	var config: ConfigFile = ConfigFile.new()

	var property_list: Array = get_script().get_script_property_list()
	for property in property_list:
		var property_name: String = property["name"]
		if not property_name.begins_with("graphics_") and not property_name.begins_with("audio_") \
			and not property_name.begins_with("game_") and not property_name.begins_with("display_") \
			and not property_name.begins_with("lullaby_") and property_name != "input_map" and property_name != "input_game":
			continue

		var section: String = property_name.substr(0, property_name.find("_"))
		var setting: String = property_name.substr(property_name.find("_") + 1)
		config.set_value(section, setting, get(property_name))

	var err: Error = config.save(path)
	if err != OK:
		ErrorHandler.show_warning("Settings could not be flushed to disk.", err)

func load_from(path: String = SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND

	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(path)

	if err != OK:
		return err

	reset_input_map()

	for section in config.get_sections():
		for key in config.get_section_keys(section):
			var property_name: StringName = "%s_%s" % [section, key]

			if property_name == "input_map":
				var map_input: Dictionary = config.get_value(&"input", &"map")
				for input in map_input:
					input_map[input] = map_input[input]
				continue

			if property_name in self:
				set(property_name, config.get_value(section, key))

	return OK
