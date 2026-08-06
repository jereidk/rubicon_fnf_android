class_name LullabySettings
extends Node

## Autoload matching Lullaby's real LullabySettings
## (lullaby_mod/scripts/lullaby/settings/lullaby_settings.gd), so the ported
## Cabinet of Novelties console settings screens work against real property
## names via Settings.get(property)/Settings.set(property, value).
##
## The key_bindings block below is Rubicon's own First Boot Settings screen
## (2D onboarding), kept separate from Lullaby's graphics_/audio_/game_
## properties since it predates this port. Its quality preset picker uses
## the same LullabyQualityPreset resources as the full console instead of
## its own separate system now - see PRESET_VERY_LOW etc. below.

signal applied
signal volume_changed(bus: StringName, value: float)

# --- First Boot Settings (Rubicon's onboarding screen) ---

signal key_binding_changed(lane: int, keycode: Key)
signal special_binding_changed(keycode: Key)

var key_bindings: Dictionary = {
	0: KEY_Z,
	1: KEY_F,
	2: KEY_J,
	3: KEY_K,
}
var special_binding: Key = KEY_SPACE

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
const PRESET_VERY_LOW: LullabyQualityPreset = preload("res://lullaby_mod/resources/quality_presets/qol_very_low.tres")

const DEFAULT_GAME_INPUTS: RubiconLevelNoteInputMap = preload("res://addons/rubicon_mania/resources/default_input_map.tres")
const INPUT_EXCLUSIONS: Array[StringName] = [
	&"ui_accept", &"ui_select", &"ui_cancel", &"ui_left", &"ui_right", &"ui_up", &"ui_down",
	&"ui_focus_next", &"ui_focus_prev", &"ui_page_up", &"ui_page_down", &"ui_home", &"ui_end",
	# Not a remappable gameplay binding - keep these on whatever project.godot
	# defines (desktop keyboard stand-ins + KEY_VOLUMEUP/DOWN/MUTE, which is
	# what Android's hardware volume rocker actually sends) rather than
	# freezing them into a player's settings.ini the first time it's written,
	# which would silently drop any future default binding added here.
	&"volume_up", &"volume_down", &"volume_mute",
]

enum PostProcessing { NONE = 0, LOW = 1, HIGH = 2 }

## Rubicon addition: how touch devices control free-look (e.g. the Cabinet
## of Novelties shop). Not part of the original (keyboard/mouse-only) mod.
enum TouchLookScheme { DRAG_ZONES = 0, JOYSTICK = 1 }

var display_window_mode: Window.Mode = Window.Mode.MODE_FULLSCREEN
var display_resolution: Vector2i = Vector2i(1366, 768)
var display_vsync: DisplayServer.VSyncMode = DisplayServer.VSyncMode.VSYNC_DISABLED
var display_target_fps: int = 60

## Matches project.godot's window/stretch/aspect. KEEP ("Normal") locks the
## aspect ratio to the design resolution's 16:9 and pillarboxes the rest;
## EXPAND ("Wide") instead fills a wide screen's extra width with more game
## world. Expand is the desktop-intended look and used to be the default, but
## on a phone it hands the player more world than the stages were authored to
## cover - Chimera's is visibly broken by it - so Normal is the default now
## and Wide is an opt-in in the console's Mobile section.
var display_screen_aspect: Window.ContentScaleAspect = Window.ContentScaleAspect.CONTENT_SCALE_ASPECT_KEEP

var graphics_scaling_mode: Viewport.Scaling3DMode = Viewport.Scaling3DMode.SCALING_3D_MODE_BILINEAR
var graphics_render_scale: float = 1.0
var graphics_fsr_sharpness: float = 1.0
var graphics_shadows_enabled: bool = true
var graphics_positional_shadow_atlas_size: int = 4096
var graphics_positional_shadow_filter_quality: int = 2
var graphics_screen_space_aa_quality: Viewport.ScreenSpaceAA = Viewport.ScreenSpaceAA.SCREEN_SPACE_AA_SMAA
var graphics_msaa_3d_quality: Viewport.MSAA = Viewport.MSAA.MSAA_4X
var graphics_ssao: bool = true
var graphics_ssil: bool = true
var graphics_post_processing: PostProcessing = PostProcessing.HIGH
var graphics_disable_shader_effects: bool = false

## Decorative/post-processing shaders only - screen distortions, blur, CRT/
## NTSC noise, glow, color grading, weather. Deliberately excludes shaders
## that ARE a node's base appearance rather than an effect layered on top of
## one (shd_cell's console toon shading, shd_dissolve's cartridge/console
## dissolve-in animation, shd_single_unown_eye's eye rendering,
## rgb_color_replacement/shd_simple_color_replace's functional note/splash
## recoloring) - stripping those would leave meshes flat white or notes
## wrongly colored instead of just running leaner.
##
## Two entries were removed from this list after Very Low was seen on device:
##
## - shd_shop_static_spatial is "smoke for the shop cubes". It is assigned as
##   surface_material_override 1/2/3 on the shop's glass cubes, so it IS their
##   appearance - the purple smoke (base_color 0.337,0.043,0.344) is all there
##   is inside them. Stripping it left the cubes flat white. It is also no
##   longer expensive: the 12 procedural snoise() evaluations were already
##   replaced with a single baked-noise texture lookup.
## - shd_uv_appear is the notepad's Page Display material_override, unshaded,
##   sampling the page texture - stripping it left a blank white page.
##
## The rule this encodes: a ShaderMaterial reached through material_override
## or a surface override is a candidate for being the only material a mesh
## has. _strip_surface_shader_material()/_strip_shader_material_property()
## now refuse to strip when nothing would be left underneath, but the list
## itself should still only name true effect layers.
const EFFECT_SHADER_PATHS: Array[String] = [
	"res://lullaby_mod/resources/shaders/blend_modes/shd_blend_modes.gdshader",
	"res://lullaby_mod/resources/shaders/blur/shd_radial_blur.gdshader",
	"res://lullaby_mod/resources/shaders/color/shd_contrast.gdshader",
	"res://lullaby_mod/resources/shaders/color/shd_hsv.gdshader",
	"res://lullaby_mod/resources/shaders/distortion/shd_trance_water_hsv_contrast.gdshader",
	"res://lullaby_mod/resources/shaders/distortion/shd_water_distortion.gdshader",
	"res://lullaby_mod/resources/shaders/misc/shd_yellower.gdshader",
	"res://lullaby_mod/resources/shaders/shd_blood_arrow.gdshader",
	"res://lullaby_mod/resources/shaders/shd_crt.gdshader",
	"res://lullaby_mod/resources/shaders/shd_godrays.gdshader",
	"res://lullaby_mod/resources/shaders/shd_new_shop_prop.gdshader",
	"res://lullaby_mod/resources/shaders/shd_ntsc_shader.gdshader",
	"res://lullaby_mod/resources/shaders/shd_radialblur.gdshader",
	"res://lullaby_mod/resources/shaders/shd_rain.gdshader",
	"res://lullaby_mod/resources/shaders/shd_sepia.gdshader",
	"res://lullaby_mod/resources/shaders/shd_shopregister_glow.gdshader",
	"res://lullaby_mod/resources/shaders/static/shd_shop_static.gdshader",
]

## node -> {property_name: original Material}, so toggling the setting back
## off can restore exactly what was there rather than guessing a default.
var _stashed_shader_materials: Dictionary = {}
var _watching_new_nodes: bool = false

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
## Multiplies every judgment window (Perfect/Great/Good/.../Miss) - see
## RubiconLevelNoteSettings.leniency_multiplier. Not the same as
## game_offset above: that shifts *when* a hit is considered to land,
## this changes how *wide* the acceptance window around that point is.
var game_timing_leniency: float = 1.0
var game_flashing_lights: bool = true
var game_autoplay: bool = false
var game_speed_multiplier: float = 1.0
var game_downscroll: bool = false
var game_ghost_tapping: bool = true
var game_centered: bool = false
var game_touch_look_scheme: TouchLookScheme = TouchLookScheme.JOYSTICK

var lullaby_baby_mode: bool = false
var lullaby_showcase_mode: bool = false

## Which on-screen debug overlay LullabyFPSDisplay shows (its own
## CurrentState enum: 0 NONE / 1 VERY_SIMPLE / 2 BASIC / 3 ADVANCED).
## This used to live only as a runtime var on the display itself, cycled
## by the debug_toggle key - so it reset to VERY_SIMPLE every launch and,
## on Android, couldn't be changed at all (no keyboard to press
## debug_toggle with). Keeping it here makes it settable from the Misc
## tab and persisted like everything else - save()/load_from() pick it up
## automatically off the lullaby_ prefix.
var lullaby_debug_display: int = 1

## Writes a diagnostics log to user://logs (see
## lullaby_diagnostics_log.gd). On by default: it is quiet, costs a few
## flushed lines a minute, and is worthless if it has to be switched on
## after the problem has already happened.
var lullaby_diagnostics_log: bool = true

## 0 = Classic (the layout the songs were authored with), 1 = VSlice.
## See LullabyNoteLayout / lullaby_note_layout_applier.gd.
var lullaby_note_layout: int = 0

## Whether the player's strumline should be centred, which is midscroll's
## "centered" AnimationTree state.
##
## VSlice is not a layout that works either way: its whole arrangement assumes
## a centred player strumline, and the layout applier hands horizontal
## placement to midscroll rather than fighting the AnimationTree for it. So
## selecting VSlice turns midscroll on, and the console's Midscroll row is
## locked on while it is selected (midscroll_lock.gd).
##
## game_centered itself is deliberately not written when that happens - it
## stays as the player set it, so switching back to Classic gives them their
## own choice back rather than one VSlice made for them. Read this instead of
## game_centered anywhere the answer is "should the lanes be centred".
func is_midscroll_active() -> bool:
	return game_centered or lullaby_note_layout == 1

## Rubicon addition: the Mobile settings section (gameplay touch controls).
## All of these are plain lullaby_ vars so save()/load_from() persist them
## automatically and the quality presets keep matching on graphics_ only.

## 0 = Hitbox (the full-height lane zones), 1 = Touch (tap the falling
## notes directly). The Touch input mode itself ships separately; the
## setting and its UI exist from the start so the menu is complete.
enum MobileControlMode { HITBOX = 0, TOUCH = 1 }

## Where the pendulum mechanic's own hitbox sits: 0 = top strip (the
## original layout), 1 = bottom strip, 2 = centre band between the lanes.
enum MechanicHitboxDirection { UP = 0, BOTTOM = 1, CENTER = 2 }

var lullaby_mobile_control_mode: int = MobileControlMode.HITBOX
var lullaby_hitbox_hint: bool = true
var lullaby_hitbox_gradient: bool = true
var lullaby_hitbox_opacity: int = 100
var lullaby_mechanic_hitbox_direction: int = MechanicHitboxDirection.BOTTOM
var lullaby_touch_note_hitbox_size: float = 1.0
## Short vibration on every note hit in Touch mode. On by default because
## the tap targets are small and the buzz is the only non-visual confirm
## the mode has, but on a dense chart it is near-continuous, so it needs
## to be switchable.
var lullaby_touch_haptics: bool = true
var lullaby_show_pause_button: bool = true
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
	elif PRESET_VERY_LOW.is_matching(self):
		return PRESET_VERY_LOW

	return null

func apply_settings() -> void:
	var window: Window = get_window()

	window.mode = display_window_mode
	if window.mode != Window.MODE_FULLSCREEN:
		window.size = display_resolution

	if window.mode == Window.MODE_WINDOWED:
		window.move_to_center()

	window.content_scale_aspect = display_screen_aspect

	DisplayServer.window_set_vsync_mode(display_vsync, window.get_window_id())
	Engine.max_fps = display_target_fps

	window.scaling_3d_mode = graphics_scaling_mode
	window.scaling_3d_scale = graphics_render_scale
	window.fsr_sharpness = graphics_fsr_sharpness
	window.positional_shadow_atlas_size = graphics_positional_shadow_atlas_size if graphics_shadows_enabled else 0
	ProjectSettings.set("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", graphics_positional_shadow_filter_quality)

	window.msaa_3d = graphics_msaa_3d_quality
	window.screen_space_aa = graphics_screen_space_aa_quality

	_apply_shader_effects_setting()

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
			# Rubicon note: force "any device" on reapply. A settings.ini saved
			# before the project's [input] device ids were fixed (they were
			# bogus device=16/32 instead of -1, silently dropping every touch-
			# emulated tap and most real keyboard/mouse input against these
			# actions) would otherwise keep reintroducing that same bad device
			# id from disk forever, even after the project.godot fix.
			if "device" in input_event:
				input_event.device = -1
			InputMap.action_add_event(action_name, input_event)

	applied.emit()

## Very Low toggles this on; every other preset off. Strips the current
## tree's effect ShaderMaterials (stashing originals to restore if the
## setting flips back off) and, while on, keeps stripping any newly added
## node too - songs/menus instance plenty of shader-using nodes well after
## boot (note splashes, pendulum mechanic, chimera's rain/godrays layers).
func _apply_shader_effects_setting() -> void:
	if graphics_disable_shader_effects:
		if not _watching_new_nodes:
			get_tree().node_added.connect(_strip_effect_shaders_from_node)
			_watching_new_nodes = true
		_strip_effect_shaders(get_tree().root)
	else:
		if _watching_new_nodes:
			get_tree().node_added.disconnect(_strip_effect_shaders_from_node)
			_watching_new_nodes = false
		_restore_effect_shaders()

func _strip_effect_shaders(node: Node) -> void:
	_strip_effect_shaders_from_node(node)
	for child in node.get_children():
		_strip_effect_shaders(child)

func _strip_effect_shaders_from_node(node: Node) -> void:
	_strip_shader_material_property(node, &"material")
	_strip_shader_material_property(node, &"material_override")
	_strip_shader_material_property(node, &"material_overlay")
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			_strip_surface_shader_material(node, surface)

func _stash(node: Node, property: StringName, material: Material) -> void:
	var id: int = node.get_instance_id()
	if not _stashed_shader_materials.has(id):
		_stashed_shader_materials[id] = {}
	_stashed_shader_materials[id][property] = material

func _strip_shader_material_property(node: Node, property: StringName) -> void:
	if not (property in node):
		return
	var mat: Variant = node.get(property)
	if not (mat is ShaderMaterial and mat.shader and EFFECT_SHADER_PATHS.has(mat.shader.resource_path)):
		return

	# material_override replaces every surface material on the mesh. If the
	# mesh has nothing of its own underneath, nulling it does not "remove an
	# effect", it removes the object's only material and Godot falls back to
	# the plain white default - which is how Very Low turned the shop's
	# purple cubes and the notepad page white.
	if property == &"material_override" and node is MeshInstance3D and not _mesh_has_own_material(node):
		return

	_stash(node, property, mat)
	node.set(property, null)

func _strip_surface_shader_material(node: MeshInstance3D, surface: int) -> void:
	var mat: Material = node.get_surface_override_material(surface)
	if not (mat is ShaderMaterial and mat.shader and EFFECT_SHADER_PATHS.has(mat.shader.resource_path)):
		return
	if node.mesh.surface_get_material(surface) == null:
		return

	_stash(node, "surface_material_override/%d" % surface, mat)
	node.set_surface_override_material(surface, null)

## True when [param node] is a mesh that would still be drawn with a material
## of its own after its material_override is cleared.
func _mesh_has_own_material(node: Node) -> bool:
	if not (node is MeshInstance3D) or node.mesh == null:
		return false
	for surface in node.mesh.get_surface_count():
		if node.get_surface_override_material(surface) != null:
			return true
		if node.mesh.surface_get_material(surface) != null:
			return true
	return false

func _restore_effect_shaders() -> void:
	for id: int in _stashed_shader_materials:
		var node: Object = instance_from_id(id)
		if not is_instance_valid(node):
			continue
		for property: String in _stashed_shader_materials[id]:
			var mat: Material = _stashed_shader_materials[id][property]
			if node is MeshInstance3D and property.begins_with("surface_material_override/"):
				node.set_surface_override_material(property.get_slice("/", 1).to_int(), mat)
			else:
				node.set(property, mat)
	_stashed_shader_materials.clear()

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
