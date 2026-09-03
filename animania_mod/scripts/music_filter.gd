extends Node
## Music filter system — faithful port of funkin.audio.EffectSound.
##
## Provides LOWPASS, GAIN, REVERB effects on audio buses.
## The Animania binary uses OpenAL effects (LOWPASS, GAIN, GAINHF, REVERB,
## DECAY_TIME). Godot's AudioBus system provides equivalent functionality.

# ─── Constants ─────────────────────────────────────────────────────────────

## Bus names matching the Animania binary's audio routing
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

## Filter types from the binary
enum FilterType {
	LOWPASS,
	HIGHPASS,
	BANDPASS,
	REVERB,
	GAIN,
}

# ─── Singleton ────────────────────────────────────────────────────────────

static var instance: Node = null

# ─── State ────────────────────────────────────────────────────────────────

var _lowpass_cutoff: float = 22000.0  ## Hz
var _lowpass_resonance: float = 0.5
var _gain_db: float = 0.0  ## dB
var _reverb_room_size: float = 0.0
var _reverb_damping: float = 0.5
var _reverb_wet: float = 0.0
var _reverb_dry: float = 1.0
var _reverb_spread: float = 0.0

## AudioEffect nodes
var _lowpass_effect: AudioEffectLowPassFilter
var _gain_effect: AudioEffectAmplify
var _reverb_effect: AudioEffectReverb

## Active bus indices
var _music_bus_idx: int = -1

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	instance = self
	_setup_buses()
	_apply_effects()


func _exit_tree() -> void:
	if instance == self:
		instance = null
	_clear_effects()


# ─── Bus setup ────────────────────────────────────────────────────────────

func _setup_buses() -> void:
	# Ensure Music bus exists
	_music_bus_idx = AudioServer.get_bus_index(MUSIC_BUS)
	if _music_bus_idx == -1:
		_music_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_music_bus_idx)
		AudioServer.set_bus_name(_music_bus_idx, MUSIC_BUS)
		AudioServer.set_bus_send(_music_bus_idx, "Master")


func _apply_effects() -> void:
	# Low-pass filter
	_lowpass_effect = AudioEffectLowPassFilter.new()
	_lowpass_effect.cutoff_hz = _lowpass_cutoff
	_lowpass_effect.resonance = _lowpass_resonance
	AudioServer.add_bus_effect(_music_bus_idx, _lowpass_effect, 0)

	# Gain (amplify)
	_gain_effect = AudioEffectAmplify.new()
	_gain_effect.volume_db = _gain_db
	AudioServer.add_bus_effect(_music_bus_idx, _gain_effect, 1)

	# Reverb
	_reverb_effect = AudioEffectReverb.new()
	_reverb_effect.room_size = _reverb_room_size
	_reverb_effect.damping = _reverb_damping
	_reverb_effect.wet = _reverb_wet
	_reverb_effect.dry = _reverb_dry
	_reverb_effect.spread = _reverb_spread
	AudioServer.add_bus_effect(_music_bus_idx, _reverb_effect, 2)


func _clear_effects() -> void:
	if _music_bus_idx == -1:
		return
	# Remove effects in reverse order
	while AudioServer.get_bus_effect_count(_music_bus_idx) > 0:
		AudioServer.remove_bus_effect(_music_bus_idx, 0)


# ─── Public API ───────────────────────────────────────────────────────────

## Set low-pass filter cutoff (Hz). Higher values let more frequencies through.
## Animania uses this for the blur/fade effect during song transitions.
func set_lowpass(cutoff_hz: float, resonance: float = 0.5) -> void:
	_lowpass_cutoff = cutoff_hz
	_lowpass_resonance = resonance
	if _lowpass_effect:
		_lowpass_effect.cutoff_hz = cutoff_hz
		_lowpass_effect.resonance = resonance


## Set gain in dB. 0.0 = normal volume, negative = quieter, positive = louder.
func set_gain(db: float) -> void:
	_gain_db = db
	if _gain_effect:
		_gain_effect.volume_db = db


## Set reverb parameters.
func set_reverb(room_size: float, damping: float = 0.5, wet: float = 0.0, dry: float = 1.0) -> void:
	_reverb_room_size = room_size
	_reverb_damping = damping
	_reverb_wet = wet
	_reverb_dry = dry
	if _reverb_effect:
		_reverb_effect.room_size = room_size
		_reverb_effect.damping = damping
		_reverb_effect.wet = wet
		_reverb_effect.dry = dry


## Apply a named filter preset from the Animania binary.
## Supports: "LOWPASS", "GAIN", "REVERB", "DECAY_TIME"
func apply_filter(filter_name: String, value: float) -> void:
	match filter_name.to_upper():
		"LOWPASS":
			set_lowpass(value)
		"GAIN":
			set_gain(value)
		"REVERB":
			set_reverb(value)
		"DECAY_TIME":
			if _reverb_effect:
				_reverb_effect.room_size = clampf(value / 5.0, 0.0, 1.0)


## Reset all filters to defaults
func reset() -> void:
	set_lowpass(22000.0, 0.5)
	set_gain(0.0)
	set_reverb(0.0, 0.5, 0.0, 1.0)


## Smoothly transition low-pass cutoff over time.
## Used for song end/exit blur effects.
func tween_lowpass(target_cutoff: float, duration: float = 0.5) -> void:
	var tw := create_tween()
	tw.tween_method(set_lowpass, _lowpass_cutoff, target_cutoff, duration).set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)


## Smoothly transition gain over time.
func tween_gain(target_db: float, duration: float = 0.5) -> void:
	var tw := create_tween()
	tw.tween_method(set_gain, _gain_db, target_db, duration).set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)


## Apply the standard song-end filter effect from Animania.
## Low-passes the music and fades it out.
func apply_song_end_filter(duration: float = 1.0) -> void:
	tween_lowpass(200.0, duration)
	tween_gain(-20.0, duration)


## Clear the song-end filter and restore normal audio.
func clear_song_end_filter(duration: float = 0.5) -> void:
	tween_lowpass(22000.0, duration)
	tween_gain(0.0, duration)
