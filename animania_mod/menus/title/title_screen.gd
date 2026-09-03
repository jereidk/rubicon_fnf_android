extends Node2D
## The title screen.
##
## Two phases, and they come from two different places. The intro - the text that spells
## itself out over black for the first 31 beats - is `TitleScreen.script`, which the mod
## ships as plain HScript, so this half is transcribed rather than guessed. What follows it
## is `animania.states.TitleScreen`, compiled into the game's binary, so the logo and the
## press-enter prompt are here with their real assets and animations but a layout this port
## chose. See animania_mod/source/README.md.
##
## The beat is the music's: animaniaINTRO is 102bpm 4/4 per its own metadata, so a beat is
## 60/102 seconds. Funkin drives titleBeat off the Conductor the same way.

const BPM := 102.0

## case 31 tweens the last line up and out over .6s with a circIn ease.
const FINALE_SECONDS := 0.6
const FINALE_SCALE := 1.25
const FINALE_RISE := -100.0

## The colour the script's <a> markup applies, as FlxTextFormat(0xFFAAD2FF).
const ACCENT := Color8(0xAA, 0xD2, 0xFF)

## BOIL_INTERVAL: 1/24 seconds, exact from .rodata double at 0x2ed0ce8. The displacement
## is re-rolled in STEPS rather than swum through continuously — that discontinuity is the
## effect. The mod's bumpTimer() fires every BOIL_INTERVAL and re-rolls the offset.
const BOIL_INTERVAL := 1.0 / 24.0

## Logo scale: 0.32, exact from rodata doubles at 0x2ed2ba8 and 0x2ed2b94 in create().
## The logo does NOT bump on beats — the update() method has no logo scale manipulation.
## The only post-intro visual is the camera lerp below.
const LOGO_SCALE := 0.32

## Camera lerp: from update(). The camera's field at offset 0x110 (likely zoom or offset)
## is interpolated toward 0.885 (rodata at 0x2ed0b8e) with a factor derived from:
##   factor = -3.125 * dt  (rodata at 0x2ed0bb4)
##   then passed through exp() (call to 0x8bd2d0, which is expf/expd)
##   result = 0.885 + (current - 0.885) * exp(-3.125 * dt)
## This is exponential decay toward 0.885 — the camera eases back to its rest position.
## The lerp is SKIPPED when [this + 0x158] != 0, which is the follows_singer flag:
## when the chart has camera events, the follow-the-singer fallback is off.
const CAMERA_LERP_TARGET := 0.885
const CAMERA_LERP_RATE := -3.125

## Flash: from playIntro(). The flash overlay is Color(0,0,0,255) = BLACK, not white.
## It fades over 8.0 seconds (rodata at 0x2ed6e2a). The flash is a fade-to-black that
## covers the screen while the intro elements become visible, then fades out.
const FLASH_COLOR := Color.BLACK
const FLASH_DURATION := 8.0

## MUSIC_FINAL_VOLUME: 0.7, exact from doJingle's rodata at 0x2ed5bf0. The intro music
## fades in to this volume rather than starting at full.
const MUSIC_FINAL_VOLUME := 0.7
## MUSIC_FADE_IN_TIME: how long the music takes to reach final volume.
const MUSIC_FADE_IN_TIME := 1.5

## CONFIRM_DELAY: 0.35, exact from create() rodata at 0x2ed34b2/0x2ed3471. The deaf
## window after the intro ends before a confirm is accepted.
const CONFIRM_DELAY := 0.35

## Black screen bars: from the binary's blackScreen/blackLineDown/blackLineUp fields.
## These animate at the intro's dramatic beats. They appear at beat 28 (the zoom-in
## section) and clear at beat 31 (the finale).
const BAR_HEIGHT := 100.0

## Every beat that does something, transcribed from titleBeat(). `text` replaces the line,
## `add` appends to it, `clear` empties it, `zoom` punches the camera, and `hold` is the
## script's `skipTween` - the beats that place the text themselves instead of letting the
## default tween slide it into the middle of the screen.
##
## The flash trigger is NOT per-beat — it happens once in playIntro() as a fade-to-black.
## The bars are per-beat from the binary's blackScreen field.
const BEATS := {
	1: {"text": "[accent]ANIMANIA!CREW[/accent]"},
	3: {"text": "[accent]ANIMANIA!CREW[/accent]\nPRESENTS"},
	4: {"clear": true},
	5: {"text": "HAVING FUN?"},
	7: {"add": "\nGOOD"},
	8: {"clear": true},
	9: {"text": "WOOF WOOF"},
	11: {"add": "\nWE FUNK"},
	12: {"clear": true},
	13: {"text": "FNF"},
	15: {"add": "\nIS REAL"},
	16: {"clear": true},
	17: {"text": "GOD DAMN THE SUN"},
	19: {"add": "\nMY EYES"},
	20: {"clear": true, "hold": true, "y": 350.0},
	21: {"text": "WE ARE"},
	23: {"add": "\nSO REAL"},
	24: {"clear": true, "hold": true, "y": 0.0},
	25: {"text": "FUNKIN\n"},
	27: {"add": "FOREVER"},
	28: {"text": "FRIDAY\n", "alpha": 0.0, "zoom": 0.05, "bars": true},
	29: {"add": "NIGHT\n", "zoom": 0.075},
	30: {"add": "FUNKIN'\n", "zoom": 0.1},
	31: {"add": "[accent]ANIMANIA![/accent]", "hold": true, "zoom": 0.15,
		 "finale": true},
}

## The last beat the intro spells, after which the title proper takes over.
const LAST_BEAT := 31

## Where a confirm goes.
const NEXT_SCENE := "res://animania_mod/menus/main/main_menu.tscn"

## Jingle: gfLoveJingle from the binary's doJingle method at 0x2b249a0.
## Only fires on cheat code completion. confirmMenu is the menu confirm sound.
const JINGLE_PATH := "res://animania_mod/source/sounds/gfLoveJingle.ogg"
const CONFIRM_SOUND_PATH := "res://animania_mod/source/sounds/confirmMenu.ogg"
const INTRO_SOUND_PATH := "res://animania_mod/source/sounds/introSound.ogg"

## Cheat code: from the binary's codePress/cheatCodeShit system. The title screen
## listens for an 8-key arrow sequence stored in .rodata at 0x5ba9a40, memcpy'd
## into the cheatCodeArray field. Sequence: UP, RIGHT, UP, RIGHT, DOWN, LEFT, DOWN, LEFT.
const CHEAT_CODE := [KEY_UP, KEY_RIGHT, KEY_UP, KEY_RIGHT,
	KEY_DOWN, KEY_LEFT, KEY_DOWN, KEY_LEFT]

@export var music: AudioStreamPlayer
@export var intro_text: RichTextLabel
@export var title: Node2D
@export var camera: Camera2D
## The material carrying boil.gdshader, whose offset this steps.
@export var boil: ShaderMaterial

var _beat: int = 0
var _elapsed: float = 0.0
var _line: String = ""
var _done: bool = false
var _boil_timer: float = 0.0
var _confirmed: bool = false
var _ready_at: float = INF

# Music fade-in
var _music_volume: float = 0.0
var _music_fading: bool = false

# Flash overlay (black, from playIntro)
var _flash_rect: ColorRect = null
var _flash_tween: Tween = null

# Black bars
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null
var _bars_visible: bool = false

# Cheat code
var _cheat_index: int = 0

# Audio players
var _jingle_player: AudioStreamPlayer = null
var _confirm_player: AudioStreamPlayer = null
var _intro_sound_player: AudioStreamPlayer = null


func _ready() -> void:
	title.visible = false
	intro_text.visible = false
	intro_text.text = ""

	# Flash overlay: BLACK, full screen, starts at alpha 0.
	# Created on the CanvasLayer that has intro_text so it draws above everything.
	var canvas: CanvasLayer = intro_text.get_parent()
	_flash_rect = ColorRect.new()
	_flash_rect.color = FLASH_COLOR
	_flash_rect.modulate.a = 0.0
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_flash_rect)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Black bars (from binary's blackScreen/blackLineDown/blackLineUp)
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_top.visible = false
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.offset_bottom = BAR_HEIGHT
	canvas.add_child(_bar_top)

	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bottom.visible = false
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.offset_top = -BAR_HEIGHT
	canvas.add_child(_bar_bottom)

	# One-shot audio players
	_jingle_player = AudioStreamPlayer.new()
	add_child(_jingle_player)
	_confirm_player = AudioStreamPlayer.new()
	add_child(_confirm_player)
	_intro_sound_player = AudioStreamPlayer.new()
	add_child(_intro_sound_player)

	# Play intro sound (from create())
	call_deferred("_play_intro_sound")


func _play_intro_sound() -> void:
	if ResourceLoader.exists(INTRO_SOUND_PATH):
		_intro_sound_player.stream = load(INTRO_SOUND_PATH)
		_intro_sound_player.play()















## Music fade-in: ramp from 0 to MUSIC_FINAL_VOLUME over MUSIC_FADE_IN_TIME.
## From playMusic(): startingVolume, overrideExisting, restartTrack.
func _fade_music(delta: float) -> void:
	if music == null or not _music_fading:
		return
	_music_volume = minf(_music_volume + delta / MUSIC_FADE_IN_TIME, 1.0)
	music.volume_db = linear_to_db(_music_volume * MUSIC_FINAL_VOLUME)
	if _music_volume >= 1.0:
		_music_fading = false


## Camera lerp: exponential decay toward CAMERA_LERP_TARGET.
## From update(): the camera field at offset 0x110 (zoom) is lerped:
##   result = 0.885 + (current - 0.885) * exp(-3.125 * dt)
## Skipped when [this + 0x158] != 0 (follows_singer mode).
## In the port, the camera's zoom.x serves as the lerp target field.
func _update_camera(delta: float) -> void:
	if camera == null:
		return
	# The mod skips the lerp when follows_singer is on (chart has events).
	# For the title screen, follows_singer is always off, so we always lerp.
	var current: float = camera.zoom.x
	var factor: float = exp(CAMERA_LERP_RATE * delta)
	var target: float = CAMERA_LERP_TARGET + (current - CAMERA_LERP_TARGET) * factor
	camera.zoom = Vector2(target, target)


## bumpTimer/updateBoil: every BOIL_INTERVAL the displacement is re-rolled.
## From the compiled TitleScreen's bumpTimer/updateBoil pair.
func _bump_boil(delta: float) -> void:
	if boil == null:
		return
	_boil_timer += delta
	if _boil_timer < BOIL_INTERVAL:
		return
	_boil_timer -= BOIL_INTERVAL
	boil.set_shader_parameter(&"boil_offset", Vector2(randf(), randf()))


## Flash overlay: triggered once in playIntro(). The binary's playIntro creates a
## Color(0,0,0,255) flash with duration 8.0 seconds. This fades to black, covering
## the screen while intro elements become visible underneath, then fades out.
func _trigger_flash() -> void:
	if _flash_rect == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# Start fully opaque (black), then fade out
	_flash_rect.modulate.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "modulate:a", 0.0, FLASH_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


## Black bars: shown on beats with {"bars": true}, hidden on the finale.
func _show_bars() -> void:
	_bars_visible = true
	if _bar_top != null:
		_bar_top.visible = true
		_bar_top.offset_bottom = 0.0
		var tween: Tween = create_tween()
		tween.tween_property(_bar_top, "offset_bottom", BAR_HEIGHT, 0.3) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	if _bar_bottom != null:
		_bar_bottom.visible = true
		_bar_bottom.offset_top = 0.0
		var tween: Tween = create_tween()
		tween.tween_property(_bar_bottom, "offset_top", -BAR_HEIGHT, 0.3) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


func _hide_bars() -> void:
	_bars_visible = false
	if _bar_top != null:
		var tween: Tween = create_tween()
		tween.tween_property(_bar_top, "offset_bottom", 0.0, 0.3) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func(): _bar_top.visible = false)
	if _bar_bottom != null:
		var tween: Tween = create_tween()
		tween.tween_property(_bar_bottom, "offset_top", 0.0, 0.3) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func(): _bar_bottom.visible = false)


## titleBeat(beat). The default tween at the bottom runs on every beat the script does not
## set skipTween on - it slides the line to the middle of the screen and fades it in over
## beatLengthMs / 1250, which at 102bpm is not quite half a beat.
func _run_beat(beat: int) -> void:
	if beat > LAST_BEAT:
		_finish()
		return

	var step: Dictionary = BEATS.get(beat, {})
	if step.is_empty():
		return

	if step.has("clear"):
		_line = ""
	elif step.has("text"):
		_line = String(step["text"])
	elif step.has("add"):
		_line += String(step["add"])

	intro_text.visible = not _line.is_empty()
	intro_text.text = "[center]%s[/center]" % _line.replace(
		"[accent]", "[color=#%s]" % ACCENT.to_html(false)).replace("[/accent]", "[/color]")

	if step.has("alpha"):
		intro_text.modulate.a = float(step["alpha"])
	if step.has("y"):
		intro_text.position.y = float(step["y"])
	if step.has("zoom") and camera != null:
		camera.zoom += Vector2.ONE * float(step["zoom"])

	# Black bars
	if step.has("bars"):
		_show_bars()

	if step.has("finale"):
		if _bars_visible:
			_hide_bars()
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(intro_text, "scale", Vector2.ONE * FINALE_SCALE,
			FINALE_SECONDS).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
		tween.tween_property(intro_text, "position:y",
			intro_text.position.y + FINALE_RISE, FINALE_SECONDS) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
		return

	if step.get("hold", false):
		return

	# The default tween: to the middle of the screen, fading in.
	var slide: Tween = create_tween().set_parallel(true)
	slide.tween_property(intro_text, "position:x", 0.0, 60.0 / BPM / 1.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	slide.tween_property(intro_text, "modulate:a", 1.0, 60.0 / BPM / 1.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## moveToMain: the intro is over and the title itself comes up.
## From the compiled TitleScreen's _finish method.
func _finish() -> void:
	if _done:
		return
	_done = true
	_ready_at = _elapsed + CONFIRM_DELAY
	intro_text.visible = false
	title.visible = true

	# playIntro's flash: fade from black to transparent over FLASH_DURATION.
	_trigger_flash()

	# Start music fade-in (from playMusic: startingVolume → MUSIC_FINAL_VOLUME).
	if music != null:
		_music_volume = 0.0
		_music_fading = true
		music.volume_db = linear_to_db(0.0)
		music.play()


## doJingle: from the binary's doJingle method at 0x2b249a0. Only fires
## when the cheat code completes — NOT from the normal title flow.
## Plays gfLoveJingle (overrideExisting, restartTrack) then confirmMenu
## at volume 0.7 (MUSIC_FINAL_VOLUME). The flash is fully transparent.
func _do_jingle() -> void:
	if ResourceLoader.exists(JINGLE_PATH):
		_jingle_player.stream = load(JINGLE_PATH)
		_jingle_player.volume_db = linear_to_db(MUSIC_FINAL_VOLUME)
		_jingle_player.play()
	if ResourceLoader.exists(CONFIRM_SOUND_PATH):
		_confirm_player.stream = load(CONFIRM_SOUND_PATH)
		_confirm_player.volume_db = linear_to_db(MUSIC_FINAL_VOLUME)
		_confirm_player.play()


## Cheat code: from the binary's codePress/cheatCodeShit system.
func _check_cheat_code(keycode: int) -> void:
	if _cheat_index >= CHEAT_CODE.size():
		return
	if keycode == CHEAT_CODE[_cheat_index]:
		_cheat_index += 1
		if _cheat_index >= CHEAT_CODE.size():
			print("CHEAT CODE: Solo Time!")
			_do_jingle()
			_cheat_index = 0
	else:
		_cheat_index = 0


## skipIntro while the intro runs; the confirm once it is over.
func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or not event.is_pressed():
		return
	if not (event is InputEventKey or event is InputEventScreenTouch
			or event is InputEventMouseButton):
		return

	if event is InputEventKey and event.pressed and not event.echo:
		_check_cheat_code(event.keycode)

	if not _done:
		_finish()
		return
	confirm()


## moveToMain. The deaf window prevents the skip keystroke from also confirming.
func confirm() -> void:
	if _confirmed or not _done or _elapsed < _ready_at:
		return
	_confirmed = true
	if music != null:
		music.stop()
	get_tree().change_scene_to_file(NEXT_SCENE)
