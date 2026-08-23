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
## Frame rate cap. A real number is used as-is, 0 is unlimited, and
## TARGET_FPS_NATIVE follows whatever the display is actually running at.
var display_target_fps: int = 60

## display_target_fps value meaning "match the screen".
##
## -1 rather than a plausible rate, so it can never collide with a real one:
## the row already offers 30 through 240 and 0 for unlimited, and a phone set
## to 90Hz or 120Hz should follow the panel rather than have the player guess
## which of those numbers their own device is on.
##
## Resolved at apply time, not stored resolved, because the refresh rate can
## change while the game is running - Android switches panels between 60 and
## 120 on its own, and the player can change it in system settings without
## restarting the game. Settings.applied re-runs this.
const TARGET_FPS_NATIVE := -1

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

## Viewport.anisotropic_filtering_level (0 = off/1x .. 4 = 16x) and
## Viewport.mesh_lod_threshold, both of which this project had been leaving at
## the engine defaults (4x and 1.0 pixel) on every preset. They are the two
## per-pixel knobs Godot already exposes that nothing here was using, and they
## apply to the whole viewport, so they help every scene rather than one.
var graphics_anisotropic_filtering: int = 2
var graphics_mesh_lod_threshold: float = 1.0

## Multiplier on a light's own range past which it stops being rendered, applied
## by MobileLightBudget. 0 = off, which is what High and Medium ship.
var graphics_light_distance_fade: float = 0.0

## Engine.physics_ticks_per_second. Nothing here is timing-critical on the
## physics tick (see lullaby_quality_preset.gd), and the Collector's Shop
## spends 3-6ms of a 24ms frame on Area3D overlaps with zero active bodies,
## so the low presets halve it.
var graphics_physics_ticks_per_second: int = 60
var graphics_disable_shader_effects: bool = false

## Hide lights whose contribution is already inside a scene's LightmapGI.
##
## A BAKE_STATIC light is baked into the lightmap AND still rendered in real
## time for anything the bake does not cover, so on a lightmapped scene the
## house pays for it twice. Applied by MobileLightBudget, which refuses to act
## unless the scene really has a LightmapGI with light data loaded.
var graphics_hide_baked_lights: bool = false

## Drop Burley diffuse and Schlick-GGX specular from 3D materials, which every
## one of them runs per light per fragment purely because they are Godot's
## defaults. Applied by MobileLightBudget; metallic materials keep their
## specular, since for a metal that lobe is the entire appearance.
var graphics_cheap_shading: bool = false

## Written straight through to AnimateSymbol.frame_step. See that property and
## LullabyQualityPreset.atlas_frame_step for the measurement behind it.
var graphics_atlas_frame_step: int = 1

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

## node instance id -> the BackBufferCopy.copy_mode it had before the effects
## setting disabled it. See _strip_backbuffer_copy().
var _stashed_copy_modes: Dictionary = {}

## Nodes this setting hid because, with their effect shader gone, they draw
## nothing at all. Kept apart from _stashed_shader_materials for the same
## reason _stashed_copy_modes is: its restore loop assigns Materials back.
var _stashed_visibility: Dictionary = {}
var _watching_new_nodes: bool = false

## The shadow state apply_settings() last actually sent to the engine.
##
## Deliberately impossible starting values, so the first apply always writes:
## an atlas size is never negative and neither is a filter quality.
var _applied_shadow_atlas_size: int = -1
var _applied_shadow_filter_quality: int = -1
## Same, for the SubViewport render scale.
var _watching_new_viewports: bool = false

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

## The driver's pipeline cache UUID as of the last session that finished a
## load, so a cold cache can be told from a warm one.
##
## Not a "have they played before" flag, because that is not the question. Two
## logs from the same Redmi on 10154-8d1ee1ac, same build, two launches:
##
##     arranque 1   tienda: 52014ms de carga + 30089ms de precache = 82s
##     arranque 2   tienda:  5998ms de carga +  1270ms de precache =  7s
##
## with `bench` comparable in both windows, so it is not the governor - it is
## the driver's shader cache, which survives the app closing. The pipeline
## COUNT is the same in both (233 against 243), which is the other half of the
## lesson: Godot counts pipeline creations, not cache misses.
##
## So the first launch after installing costs a minute and a half of loading
## screen and every launch after that costs seven seconds. Keying on the
## driver UUID rather than a boolean also covers the case a boolean would miss:
## a driver update invalidates the cache, and the next launch is slow again.
##
## Written at boot rather than after the first heavy load. If the player kills
## the app mid-load the notice will not show again, but by then the driver has
## already cached most of what it compiled, so that launch really is faster -
## the inaccuracy is in the message, not in what it describes.
var lullaby_shader_cache_uuid: String = ""

var lullaby_baby_mode: bool = false
var lullaby_showcase_mode: bool = false

## Plays the whole song faster or slower. Not the same as
## game_speed_multiplier above, which only changes how fast the notes travel
## toward you: here the chart, the music and everything keyed to the song
## move together, so the song really is at a different tempo.
##
## Applied by lullaby_song_settings.gd. Deliberately does NOT touch the
## judgment windows - they are in milliseconds of song time, so at 1.5x a
## Perfect is 1.5x harder to land in real time and at 0.5x it is easier,
## which is the entire point of practising with it.
##
## A short list rather than a slider: easier to hit on a phone, and every
## value is an exact binary fraction, so what is written to the save file
## comes back matching an entry in the list instead of landing between two
## (ListButton looks the current value up with values_list.find()).
var lullaby_speed_hack: float = 1.0

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

## Let the diagnostics log split the GPU frame into lighting, fill and the
## rest, by re-rendering two frames per sample through Viewport.debug_draw.
##
## **Off at every launch, and never persisted**, with a row in the console's
## Misc tab right under Diagnostics Log to turn it on for a measurement pass.
##
## It shipped off, twice over the wrong reason. First as a cheat code on
## "a diagnostic is not a preference" - wrong on its own terms, since the
## master switch for this whole log is a row six lines above it. Then as an
## opt-in row, on the cost of the debug frames. That is the weaker argument:
## **an instrument that needs someone to remember it is an instrument that
## does not run.** This session lost two device passes to exactly that -
## hide_baked_lights never executed once because of a bug nobody could see
## without the log, and the log did not carry the field that would have shown
## it.
##
## What made it affordable by default was alternating the two passes instead of
## doing both per sample: **one** wrong frame every 20 seconds, not two, and
## `debug_draw` only reaches the 3D pass, so that frame is the world going
## flat-albedo (or additive) for 33ms with the HUD untouched. That was argued
## as "a single-frame blink, not a flash".
##
## **It is a flash, and the player found it before we did.** Reported off the
## 27868ddd build, unprompted and without knowing this existed: "hay ocasiones
## que en el 3D, tanto en la tienda como tambien en chimera, hay una especie de
## flash blanco opaco... aparece en ocasiones y molesta, se ve feo". Both 3D
## scenes, occasional, bright - which is a 20-second period, a camera check,
## and `DEBUG_DRAW_UNSHADED` throwing away the lighting on a scene whose whole
## look is dark.
##
## **Changing the default did not turn it off, and this is why the name has no
## prefix.** It shipped as `lullaby_diagnostics_gpu_split`, and every var with
## one of save()'s five prefixes is written to settings.ini and read back by
## load_from(). So the phone that had already run the on-by-default build had
## `[lullaby] diagnostics_gpu_split=true` on disk, load_from() restored it over
## the new default on the next launch, and the flash carried on exactly as
## before - "el destello blanco sigue". The next device log settled it in its
## own header: `gpu_split : on`, fifteen samples, 133s to 484s, spread across
## the shop and Chimera, seven of them the UNSHADED pass. A default is not a
## fix for anything already persisted.
##
## Unprefixed, so it is not saved and not loaded: off at every launch, on for as
## long as the console row says so and no longer. Old settings.ini files carry
## the dead `[lullaby] diagnostics_gpu_split` key, which load_from() skips
## because the property no longer exists - no migration needed, and the flash
## stops on installs that already have the key.
##
## The concern that turned it on stands and is handled differently: a log with
## no GPUSPLIT lines used to be indistinguishable from an instrument nobody
## remembered to switch on, so the header states the switch either way
## (`gpu_split:` in the log preamble). Absence is loud instead of silent, and
## nothing has to be paid for in frames the player sees.
##
## It is the only instrument that can tell "Chimera is per-fragment lighting"
## from "Chimera is 3D overdraw": both fit a single gpu= number and neither
## could be ruled out from one. Turn it on from the console row for a
## measurement pass; it turns itself off when the game is next launched.
var diagnostics_gpu_split: bool = false

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

## Global multiplier on in-game camera/sprite shake, as a percent.
##
## Pairs with game_flashing_lights: the same reason exists for shake. A
## jumpscare that throws the whole screen around reads very differently in a
## hand than it does on a monitor, and there was no way to turn it down.
##
## Scales the three real shakes - CameraShake2D (Monochrome's jumpscare
## camera), SpriteShake2D and Peepers' violent parent shake. Deliberately
## not the two [shake] BBCode text effects (specialkey.gd,
## text_collector_effect.gd): those are typography, not the screen moving,
## and killing them would just make the prompts look broken. Nor Chimera's
## pause-menu shaky camera, which is a menu's style rather than a jolt.
var lullaby_screen_shake: int = 100

## 24-hour clock on the console's Memory Card header, which otherwise
## hardcodes am/pm (see time.gd).
var lullaby_clock_24h: bool = false

## UI language. Every static label's `text` is authored in English, and
## Godot auto-translates a Control's text/tooltip against whatever locale
## TranslationServer is set to - "en" (or any locale with no matching
## Translation resource) falls straight back to that authored English, no
## file needed. "es" resolves against
## lullaby_mod/resources/localization/ui_strings.es.translation, a CSV-
## sourced Translation keyed on the literal English source strings. A
## handful of dynamically-built strings (hacks_tab.gd's messages, the
## results screen, ...) call tr() explicitly for the same reason auto-
## translate can't reach them: the value assigned already has the format
## arguments substituted in, so it would never match a CSV key.
var lullaby_language: String = "en"

## Play the Collector's welcome - the "HELLO AND WELCOME! TO THE CABINET OF
## NOVELTIES!" tour he gives on your first visit - every time you enter the
## shop, rather than only on the visit where SaveData's "intro_seen" flag is
## still false.
##
## A Setting rather than just clearing that flag, because the flag means two
## things at once: env_collector_shop.gd uses it to decide whether to play
## sequence_intro, and EntryVoicelines.gd uses it to decide whether you are a
## returning visitor at all (it stays silent while the intro has never been
## seen). Clearing it to re-watch the tour would therefore also mute the
## entry voicelines from then on, which is not what "play the intro again"
## should mean.
##
## **Once per launch, not once per visit.** This used to be read directly by
## the shop, which runs that check in its `_ready` - so the 152-second tour
## replayed every single time the room loaded, including walking back in after
## finishing a song. `force_shop_intro_pending` below is what the shop actually
## consumes; this is only the stored preference that arms it at boot.
var lullaby_force_shop_intro: bool = false

## The armed, one-shot form of the preference above: true from launch until the
## shop plays the forced tour, then false for the rest of the session.
##
## No `lullaby_`/`graphics_`/`audio_`/`game_`/`display_` prefix on purpose, so
## `save()` skips it - it is session state, not a setting, and persisting it
## would put the replay back on every visit through the back door.
var force_shop_intro_pending: bool = false

## Which keyboard Monochrome's typing mechanic uses.
##
## SYSTEM focuses a hidden LineEdit, which is what makes Android raise the
## player's own keyboard - their layout, language, autocorrect and swipe.
## IN_GAME draws the game's own keys instead, for players whose keyboard
## covers too much of the screen or whose suggestion strip fights the song.
##
## Showcase Mode ignores this and always uses IN_GAME: the system keyboard
## belongs to another app, so nothing can show its keys being pressed, and
## raising it over a showcase would cover the song. See
## monochrome_typing_touch_controls.gd.
enum MobileKeyboardType { SYSTEM = 0, IN_GAME = 1 }

var lullaby_mobile_keyboard_type: int = MobileKeyboardType.SYSTEM
var input_game: Dictionary = {}
var input_map: Dictionary = {}

var _level_note_inputs: RubiconLevelNoteInputMap = RubiconLevelNoteInputMap.new()

## Latched once at boot: whether the driver's shader cache is cold for this
## build+driver, and so whether this session pays the first-run compile.
##
## Read by the loading screen. See lullaby_shader_cache_uuid for the numbers.
var shader_cache_cold: bool = false

func _ready() -> void:
	if load_from(SAVE_PATH) == ERR_FILE_NOT_FOUND:
		reset_input_map()
		save(SAVE_PATH)

	# Arm the forced intro for this launch. The shop disarms it the first time
	# it plays the tour, so the preference means "once when I start the game",
	# not "every time I walk into the room".
	force_shop_intro_pending = lullaby_force_shop_intro

	_check_shader_cache()
	apply_settings()

## Compares the driver's pipeline cache UUID against the one stored, latches
## the answer, and stores the new one.
##
## Guarded for a null RenderingDevice - GL Compatibility has none - in which
## case nothing is claimed and the notice never shows.
func _check_shader_cache() -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	if device == null:
		return

	var uuid: String = device.get_device_pipeline_cache_uuid()
	if uuid.is_empty():
		return

	shader_cache_cold = uuid != lullaby_shader_cache_uuid
	if shader_cache_cold:
		lullaby_shader_cache_uuid = uuid
		save(SAVE_PATH)

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
	Engine.max_fps = _resolved_target_fps()

	window.scaling_3d_mode = graphics_scaling_mode
	window.scaling_3d_scale = graphics_render_scale
	_apply_subviewport_render_scale()

	# A static on the addon, so this reaches every AnimateSymbol including the
	# ones built at runtime, with nothing to wire per node and no walk of the
	# tree. The addon never reads Settings back - it stays free of the mod's
	# singletons - so this is the only writer.
	AnimateSymbol.frame_step = graphics_atlas_frame_step
	window.fsr_sharpness = graphics_fsr_sharpness
	# Only when they actually moved, and this is the one block in here that
	# needs saying so.
	#
	# Every settings row calls apply_settings() the moment it is touched -
	# list_button, toggle_button, incremental_button, input_button and
	# quality_preset_button all do - and the reported symptom is that changing
	# anything hitches, "sin importar magnitud". That is the shape of a cost
	# belonging to the re-apply rather than to the setting.
	#
	# The device log names it: a settings change compiles 35 render pipelines,
	# and the breakdown is identical every time - surf+6 draw+13 spec+16 - so
	# these are not new shaders, they are the same ones thrown away and rebuilt.
	# That session compiled 790 pipelines in total.
	#
	# Every other assignment in this function goes through a Godot setter that
	# returns early when the value has not moved. These four do not: a bare
	# RenderingServer call has no such check, and shadow filter quality is a
	# shader define, so writing it at all invalidates the scene shaders that
	# read it. They are the only writes here that can cost anything when
	# nothing changed, which is exactly the case the symptom describes.
	#
	# Not measured on this machine, and worth being straight about:
	# RENDERING_INFO_PIPELINE_COMPILATIONS_* is Vulkan-only and reads zero
	# under the OpenGL3 renderer a headless runner gets, so the counter that
	# would prove it cannot be read here. The change is safe either way - the
	# same values still reach the engine, they just stop being re-sent.
	var shadow_size: int = graphics_positional_shadow_atlas_size if graphics_shadows_enabled else 0
	if shadow_size != _applied_shadow_atlas_size \
			or graphics_positional_shadow_filter_quality != _applied_shadow_filter_quality:
		_applied_shadow_atlas_size = shadow_size
		_applied_shadow_filter_quality = graphics_positional_shadow_filter_quality

		window.positional_shadow_atlas_size = shadow_size
		ProjectSettings.set("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", graphics_positional_shadow_filter_quality)

		# positional_shadow_atlas_size covers omni and spot lights only - a
		# DirectionalLight3D renders into a separate atlas that the "Shadows"
		# row was leaving at the engine default, so "off" was never fully off
		# and the ladder's atlas sizes never applied to it. Same numbers as the
		# positional atlas so one row means one thing.
		RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			graphics_positional_shadow_filter_quality as RenderingServer.ShadowQuality
		)

	window.anisotropic_filtering_level = clampi(graphics_anisotropic_filtering, 0, 4) as Viewport.AnisotropicFiltering
	window.mesh_lod_threshold = maxf(0.0, graphics_mesh_lod_threshold)

	Engine.physics_ticks_per_second = clampi(graphics_physics_ticks_per_second, 15, 120)
	# Godot's default is 8, i.e. after a 141ms frame it runs eight catch-up
	# physics steps inside the next one - piling work onto a frame that is
	# already late. Capped rather than made a preset field because it costs
	# nothing when frames are fast: below two ticks of frame time it never
	# engages at all.
	Engine.max_physics_steps_per_frame = 4

	window.msaa_3d = graphics_msaa_3d_quality
	window.screen_space_aa = graphics_screen_space_aa_quality

	if lullaby_language != TranslationServer.get_locale():
		TranslationServer.set_locale(lullaby_language)

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

## Nodes whose SubViewport must keep rendering at its authored size, by
## group. Nothing is in it yet; it exists because "render everything smaller"
## is wrong for a viewport whose pixels are read rather than looked at - a
## mask, or anything sampled for a picking test.
const SUBVIEWPORT_NATIVE_GROUP := &"native_resolution_viewport"

## Render scale, applied to SubViewports as well as to the window.
##
## The window has honoured this setting since the graphics rows existed;
## SubViewports never did, and they are not a rounding error. The shop's
## three are 640x480, 1240x928 and 480x960 - 1.92M pixels authored, against
## 0.29M for the whole screen at scale 0.50 - and the device log measures
## them at 2.93M live pixels and 3.67ms of a 15.04ms GPU frame. A quarter of
## the shop's GPU time was going to render targets four times the resolution
## of the screen showing them.
##
## size_2d_override keeps the 2D coordinate space the UI inside was laid out
## against, so only the render target shrinks - the same split the main
## viewport makes between window size and render scale. Without it every
## Control inside would reflow against a smaller rect, which is a layout
## change, not a performance one.
##
## Re-entrant: the override, not the current size, is the authored size once
## this has run, or repeated applies would scale an already-scaled viewport.

## The cap to hand Engine.max_fps, with TARGET_FPS_NATIVE resolved.
##
## screen_get_refresh_rate() returns -1 when the platform cannot answer -
## headless does, and so does any driver that does not expose it - so the
## fallback is the 60 the game shipped with rather than an unlimited cap that
## would quietly cook the battery on a device that simply would not say.
##
## Rounded, not truncated: panels report 59.94 and 119.88 as often as 60 and
## 120, and int() on those gives 59 and 119, a cap fractionally under the
## refresh rate which is the one value guaranteed to miss every frame.
func _resolved_target_fps() -> int:
	if display_target_fps != TARGET_FPS_NATIVE:
		return display_target_fps

	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz <= 0.0:
		return 60
	return int(roundf(hz))

func _apply_subviewport_render_scale() -> void:
	# A scene loaded later brings its own SubViewports, and they would render
	# at full size until the next time the settings happened to be applied -
	# which for the shop is never, since nothing reapplies them on entering a
	# room. Same reason the shader stripper watches node_added.
	if not _watching_new_viewports:
		get_tree().node_added.connect(_on_node_added_scale_viewport)
		_watching_new_viewports = true

	_scale_subviewports_under(get_tree().root)

func _on_node_added_scale_viewport(node: Node) -> void:
	if node is SubViewport:
		_scale_subviewport(node)

func _scale_subviewports_under(node: Node) -> void:
	if node is SubViewport:
		_scale_subviewport(node)

	for child: Node in node.get_children():
		_scale_subviewports_under(child)

func _scale_subviewport(viewport: SubViewport) -> void:
	if viewport.is_in_group(SUBVIEWPORT_NATIVE_GROUP):
		return

	# First time through, the size in the scene file is the authored size.
	# After that it is the override, because size itself has been scaled.
	var authored: Vector2i = viewport.size_2d_override
	if authored.x <= 0 or authored.y <= 0:
		authored = viewport.size
		viewport.size_2d_override = authored
		viewport.size_2d_override_stretch = true

	# One pixel minimum: a zero-sized render target is an error, and a scale
	# row can go low.
	viewport.size = Vector2i(
		maxi(1, int(round(float(authored.x) * graphics_render_scale))),
		maxi(1, int(round(float(authored.y) * graphics_render_scale))))

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
		_hide_mesh_that_only_draws_an_effect(node)
	_strip_backbuffer_copy(node)

## The screen copies the stripped shaders were reading.
##
## shd_blend_modes samples hint_screen_texture, so every node using it needs a
## BackBufferCopy - and intro.tscn has five, one per overlay-blended fog layer.
## A full framebuffer copy is about the most expensive thing there is on a
## tile-based mobile GPU: it forces the tile to resolve out to memory. That is
## why intro.tscn measures 20.6ms of GPU with 13 draw calls, 40 objects and
## **168 primitives** - it is not drawing anything, it is copying the screen
## five times.
##
## Nulling the material does not stop this. A BackBufferCopy copies whether or
## not anything still samples the result, so before this the setting removed
## the shader maths and kept the entire cost. With the materials gone nothing
## reads the screen texture, so disabling the copy is free.
func _strip_backbuffer_copy(node: Node) -> void:
	if not (node is BackBufferCopy):
		return
	if node.copy_mode == BackBufferCopy.COPY_MODE_DISABLED:
		return

	# Kept in its own map rather than going through _stash(), which stores
	# Materials and whose restore loop would try to assign one back here.
	_stashed_copy_modes[node.get_instance_id()] = node.copy_mode
	node.copy_mode = BackBufferCopy.COPY_MODE_DISABLED

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
	_hide_if_it_draws_nothing(node, property)

## Hides a node whose only reason to be drawn was the shader just removed.
##
## Same shape as _strip_backbuffer_copy above, and the same lesson: the
## setting was removing the maths and keeping the cost. Safety Lullaby
## authors five full-screen effect ColorRects across its own scene and
## Petina (WaterEffect, RadialEffect, SquiggleLayer, Rain, NTSC), Monochrome
## authors a sixth, and every one of them is Color(0, 0, 0, 0) - fully
## transparent, because the shader was what put anything on screen. With the
## material nulled they keep being rasterised and alpha-blended across the
## whole frame to produce nothing.
##
## That is most of what Very Low costs in that song. The device log measures
## Safety Lullaby at gpu=6.52ms with draw=6/prims=424 and gpu=42.11ms with
## draw=11/prims=434 - five extra draw calls for +35ms on identical
## geometry, and at draw=11 the GPU also reads 22.1ms and 12.9ms in other
## sections, so it tracks full-screen passes and nothing else. fx= reads 0
## throughout, which says the materials really were stripped and the cost
## stayed anyway.
##
## Deliberately narrow. Only a ColorRect, only when its colour is fully
## transparent, and only for the `material` slot - a Sprite2D or TextureRect
## still has its texture to draw after the shader goes (Safety's `Glow` is
## exactly that), and hiding one of those would remove art the player is
## meant to see. This is the same guard _mesh_has_own_material() applies on
## the 3D side, where nulling material_override once turned the shop's cubes
## and the notepad page white.
func _hide_if_it_draws_nothing(node: Node, property: StringName) -> void:
	if property != &"material" or not (node is ColorRect):
		return
	if not is_zero_approx(node.color.a):
		return
	if not node.visible:
		return

	_stashed_visibility[node.get_instance_id()] = true
	node.visible = false

## Hides a mesh whose every surface is an effect shader living on the *mesh
## resource* rather than on the node.
##
## _strip_surface_shader_material() above reads get_surface_override_material()
## and _strip_shader_material_property() reads material_override, so between
## them they cover every material the node owns. A material set on the
## PrimitiveMesh/ArrayMesh itself is owned by neither, and neither sees it.
##
## Chimera's Environment/Lights/Ray is exactly that: a BoxMesh whose own
## `material` is shd_godrays, which is in EFFECT_SHADER_PATHS and has never
## once been stripped by the setting named after removing it. And it is not a
## small thing to miss - the shader is
##
##     render_mode unshaded, blend_add, cull_disabled, depth_test_disabled
##
## so the box is rasterised on **both** faces with no depth rejection, taking a
## hint_depth_texture sample per fragment, over 1738x1080 of screen at
## `scene@60` and 1210x1080 at `scene@100` (measured by scene_probe against the
## running scene). At scale=0.50 the entire 3D pass is 800x360 = 0.29 Mpx and
## this one box covers roughly three times that, because it is drawn twice.
##
## Nulling is not the fix here and that is the whole reason this is separate:
## the material belongs to a shared mesh resource, and clearing it would leave
## the box drawing as Godot's plain white default - the same failure that once
## turned the shop's cubes and the notepad page white. A node whose only
## reason to be on screen is the effect just removed should not be on screen.
##
## Deliberately narrow, in the same spirit as _hide_if_it_draws_nothing():
##
## - every surface must resolve to an effect shader. One real material and the
##   mesh is art, not an effect.
## - a node already hidden is left alone, so the restore can never reveal
##   something another system hid. That is the bug the reverted shader prewarm
##   shipped - it revealed hidden nodes, gave focus to the console's Codes tab
##   and opened the Android keyboard on a screen the player never chose.
func _hide_mesh_that_only_draws_an_effect(node: MeshInstance3D) -> void:
	if not node.visible:
		return
	var surfaces: int = node.mesh.get_surface_count()
	if surfaces == 0:
		return
	# material_override replaces every surface, so if one is set this node is
	# not describable surface by surface and the override path already owns it.
	if node.material_override != null:
		return

	for surface in surfaces:
		var mat: Material = node.get_surface_override_material(surface)
		if mat == null:
			mat = node.mesh.surface_get_material(surface)
		if not (mat is ShaderMaterial and mat.shader
				and EFFECT_SHADER_PATHS.has(mat.shader.resource_path)):
			return

	_stashed_visibility[node.get_instance_id()] = true
	node.visible = false

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

	for id: int in _stashed_copy_modes:
		var node: Object = instance_from_id(id)
		if is_instance_valid(node) and node is BackBufferCopy:
			node.copy_mode = _stashed_copy_modes[id]
	_stashed_copy_modes.clear()

	# Only ever puts back a true this setting itself turned off, so a node
	# something else hid in the meantime is not revealed by turning the
	# effects back on.
	for id: int in _stashed_visibility:
		var node: Object = instance_from_id(id)
		# CanvasItem for the transparent effect rects, MeshInstance3D for a
		# mesh whose only material was an effect shader on its own resource.
		if is_instance_valid(node) and (node is CanvasItem or node is MeshInstance3D):
			node.visible = true
	_stashed_visibility.clear()

func get_input_name(action: StringName) -> String:
	if not input_map.has(action):
		return ""

	for event in input_map[action]:
		return event.as_text()

	return ""

## Gamepad buttons for the four note lanes, kept in `input_game`.
##
## The D-pad rather than the face buttons, because the lanes ARE directions -
## lane 0 is the left arrow on screen - and a 1:1 mapping needs no learning.
## It overlaps `ui_left`/`ui_down`/`ui_up`/`ui_right`, which is harmless: those
## only do anything while a Control has focus, and nothing does during a song.
const GAMEPAD_LANE_BUTTONS: Dictionary[StringName, int] = {
	&"mania_lane0": JOY_BUTTON_DPAD_LEFT,
	&"mania_lane1": JOY_BUTTON_DPAD_DOWN,
	&"mania_lane2": JOY_BUTTON_DPAD_UP,
	&"mania_lane3": JOY_BUTTON_DPAD_RIGHT,
}

## Gamepad buttons for the rebindable project actions, kept in `input_map`.
##
## `lullaby_special` takes A, which is also `ui_accept` below - deliberately
## the same overlap the keyboard already ships, where the mechanic key and
## ui_accept are both Space.
const GAMEPAD_ACTION_BUTTONS: Dictionary[StringName, int] = {
	&"lullaby_special": JOY_BUTTON_A,
	&"funkin_pause": JOY_BUTTON_START,
	&"open_cartridge_bag": JOY_BUTTON_X,
}

## Gamepad buttons for Godot's own UI actions, added straight to the InputMap.
##
## Godot ships joypad bindings for `ui_left/right/up/down` and **none for
## `ui_accept` or `ui_cancel`** - checked against the running binary, they are
## Enter/Kp Enter/Space and Escape. So a pad could move through every menu in
## the game and neither confirm nor go back.
##
## Added at runtime rather than written into project.godot's `[input]`, and
## that is the safe half of the choice: overriding a built-in action in the
## project file replaces its whole event list, so a joypad-only entry would
## silently take Enter and Space off `ui_accept`. Appending cannot.
##
## `reset_input_map()` skips `ui_` actions, so these are never persisted and
## are re-applied from here on every boot.
const GAMEPAD_UI_BUTTONS: Dictionary[StringName, int] = {
	&"ui_accept": JOY_BUTTON_A,
	&"ui_cancel": JOY_BUTTON_B,
}

## Whether any of these events is a gamepad one.
static func _has_gamepad_event(events: Array) -> bool:
	for event: InputEvent in events:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false

## `device = -1` is "any pad", which is what Godot's own `ui_left` ships and
## what the note map needs - `InputEvent.is_match()` ignores the device, and
## `InputMap` treats -1 as ALL_DEVICES.
static func _gamepad_event(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	return event

## Guarantees every action a pad needs has at least one gamepad binding.
##
## Never overrides one: an action that already carries any gamepad event is
## left exactly as it is, so a player who rebinds a lane to a different button
## does not get the default added back on the next boot. That is also what
## makes it safe to run on every load rather than once behind a migration
## flag.
##
## It has to run on load and not only on a fresh install. `load_from()` reads
## `input_game` back wholesale and `input_map` per action, so a settings.ini
## written before this existed would otherwise erase the defaults every boot -
## the pad would work on a clean install and nowhere else.
##
## Sticks and triggers are out of scope on purpose: the console's rebind row
## finishes on `event.is_pressed()`, and `InputEventJoypadMotion` never reports
## pressed, so an axis cannot be bound there either. Buttons only, both ways.
func ensure_gamepad_defaults() -> void:
	for action: StringName in GAMEPAD_LANE_BUTTONS:
		if not input_game.has(action):
			input_game[action] = []
		if not _has_gamepad_event(input_game[action]):
			input_game[action].append(_gamepad_event(GAMEPAD_LANE_BUTTONS[action]))

	for action: StringName in GAMEPAD_ACTION_BUTTONS:
		if not input_map.has(action):
			continue
		if not _has_gamepad_event(input_map[action]):
			input_map[action].append(_gamepad_event(GAMEPAD_ACTION_BUTTONS[action]))

	for action: StringName in GAMEPAD_UI_BUTTONS:
		if not InputMap.has_action(action):
			continue
		if not _has_gamepad_event(InputMap.action_get_events(action)):
			InputMap.action_add_event(action, _gamepad_event(GAMEPAD_UI_BUTTONS[action]))

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

	ensure_gamepad_defaults()

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

	# After the file, not before: load_from() replaces input_game wholesale and
	# input_map per action, so defaults added earlier would be read straight
	# back off disk. A settings.ini written before gamepad support existed gets
	# the bindings here.
	ensure_gamepad_defaults()

	return OK
