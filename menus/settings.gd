extends Node

## Autoload holding player preferences set up during First Boot Settings
## (and later from a proper Settings menu, once one exists). Lullaby's own
## default keybinds are Z/F/J/K rather than Rubicon's D/F/J/K default.

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

var flashing_lights_enabled := true

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
