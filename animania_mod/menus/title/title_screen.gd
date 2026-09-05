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
## The logo does NOT bump on beats - update() has no logo scale manipulation. It does
## MOVE, though: it is one of the three pieces the confirm branch flings. See _fling_pieces().
const LOGO_SCALE := 0.32

## Camera lerp, update() line 369: the camera's 0x110 - `zoom`, named by the `set_zoom` it
## is handed to - eased toward 0.885 by `exp(-3.125 * dt)`. There is NO skip condition; the
## "skipped when [this + 0x158] != 0, which is the follows_singer flag" this block used to
## carry was invented. 0x158 is `lerpOutroFactor`, the weight of the scrollAngle lerp on the
## line above it. See _update_camera().
const CAMERA_LERP_TARGET := 0.885
const CAMERA_LERP_RATE := -3.125

## Flash: from playIntro(). The flash overlay is Color(0,0,0,255) = BLACK, not white.
## It fades over 8.0 seconds (rodata at 0x2ed6e2a). The flash is a fade-to-black that
## covers the screen while the intro elements become visible, then fades out.
const FLASH_COLOR := Color.BLACK
const FLASH_DURATION := 8.0

## Re-read against the binary. The 0.7 IS at that displacement, but it is not the music's
## volume: doJingle line 548 (0x2b24b49) puts it in the `Null<double>` that
## `FunkinSound.playOnce(Paths.sound('confirmMenu'), 0.7)` takes - it is the CONFIRM SOUND's
## volume. The music's own numbers are elsewhere: playMusic (line 295) passes
## `{overrideExisting: true, startingVolume: 0, restartTrack: true}` (the anon's three fields
## at 0x2b2356f onward, lengths 16/14/12), and its closure sets `volume = 1.0` (0x2b241fc,
## set_volume through vtable 0x1b8). So the loop starts silent and ends at FULL.
const MUSIC_FINAL_VOLUME := 1.0
## The confirm sound in doJingle, which is where the 0.7 actually belongs.
const CONFIRM_VOLUME := 0.7
## MUSIC_FADE_IN_TIME: how long the music takes to reach final volume. The mod hands the ramp
## to FunkinSound rather than doing it itself, so the duration is this port's.
const MUSIC_FADE_IN_TIME := 1.5

## Re-read: 0.35 IS at that displacement, but it is not a delay. Both loads sit in create()
## line 159, feeding `FlxPointRangeBounds.set(0.35, 0.35, 0.1, 0.1)` on the title's particle
## emitter - it is the particles' START SCALE, shrinking to 0.1, the same pair the main
## menu's emitter uses. There is no deaf window in the mod at all: `inIntro` and `transition`
## are separate branches of update(), so one keypress can only be consumed by one of them.
## This port has no such state split, so the window stays - as this port's own device, at a
## number that is now admittedly arbitrary rather than measured.
const CONFIRM_DELAY := 0.35

## create() line 149-163, the title's own FlxTypedEmitter. This port had nothing here.
##
##     149  particleEmitter = new FlxTypedEmitter(-100, ...);
##     150  loadParticles(Paths.imageGraphic('menus/particle'), ...);
##     154  velocity.set(-50, -950, 50, -750)      // straight up, fast
##     159  scale.set(0.35, 0.35, 0.1, 0.1)
##     161  <colour range>.set(0xFFFFC0CB, 0xFF00FFFF, 0xFFFFFFFF)   // pink, cyan, white
##     163  start(<bool>, 0.09)
##
## The velocity pair is read but its mapping onto FlxPointRangeBounds' six parameters is
## this port's reading, the same caveat title_props.gd carries. Everything else is measured.
const SCREEN := Vector2(1920.0, 1080.0)
## Funkin is 1280x720 and this project 1920x1080.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const PARTICLE_IMAGE := "res://animania_mod/source/images/menus/particle.png"
const PARTICLE_SCALE := Vector2(0.35, 0.1)
const PARTICLE_RISE := Vector2(750.0, 950.0)
const PARTICLE_DRIFT := 50.0
const PARTICLE_FREQUENCY := 0.09
const PARTICLE_COLOURS: Array[Color] = [
	Color8(0xFF, 0xC0, 0xCB),
	Color8(0x00, 0xFF, 0xFF),
	Color(1.0, 1.0, 1.0),
]

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

## The cheat is real and lives in the binary, not in the HScript. `cheatCodeShit` (line 514,
## 0x2b265b0) polls EIGHT Controls actions - the four arrows at 0x30/0x38/0x40/0x48 and four
## more at 0x90/0x98/0xa0/0xa8, which are the gameplay lane keys, so either set works - and
## calls `codePress(flag)` with one of four bits per direction. `codePress` (line 526) walks
## `cheatArray` against `curCheatPos` and fires `doJingle()` on the last one (0x2b26532).
##
## `cheatArray` is built in __construct from `_hx_array_data_46b436b0_1` (0x5ba9a40), eight
## ints: **[1, 16, 1, 16, 256, 4096, 256, 4096]**. Pairing those flags with the order the
## eight actions are polled in gives 1 = UP, 16 = DOWN, 256 = RIGHT, 4096 = LEFT, so the
## sequence is UP DOWN UP DOWN RIGHT LEFT RIGHT LEFT - a Konami riff. This port had the right
## SHAPE (A B A B C D C D) with the wrong letters.
##
## The flag-to-direction pairing is read off how the compiler grouped the eight polls into
## four flag-emitting tails; that the result comes out as a recognisable Konami variant is
## the corroboration, not the derivation.
const CHEAT_CODE := [KEY_UP, KEY_DOWN, KEY_UP, KEY_DOWN,
	KEY_RIGHT, KEY_LEFT, KEY_RIGHT, KEY_LEFT]
## The mod accepts the lane keys for the same steps, so this port does too.
const CHEAT_ALIASES := {
	KEY_UP: [KEY_W], KEY_DOWN: [KEY_S], KEY_LEFT: [KEY_A], KEY_RIGHT: [KEY_D],
}

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
## `playingLoveJingle`, field 0x175 - the flag destroy() reads on the way out.
var _playing_love_jingle: bool = false

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
	_outro_angle = float(randi_range(-10, 0) * 2)
	_build_particles()
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


func _process(delta: float) -> void:
	_elapsed += delta
	_drive_beats()
	_update_camera(delta)
	_bump_boil(delta)
	_fade_music(delta)


## beatHit (line 445) dispatches 'titleBeat' into the script on every beat, and _run_beat is
## this port's side of that. It had no caller: commit affb218 rewrote _process and took the
## driver with it, so the whole 31-beat intro - the BEATS table, the text spelling itself
## out, the bars, the zoom punches - has been dead code ever since. Nothing catches that,
## because the guard only asks whether _finish() leaves the title visible, which it does
## whether or not a single beat ever ran. A render is what showed it: beat=0 in all six
## frames and the text field empty.
##
## The clock is the music's when there is one, so the beats sit on the track rather than on
## whatever the frame rate managed; _elapsed is the fallback for a headless run where the
## audio device will not open.
func _drive_beats() -> void:
	if _done:
		return
	var at: float = _elapsed
	if music != null and music.playing:
		at = music.get_playback_position()
	var beat: int = floori(at * BPM / 60.0)
	while _beat < beat:
		_beat += 1
		_run_beat(_beat)


func _build_particles() -> void:
	if not ResourceLoader.exists(PARTICLE_IMAGE):
		return
	var fx := CPUParticles2D.new()
	fx.name = "TitleParticles"
	fx.texture = load(PARTICLE_IMAGE) as Texture2D
	fx.z_index = -5
	# The emitter spans the screen's width and sits on its bottom edge, which is where a
	# field rising at 750-950 px/s has to start.
	fx.position = Vector2(SCREEN.x * 0.5, SCREEN.y)
	fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fx.emission_rect_extents = Vector2(SCREEN.x * 0.5, 8.0)
	fx.direction = Vector2(0.0, -1.0)
	fx.spread = 0.0
	fx.gravity = Vector2.ZERO
	fx.initial_velocity_min = PARTICLE_RISE.x * FUNKIN_TO_RUBICON
	fx.initial_velocity_max = PARTICLE_RISE.y * FUNKIN_TO_RUBICON
	fx.linear_accel_min = -PARTICLE_DRIFT
	fx.linear_accel_max = PARTICLE_DRIFT
	fx.scale_amount_min = PARTICLE_SCALE.x * FUNKIN_TO_RUBICON
	fx.scale_amount_max = PARTICLE_SCALE.x * FUNKIN_TO_RUBICON
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, PARTICLE_SCALE.y / PARTICLE_SCALE.x))
	fx.scale_amount_curve = shrink
	# start(false, 0.09): one particle every 0.09s rather than a burst.
	fx.lifetime = SCREEN.y / (PARTICLE_RISE.x * FUNKIN_TO_RUBICON)
	fx.amount = maxi(1, int(fx.lifetime / PARTICLE_FREQUENCY))
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray(PARTICLE_COLOURS)
	fx.color_ramp = ramp
	fx.emitting = true
	add_child(fx)
	move_child(fx, 1)


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


## update() line 369 (0x2b2a174), and it is unconditional - there is no skip. The
## "skipped when [this + 0x158] != 0 (follows_singer)" this port used to carry was a
## misreading: __GetFields names TitleScreen's members, and 0x158 is `lerpOutroFactor`, a
## double used as the WEIGHT of the scrollAngle lerp below. Nothing about the zoom.
##
##     camera.zoom = 0.885 + (camera.zoom - 0.885) * exp(-3.125 * elapsed)
##
## Note there is no `addsd %xmm0,%xmm0` here, unlike MainMenuScreen's updateCameraZoom - so
## the rate really is -3.125 on this screen and -6.25 on that one.
##
## Line 365 is the part that was missing entirely: the camera never stops moving.
##
##     var t = FlxG.game.ticks * (1/24);
##     var wobble = Math.sin(t / 15 / Math.PI) + Math.sin(t / Math.PI) / 5;
##     camera.scrollAngle = wobble + (outroAngle - wobble) * lerpOutroFactor;
##
## FlxG.game.ticks is milliseconds, so the slow term turns over about every seven seconds
## and the fast one about every half second - a degree of sway with a fifth of a degree of
## flutter on top. `lerpOutroFactor` is 0 for the whole screen and only ramps during the
## outro, when it pulls the angle to `outroAngle`; until then the wobble is the whole of it.
const ANGLE_SLOW := 15.0
const ANGLE_FAST_DIV := 5.0
const TICKS_PER_UNIT := 24.0


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var current: float = camera.zoom.x
	var factor: float = exp(CAMERA_LERP_RATE * delta)
	var target: float = CAMERA_LERP_TARGET + (current - CAMERA_LERP_TARGET) * factor
	camera.zoom = Vector2(target, target)

	var t: float = float(Time.get_ticks_msec()) / TICKS_PER_UNIT
	var wobble: float = sin(t / ANGLE_SLOW / PI) + sin(t / PI) / ANGLE_FAST_DIV
	# flixel's scrollAngle is degrees; Godot's rotation is radians.
	camera.rotation = deg_to_rad(lerpf(wobble, _outro_angle, _lerp_outro_factor))


## `outroAngle` (0x160, an Int) and `lerpOutroFactor` (0x158), reset together at 0x2b254b4:
## the factor to 0 and the angle to `FlxG.random.int(-10, 0) * 2` - the `add %eax,%eax` right
## after the call is the doubling. So the camera swings to somewhere between 0 and -20 degrees
## on the way out, and which one is rolled per visit.
var _outro_angle: float = 0.0
var _lerp_outro_factor: float = 0.0


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
	# nonIntroGroup - the group whose whole point is that it is not the intro.
	var non_intro: Node2D = get_node_or_null(^"NonIntro") as Node2D
	if non_intro != null:
		non_intro.visible = true

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
	# gfLoveJingle goes through playMusic with only overrideExisting and restartTrack
	# (0x2b24a6a/0x2b24a81) - no volume override, so it plays at full.
	if ResourceLoader.exists(JINGLE_PATH):
		_jingle_player.stream = load(JINGLE_PATH)
		_jingle_player.volume_db = 0.0
		_jingle_player.play()
	if ResourceLoader.exists(CONFIRM_SOUND_PATH):
		_confirm_player.stream = load(CONFIRM_SOUND_PATH)
		_confirm_player.volume_db = linear_to_db(CONFIRM_VOLUME)
		_confirm_player.play()


## Cheat code: from the binary's codePress/cheatCodeShit system.
func _check_cheat_code(keycode: int) -> void:
	if _cheat_index >= CHEAT_CODE.size():
		return
	var wanted: int = CHEAT_CODE[_cheat_index]
	var accepted: Array = [wanted]
	accepted.append_array(CHEAT_ALIASES.get(wanted, []))
	if accepted.has(keycode):
		_cheat_index += 1
		if _cheat_index >= CHEAT_CODE.size():
			_playing_love_jingle = true
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
## update()'s confirm branch, lines 404-439, which this port jumped straight past:
##
##     404  pressEnterText.animation.play('press');
##     405  FlxG.camera.flash(<colour>, 0.75);
##     407  FunkinSound.playOnce(Paths.sound('confirmMenu'), 0.7);
##          transition = true;                                   // field 0xd1
##     410  FlxTween.tween(<a>, {y: <a>.y + 600}, 1.8, {ease: cubeIn});
##     416  new FlxTimer().start(0.5, ...);
##     420  var r0 = FlxG.random.float(0.25, 1.75);   // and r1, r2 the same
##     424  FlxTween.num(0, 1, 1.8, {ease: cubeIn}, <the driver at 0x2b213a0>);
##     434  FlxTween.tween(<b>, {y: <b>.y - 100}, ..., {ease: cubeIn});
##     439  moveToMain();
##
## So confirming is a second and eight tenths of animation, not a scene change. The driver
## closure (line 427) runs one formula three times, once per random: a `pow` curve keyed on
## `1.5 * progress` against 0.75, times **1400**, times that sprite's random - the three
## title pieces are flung off screen at different speeds. Those three are `fallBF`, `fallGF`
## and `logoTV` from the field list, and this scene has only a Logo, so the fling is written
## down rather than faked; it needs create() read and the sprites built first.
##
## What IS ported is the shape: the press animation, the flash, the sound, the camera swing,
## and the 1.8s before the scene changes.
const OUTRO_SECONDS := 1.8
const CONFIRM_FLASH := 0.75
## The three flung pieces travel up to 1400 scaled by their own FlxG.random.float(0.25, 1.75).
const OUTRO_THROW := 1400.0
const OUTRO_SPREAD := Vector2(0.25, 1.75)
## The exponent the driver's `pow` is given, loaded right beside the comparison it guards.
const OUTRO_THROW_POWER := 0.75


## destroy() (0x2b2bc20, line 488): super.destroy(), a FlxSound cleanup, and then
##
##     if (playingLoveJingle)
##         FunkinSound.playMusic(Constants.defaultThemeTrack,
##                               {overrideExisting: true, restartTrack: true});
##
## - leaving the title while the cheat's jingle is playing puts the normal theme back, so the
## next screen does not inherit it. This port had no teardown here at all.
## The driver at 0x2b213a0, once per piece. What the assembly gives exactly: the setter is
## vtable **0x218**, which is `set_y`, so the fling is vertical; the travel is **1400** times
## that piece's own `FlxG.random.float(0.25, 1.75)`; and the curve is a `pow` whose exponent
## is the 0.75 loaded beside it, behind a NaN guard on `1.5 * r`.
##
## How the pow's base and the sprite's resting y combine into the final `set_y` is this
## port's reading - the registers cross a call boundary the dump does not resolve - so it is
## written as `y = rest - 1400 * r * pow(t, 0.75)`, which is the only arrangement of those
## three that leaves the piece at rest when t = 0.
func _fling_pieces() -> void:
	var pieces: Array[Node2D] = []
	var non_intro: Node2D = get_node_or_null(^"NonIntro") as Node2D
	if non_intro != null:
		for child: Node in non_intro.get_children():
			pieces.append(child as Node2D)
	if title != null:
		pieces.append(title.get_node_or_null(^"Logo") as Node2D)

	for piece: Node2D in pieces:
		if piece == null:
			continue
		var rest: float = piece.position.y
		var reach: float = OUTRO_THROW * FUNKIN_TO_RUBICON \
			* randf_range(OUTRO_SPREAD.x, OUTRO_SPREAD.y)
		var fling := create_tween()
		fling.tween_method(
			func(t: float) -> void:
				if is_instance_valid(piece):
					piece.position.y = rest - reach * pow(t, OUTRO_THROW_POWER),
			0.0, 1.0, OUTRO_SECONDS)


func _exit_tree() -> void:
	if not _playing_love_jingle:
		return
	if _jingle_player != null:
		_jingle_player.stop()
	for node: Node in get_tree().get_nodes_in_group("menu_music"):
		var player: AudioStreamPlayer = node as AudioStreamPlayer
		if player != null and not player.playing:
			player.play()


func confirm() -> void:
	if _confirmed or not _done or _elapsed < _ready_at:
		return
	_confirmed = true

	var press: Node = title.get_node_or_null(^"PressEnter") if title != null else null
	if press != null:
		var player: AnimationPlayer = press.get_node_or_null(^"AnimationPlayer")
		if player != null and player.has_animation(&"press"):
			player.play(&"press")

	if _flash_rect != null:
		if _flash_tween != null and _flash_tween.is_valid():
			_flash_tween.kill()
		_flash_rect.modulate.a = 1.0
		_flash_tween = create_tween()
		_flash_tween.tween_property(_flash_rect, "modulate:a", 0.0, CONFIRM_FLASH)

	if ResourceLoader.exists(CONFIRM_SOUND_PATH):
		_confirm_player.stream = load(CONFIRM_SOUND_PATH)
		_confirm_player.volume_db = linear_to_db(CONFIRM_VOLUME)
		_confirm_player.play()

	# FlxTween.num(0, 1, 1.8, {ease: cubeIn}) - the progress the whole outro reads, and the
	# weight that swings the camera from its wobble to outroAngle.
	var outro := create_tween()
	outro.tween_property(self, "_lerp_outro_factor", 1.0, OUTRO_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	_fling_pieces()

	await get_tree().create_timer(OUTRO_SECONDS).timeout
	if not is_inside_tree():
		return
	if music != null:
		music.stop()
	get_tree().change_scene_to_file(NEXT_SCENE)
