extends Node2D
## The main menu.
##
## `animania.states.MainMenuScreen` is compiled, so unlike the title's intro this is read
## out of the Linux build rather than transcribed. What ships as data, and is therefore
## exact, is the LAYOUT: every button has a `butts/<name>.json` with an id and a rect, and
## the eight animations come out of one Adobe atlas. See animania_mod/source/README.md.

## MainMenuScreen.BUTTONS_LIST, in order. Its array lives in .bss and is filled at runtime,
## so it is read out of the global initialiser for MainMenuScreen.cpp, which writes one
## 16-byte String per entry - length first, pointer second. The lengths alone nearly name
## them (9, 4, 8, 7, 7, 7, 6, 4) and the pointers close it. It matches the ids 0..7 the
## JSONs carry, which is a second source agreeing.
const BUTTONS: PackedStringArray = [
	"storymode", "shop", "freeplay", "website", "options", "credits", "awards", "exit",
]

## MainMenuScreen.BLOCKED_BUTTONS - three names, sharing pointers with BUTTONS_LIST[1], [3]
## and [6]. `button_lock.png` is the art for them. They are SKIPPED by the walk rather than
## merely refused, which is what changeItem's loop over BUTTONS_LIST is doing.
const BLOCKED: PackedStringArray = ["shop", "website", "awards"]

## Which of the eight this port can actually reach. The rest are menus that do not exist
## here yet; a button that leads nowhere is left selectable and does nothing, because
## hiding it would change a layout that is measured.
const DESTINATIONS := {
	"storymode": "res://animania_mod/menus/story/story_menu.tscn",
	"freeplay": "res://animania_mod/menus/freeplay/freeplay_screen.tscn",
	"credits": "res://animania_mod/menus/credits/credits_menu.tscn",
	"options": "res://animania_mod/menus/options/options_screen.tscn",
}

## `changeItem(amount:Int, playSound:Bool)`. NOT a direction pair, which is what the two
## `Dynamic` parameters first suggested: handleInput passes `Dynamic(-1), Dynamic(true)` on
## one branch and `Dynamic(-FlxG.mouse.wheel), Dynamic(true)` on the other, so the second is
## a bool and the walk is over the LIST, not over the grid the rects draw.
## Funkin is 1280x720 and this project 1920x1080.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
## doSelect's own sound, and the one a blocked button gets.
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
## handleInput's BACK branch plays `cancelMenu` (0x180f370).
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"

## doSelect does NOT start the transition. Its forEach closure (0x18051a0) plays `confirm`
## on the chosen button and arms `new FlxTimer().start(1.0, ...)` at 0x180531a - a flat one
## second, not the 18/24 the animation's own frame count suggests - and only that timer's
## closure picks the destination and calls startTransitionToMenu. So the confirm and the
## exit are two waits back to back, 1.0 then 0.75, and this port had them fused into one
## 0.75 that cut the confirm animation off a quarter of the way in.
const CONFIRM_SECONDS := 1.0

## The menu breathes on the beat. animaniaLOOP's own metadata says 102 BPM, 4/4 - the same
## tempo the title's intro runs at, which is the track this one loops into.
const BPM := 102.0

## beatHit does `camera.zoom += 0.005` on the game camera, and updateCameraZoom(elapsed)
## eases it back:
##
##     zoom = target + (zoom - target) * exp(-6.25 * elapsed)
##
## read straight off the arithmetic - a mulsd by -3.125, an addsd of the result to itself,
## an exp, then (zoom - target) * that + target. A half-life of 0.111s, so it is a punch and
## not a sway.
##
## The mod's target is 0.885. This port rests at 1.0 instead, because 0.885 is the zoom the
## MOD's own framing is built around and this scene's framing was settled by looking at it.
## What is ported is the MOTION - a bump of half a percent decaying at the same rate - and
## on a base of 1.0 against their 0.885 that is the same half percent either way.
const ZOOM_DECAY := 6.25
const ZOOM_REST := 1.0

## updateButtonsAnimation does not let the buttons' animations run themselves. Every frame
## it overwrites each one's current frame from ONE clock:
##
##     curAnim.curFrame = Std.int(FlxG.game.ticks / 24 * 0.6) % curAnim.frames.length
##
## - a multiply by 1/24 and then by 0.6, which is 0.025 frames per millisecond, so 25 fps,
## and `ticks` is the game's own elapsed milliseconds. The point is not the rate but the
## SHARE: all eight read the same clock, so they stay in step however often the selection
## moves them between `basic` and `white`, where eight independent players drift apart the
## first time one of them restarts.
##
## A button whose current animation is named `confirm` is exempt - the walk skips it - and
## that one does play out on its own.
const IDLE_FPS := 25.0

## startIntroAnimation, whole. The camera comes in at three times its size, off centre and
## off square, and settles; two black curtains that cover the screen open off the top and
## the bottom and leave a band of each showing.
##
## Straight off the compiled method, in Funkin's 1280x720:
##
##     FlxG.camera.zoom = 3
##     FlxG.camera.scrollAngle = FlxG.random.float(-10, 10)
##     FlxG.camera.scroll.x = FlxG.random.float(-200, 200)   (and .y the same)
##     FlxTween.tween(blackLineUp,   {y: 30 - blackLineUp.height}, 1,    smootherStepOut)
##     FlxTween.tween(blackLineDown, {y: 690},                     1,    smootherStepOut)
##     FlxTween.tween(FlxG.camera,   {zoom: 0.9, scrollAngle: 0},  0.75, smootherStepInOut)
##
## 690 is 720 - 30, so both curtains settle showing the same 30px band. The curtains are
## FunkinSprites made solid 0xFF000000, Std.int(FlxG.width * 1.25) wide by FlxG.height tall
## - a whole screen each, and wider than one so the angle and the offset cannot uncover an
## edge. That they START at y = 0 is the one reading here: it is the only y that makes
## these two tweens an opening rather than a closing.
##
## The camera tween is the one with an onComplete, and the menu goes live when it lands -
## 0.75s, while the curtains are still moving.
const INTRO_CURTAIN := 1.0
const INTRO_CAMERA := 0.75
## 30px of curtain left showing, in this project's 1.5x of Funkin's space.
const INTRO_BAND := 30.0 * 1920.0 / 1280.0
const INTRO_ANGLE := 10.0
const INTRO_SCROLL := 200.0 * 1920.0 / 1280.0
## The mod's zoom numbers are all against ITS resting 0.885 (see ZOOM_REST), so what
## carries over is the ratio: three and a bit times the resting size down to a touch over.
## The intro comes in from three times the resting size and lands ON it. The mod's 3.0 and
## 0.9 are camera zooms against its own 1280x720; here the 0.9 lives in the scene's
## AUTHORED_SCALE instead (see build_main_menu.gd), so what is left for the camera is the
## RATIO - and the resting end of it is 1. Leaving it at 0.9/0.885 rested the menu 1.7%
## zoomed in, on top of a layout that was already scaled wrong.
const INTRO_ZOOM_FROM := 3.0 / 0.9
const INTRO_ZOOM_TO := 1.0

## startTransitionToMenu, which is the intro run backwards. Its default duration is 0.75 -
## the same 0.75 the confirm animation takes, so the two are one gesture:
##
##     FlxTween.tween(menuDude,      {x: menuDude.x - 650},              d, backInOut)
##     FlxTween.tween(blackLineUp,   {y: 10 - blackLineUp.height * 0.5}, d, smootherStepOut)
##     FlxTween.tween(blackLineDown, {y: 350},                           d, smootherStepOut)
##     FlxTween.tween(FlxG.camera,   {zoom: 3, scrollAngle: float(-10, 10)},  d, smootherStepInOut)
##     FlxTween.tween(FlxG.camera.scroll, {x: float(-200,200), y: float(-200,200)}, d, smootherStepInOut)
##     new FlxTimer().start(d, _ -> switch state)
##
## The curtains close onto each other: -350 and 350 with a screen of height each, which
## overlap by 20px in the middle and cover everything. Same numbers as the opening, and the
## same 1.5x into this project's space.
const EXIT_SECONDS := 0.75
const EXIT_DUDE := 650.0 * 1920.0 / 1280.0
const EXIT_CURTAIN_UP := 10.0 * 1920.0 / 1280.0
const EXIT_CURTAIN_DOWN := 350.0 * 1920.0 / 1280.0

@export var buttons: Node2D
@export var sfx: AudioStreamPlayer
## The looping menu track, which is also the clock the beat comes off.
@export var music: AudioStreamPlayer
@export var camera: Camera2D
## The two black curtains, in world space like the mod's: they do not follow the camera,
## which is why they are wider than the screen.
@export var curtain_up: Control
@export var curtain_down: Control
## He is the only thing on the screen the exit moves besides the curtains and the camera.
@export var dude: Node2D

## `curSelected` is a class STATIC (0x7e568a8), and the only place that writes 0 to it is
## `__boot()` - once, when the program starts. `__construct` does not touch it. So it
## survives leaving the menu and coming back: go into freeplay, come back, and the plaque
## you left from is still the one lit up. This port had it as an instance field, so every
## return to the menu snapped back to storymode.
static var _selected: int = 0
var _confirmed: bool = false
var _beat: int = -1
## Which state each button is showing, so the idle driver knows what to skip and how long
## the cycle it is winding is.
var _state: Dictionary = {}
var _nodes: Dictionary = {}
## Seconds since startIntroAnimation, or -1 once both its tweens have landed.
var _intro: float = 0.0
var _intro_zoom: float = 1.0
var _intro_angle: float = 0.0
var _intro_offset := Vector2.ZERO
## Seconds into startTransitionToMenu, or -1 while it is not running.
var _exit: float = -1.0
var _story_select: Node = null
var _exit_dude: float = 0.0
var _exit_zoom: float = 1.0
var _exit_up: float = 0.0
var _exit_down: float = 0.0
var _exit_angle: float = 0.0
var _exit_offset := Vector2.ZERO


func _ready() -> void:
	_finalize_setup()
	# finalizeSetup line 611 (0x1803c57) is `changeItem()` with both defaults - huh = 0 and
	# no blocked skip. The wrap moves nothing, but everything past it still runs: the
	# forEach paints the selection, and line 849 has already made `huh` a hard +1 by the
	# time line 853 asks whether to play the sound, so the mod really does click once as
	# the menu opens.
	_refresh()
	_play(SOUND_SWITCH)
	_start_intro()


func _start_intro() -> void:
	_intro = 0.0
	if camera != null:
		camera.zoom = Vector2.ONE * ZOOM_REST * INTRO_ZOOM_FROM
		camera.rotation = deg_to_rad(randf_range(-INTRO_ANGLE, INTRO_ANGLE))
		camera.offset = Vector2(
			randf_range(-INTRO_SCROLL, INTRO_SCROLL),
			randf_range(-INTRO_SCROLL, INTRO_SCROLL))
		_intro_zoom = camera.zoom.x
		_intro_angle = camera.rotation
		_intro_offset = camera.offset
	if curtain_up != null:
		curtain_up.position.y = 0.0
	if curtain_down != null:
		curtain_down.position.y = 0.0
	_advance_intro(0.0)


## Both intro tweens, on their own clock rather than on a Tween: the two eases are
## polynomials the mod spells out and a Godot transition is a different curve, so the
## motion is only the same if it is the same arithmetic.
func _advance_intro(delta: float) -> void:
	_intro += delta

	var opening: float = _smoother_step_out(clampf(_intro / INTRO_CURTAIN, 0.0, 1.0))
	if curtain_up != null:
		curtain_up.position.y = -(curtain_up.size.y - INTRO_BAND) * opening
	if curtain_down != null:
		curtain_down.position.y = (curtain_down.size.y - INTRO_BAND) * opening

	var settling: float = _smoother_step(clampf(_intro / INTRO_CAMERA, 0.0, 1.0))
	if camera != null:
		camera.zoom = Vector2.ONE * lerpf(
			_intro_zoom, ZOOM_REST * INTRO_ZOOM_TO, settling)
		camera.rotation = lerpf(_intro_angle, 0.0, settling)
		camera.offset = _intro_offset.lerp(Vector2.ZERO, settling)

	if _intro >= maxf(INTRO_CURTAIN, INTRO_CAMERA):
		_intro = -1.0


## FlxEase.smootherStep: t*t*t*(t*(t*6 - 15) + 10), read off the 6, 15 and 10 in .rodata.
## smootherStepInOut is this one unchanged.
func _smoother_step(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## FlxEase.smootherStepOut: the same curve over its second half, stretched back out.
func _smoother_step_out(t: float) -> float:
	return 2.0 * _smoother_step(t * 0.5 + 0.5) - 1.0


## FlxEase.backInOut, with the 2.70158 and the 1.70158 read out of .rodata.
func _back_in_out(t: float) -> float:
	var at: float = t * 2.0
	if at < 1.0:
		return at * at * (2.70158 * at - 1.70158) * 0.5
	at -= 2.0
	return (at * at * (2.70158 * at + 1.70158) + 2.0) * 0.5


func _start_exit() -> void:
	_exit = 0.0
	_exit_dude = dude.position.x if dude != null else 0.0
	_exit_up = curtain_up.position.y if curtain_up != null else 0.0
	_exit_down = curtain_down.position.y if curtain_down != null else 0.0
	if camera != null:
		_exit_zoom = camera.zoom.x
		_exit_angle = deg_to_rad(randf_range(-INTRO_ANGLE, INTRO_ANGLE))
		_exit_offset = Vector2(
			randf_range(-INTRO_SCROLL, INTRO_SCROLL),
			randf_range(-INTRO_SCROLL, INTRO_SCROLL))
	_advance_exit(0.0)


## Note it does NOT stop at the end: it holds on the last frame until the scene changes,
## because letting it fall through would hand the camera straight back to the beat's decay
## and undo the zoom in the frames before the switch.
func _advance_exit(delta: float) -> void:
	_exit += delta
	var t: float = clampf(_exit / EXIT_SECONDS, 0.0, 1.0)

	if dude != null:
		dude.position.x = lerpf(_exit_dude, _exit_dude - EXIT_DUDE, _back_in_out(t))

	var closing: float = _smoother_step_out(t)
	if curtain_up != null:
		curtain_up.position.y = lerpf(
			_exit_up, EXIT_CURTAIN_UP - curtain_up.size.y * 0.5, closing)
	if curtain_down != null:
		curtain_down.position.y = lerpf(_exit_down, EXIT_CURTAIN_DOWN, closing)

	var leaving: float = _smoother_step(t)
	if camera != null:
		camera.zoom = Vector2.ONE * lerpf(
			_exit_zoom, ZOOM_REST * INTRO_ZOOM_FROM, leaving)
		camera.rotation = lerpf(0.0, _exit_angle, leaving)
		camera.offset = Vector2.ZERO.lerp(_exit_offset, leaving)


## Whether the menu answers yet. The mod turns it on in the camera tween's onComplete.
func _live() -> bool:
	return _intro < 0.0 or _intro >= INTRO_CAMERA


## beatHit, off the music's own playback rather than off a counter: a counter drifts from
## the track it is supposed to be following, and the track is the only clock this screen has.
func _process(delta: float) -> void:
	_drive_idles()

	if _exit >= 0.0:
		_advance_exit(delta)
		return

	if _intro >= 0.0:
		_advance_intro(delta)
		_apply_parallax()
		return

	if camera != null:
		camera.zoom = Vector2.ONE * (ZOOM_REST
			+ (camera.zoom.x - ZOOM_REST) * exp(-ZOOM_DECAY * delta))
	_update_camera_scroll(delta)
	_apply_parallax()

	if music == null or not music.playing:
		return
	var beat: int = floori(music.get_playback_position() * BPM / 60.0)
	if beat == _beat:
		return
	_beat = beat
	_beat_hit(beat)


## beatHit (0x1812be0), which this port had as one flat bump on every beat. It is three
## bumps under two conditions, and the second condition is a SECTION OF THE TRACK:
##
##     if (music.volume <= 0.1) return                       (0x1812cc8)
##     inDrop = music.time > 50750 && music.time < 93000     (0x181302b / 0x1813052)
##     if ((beat & 1) == 0 || inDrop)  camera.zoom += 0.005  (0x1812f4a)
##     if ((beat & 3) == 0 || inDrop)  camera.zoom += 0.001  (0x1812eb5)
##     if (inDrop)                     camera.zoom += 0.001  (0x1812ef4)
##
## So outside the drop the menu breathes on the EVEN beats only, at 0.005, with an extra
## 0.001 every fourth; inside it every beat gets all three. A flat 0.005 everywhere punched
## on the off-beats, which is the half of it that reads as wrong against the music.
const BEAT_ZOOM_MAIN := 0.005
const BEAT_ZOOM_EXTRA := 0.001
const BEAT_VOLUME_GATE := 0.1
const DROP_FROM := 50.750
const DROP_TO := 93.0


func _beat_hit(beat: int) -> void:
	if camera == null or music == null:
		return
	if db_to_linear(music.volume_db) <= BEAT_VOLUME_GATE:
		return
	var at: float = music.get_playback_position()
	var in_drop: bool = at > DROP_FROM and at < DROP_TO
	if beat % 2 == 0 or in_drop:
		camera.zoom += Vector2.ONE * BEAT_ZOOM_MAIN
	if beat % 4 == 0 or in_drop:
		camera.zoom += Vector2.ONE * BEAT_ZOOM_EXTRA
	if in_drop:
		camera.zoom += Vector2.ONE * BEAT_ZOOM_EXTRA


## `changeItem(huh:Int = 0, skipBlocked:Bool = false)` - 0x17fd6b0, read line by line:
##
##     844  if (huh == -444) { curSelected = -1; }        // and nothing else: see deselect()
##     848  else curSelected = FlxMath.wrap(curSelected + Std.int(huh), 0, len - 1);
##     849       huh = huh < 0 ? -1 : 1;                  // the step, for the loop below
##     851       if (skipBlocked) while (BLOCKED_BUTTONS.contains(BUTTONS_LIST[curSelected]))
##                    goto 848;                           // re-wrap by that step
##     853       if (huh != 0) FunkinSound.playOnce(Paths.sound('animania/menu/menu_switch'));
##     859  <the forEach and the sort: see _refresh()>
##
## The second `Dynamic` is NOT a play-sound flag - the sound is unconditional past line 853,
## because 849 has already made `huh` a hard +-1. It gates the blocked-button SKIP, and it
## defaults to FALSE (0x17fdde7 builds `Dynamic(false)` for the missing argument). handleInput
## passes true on every keyboard and wheel branch (0x180f1da, 0x180f2c9); the mouse callbacks
## pass nothing, because they are jumping straight to the button under the pointer and a
## blocked button never has a mouse callback in the first place (createButtons sends those to
## createBlockedButton instead, 0x18075b7).
##
## Deaf until the intro's CAMERA tween lands - `_live()` - and not until the curtains stop:
## the mod only reaches changeItem through handleInput, and update() stops calling
## handleInput when that tween's onComplete fires at 0.75s, a quarter of a second before the
## curtains finish. The guard used to look at whatever moment the frames happened to land on
## and call it "during the intro"; it names the moment now.
func change_item(amount: int, skip_blocked: bool = false) -> void:
	if _confirmed or not _live():
		return
	# `amount == 0` is NOT refused: finalizeSetup calls changeItem() with the defaults to
	# paint the first selection, and handleInput calls changeItem(0, true) to land on the
	# last button from nothing at all. Only line 848's wrap decides whether anything moves.
	var step: int = 1 if amount >= 0 else -1
	var at: int = wrapi(_selected + amount, 0, BUTTONS.size())
	if skip_blocked:
		# At most one full lap: if every other button were blocked this would otherwise spin.
		for _i: int in BUTTONS.size():
			if not BLOCKED.has(BUTTONS[at]):
				break
			at = wrapi(at + step, 0, BUTTONS.size())
		if BLOCKED.has(BUTTONS[at]):
			return
	if at == _selected:
		return
	_selected = at
	_refresh()
	_play(SOUND_SWITCH)


## changeItem's -444 branch (the compare at 0x17fd727). The sentinel means "nothing is
## selected": curSelected goes to -1, the forEach below drops every plaque back to `basic`,
## and the switch sound is skipped because the whole arithmetic between is jumped over.
##
## A button's onMouseOut sends it (0x17ff459) when the pointer leaves the button that WAS
## selected, so on a desktop the menu really does go blank between plaques.
func deselect() -> void:
	if _confirmed or _selected < 0:
		return
	_selected = -1
	_refresh()


## `doSelect(id:Int)` - 0x1805510:
##
##     883  if (id < 0 || !canInteract) return;
##     885  canInteract = false;
##     886  FunkinSound.playOnce(Paths.sound('confirmMenu'));
##     889  if (menuMusic != null) menuMusic.fadeOut(0.15, 0);     // the inlined FlxSound body
##     891  var name = buttons.members[curSelected].<data>.name;
##     892  buttons.forEach(function(b) { if (b.ID == curSelected) {
##     896      b.playAnim('confirm');
##     898      new FlxTimer().start(1.0, <the dispatcher>); } }, true);
##
## `id < 0` is not defensive: onMouseOut leaves curSelected at -1 (see deselect()), and the
## keyboard's ACCEPT branch passes it straight through, so a confirm with nothing hovered has
## to be a no-op. GDScript's negative indexing would have picked BUTTONS[-1] - `exit` - and
## quit the game.
##
## There is no blocked-button test anywhere in doSelect. There does not need to be one: a
## blocked button has no mouse callback and the keyboard walk skips it. The SOUND_LOCKED
## branch below is this port's own, kept because a tap on a phone can land on a rect the
## mouse never could.
func do_select() -> void:
	if _selected < 0 or _confirmed or not _live():
		return
	var name: String = BUTTONS[_selected]
	if BLOCKED.has(name):
		_play(SOUND_LOCKED)
		return

	_confirmed = true
	_play(SOUND_CONFIRM)
	_animate(name, "confirm")

	# The confirm animation gets its whole second before anything else moves. The mod's
	# dispatcher only runs when that FlxTimer fires.
	await get_tree().create_timer(CONFIRM_SECONDS).timeout
	if not is_inside_tree():
		return

	# Story mode does not go straight to the story menu, and it does not run the curtain
	# exit either: the dispatcher tests the pressed button's name against "storymode"
	# (0x5a7e5e7) and allocates StoryMenuSelectSubState (0x180b180) on the spot, over a menu
	# that is still standing. The sub-state calls back with startTransitionToMenu once a
	# side is picked.
	if name == "storymode":
		_open_story_select()
		return

	if not DESTINATIONS.has(name):
		# Nowhere to go yet. The plaque drops back out of `confirm` and the menu is live
		# again; a button that is not ported reads as "not yet" instead of as a freeze.
		_confirmed = false
		_refresh()
		return

	# Only freeplay and options reach startTransitionToMenu in the mod (0x180ad15 and
	# 0x180af65). credits opens a StickerSubState instead and exit runs the audio-filter
	# ramp; this port sends both through the same curtain, which is the transition it has.
	_start_exit()
	await get_tree().create_timer(EXIT_SECONDS).timeout
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(String(DESTINATIONS[name]))


## doSelect line 889 IS a fade - the inlined FlxSound.fadeOut body at 0x18056db: cancel the
## old tween, take the current volume, FlxTween.num(volume, 0, 0.15) with `volumeTween` as
## the setter. But it is NOT the menu music. The field is 0x190, and __GetFields names the
## pointer block: it is `musicLayerSound`, the extra stem. And updateSeasonalEffects line 750
## does `musicLayerSound.volume = FlxG.sound.music.volume` EVERY FRAME, unconditionally
## (0x17fd129, set_volume through vtable 0x1b8).
##
## Flixel updates FlxG.plugins - where the tween managers live - BEFORE the state, so the
## per-frame assignment lands after the tween's and wins it every frame. The fade never
## reaches the speakers in this build. So there is nothing to port: the menu music runs at
## full volume straight through the confirm and the transition, and this port briefly faded
## it because the field had not been named yet.


const STORY_SELECT := "res://animania_mod/menus/story_select/story_menu_select_sub_state.gd"


func _open_story_select() -> void:
	if _story_select != null:
		return
	_story_select = load(STORY_SELECT).new()
	_story_select._menu_state = self
	add_child(_story_select)
	_story_select.tree_exited.connect(func() -> void:
		_story_select = null
		# Backing out of the picker puts the menu back the way it was. Nothing had moved -
		# the picker opens over a menu that is still standing, with no curtain run - so this
		# only has to take the plaque back out of `confirm`.
		if is_inside_tree() and _confirmed:
			_confirmed = false
			_refresh())


## Called by StoryMenuSelectSubState once a side is picked - the mod's
## startTransitionToMenu, which is a method of the MAIN MENU, not of the story
## menu. Only the amtake side is unlocked, in the mod as here.
func start_story(_variant: String) -> void:
	get_tree().change_scene_to_file(String(DESTINATIONS["storymode"]))


## changeItem's tail: the forEach at line 859 (closure body 0x1806500) and the sort at line
## 872, which the mod runs together on every selection change.
##
##     if (button.ID == curSelected) { button.playAnim('white'); button.zIndex = 0; }
##     else                          { button.playAnim('basic'); button.zIndex = ~button.ID; }
##     ...
##     buttons.members.sort(sortByZ, FlxSort.ASCENDING)
##
## `~ID` is the bitwise NOT, so button 0 sits at -1, button 1 at -2 and so on, and the
## selected one at 0 sorts last - it draws over its neighbours. That matters here because
## the `white` plaque is BIGGER than the `basic` one: without the raise it slides under the
## button below it. This port set no key at all, so _sort_by_z() was reordering eight nodes
## that all compared equal and the raise never happened.
func _refresh() -> void:
	for i: int in BUTTONS.size():
		_animate(BUTTONS[i], "white" if i == _selected else "basic")
		var node: Node = _button_node(BUTTONS[i])
		if node != null:
			node.set_meta(&"sort_z", 0 if i == _selected else ~i)
	_sort_by_z()


func _animate(name: String, state: String) -> void:
	var node: Node = _button_node(name)
	if node == null:
		return
	_state[name] = state

	var player: AnimationPlayer = node.get_node_or_null(^"AnimationPlayer")
	var animation := StringName("menu_buttons_%s_%s" % [name, state])
	if state == "confirm":
		if player != null and player.has_animation(animation):
			player.play(animation)
		return

	# The idles never run on the player: _drive_idles owns their frame, and a player
	# writing the same property would be fighting it for the answer.
	if player != null:
		player.stop()
	var states: Dictionary = node.get_meta(&"states", {})
	if states.has(state):
		node.set(&"symbol", String((states[state] as Dictionary)["symbol"]))


## updateButtonsAnimation, once per frame. Every button not playing its confirm reads the
## same clock, so they cycle together.
func _drive_idles() -> void:
	var phase: int = floori(Time.get_ticks_msec() * IDLE_FPS / 1000.0)
	for name: String in BUTTONS:
		var state: String = String(_state.get(name, "basic"))
		if state == "confirm":
			continue
		var node: Node = _button_node(name)
		if node == null:
			continue
		var states: Dictionary = node.get_meta(&"states", {})
		if not states.has(state):
			continue
		var count: int = int((states[state] as Dictionary)["frames"])
		if count > 0:
			node.set(&"frame", phase % count)


## The button nodes by name, looked up once. _drive_idles walks all eight every frame.
func _button_node(name: String) -> Node:
	if _nodes.has(name):
		return _nodes[name] as Node
	var node: Node = null if buttons == null \
		else buttons.get_node_or_null(NodePath(name.capitalize()))
	_nodes[name] = node
	return node


func _play(path: String) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()




var _changelog_sub_state: CanvasLayer = null


func _open_changelog() -> void:
	if _changelog_sub_state != null:
		return
	_changelog_sub_state = preload("res://animania_mod/menus/changelog/changelog_sub_state.gd").new()
	add_child(_changelog_sub_state)
	_changelog_sub_state.tree_exited.connect(func() -> void: _changelog_sub_state = null)


## createNewsButton (0x18017a0) loads menus/changelog/news_button, an Animate atlas with
## the frame labels "loop white", "loop white2" and "open", and slides it in from 350 with
## a delayed tween. It does NOT touch new_update_bub: that strip is 1184x106 of the word
## UPDATE repeated, a marquee, and the port was hanging it off the button unscaled - which
## is where the three giant UPDATEs across the middle of the menu came from.
##
## And the art settles a question this port had open for a whole session: the banner is an
## ENVELOPE with a red seal, which is exactly the thing sitting at the bottom-left of the
## mod's capture that nothing in create() seemed to make. It is this. The remaining
## disagreement is how far in it comes - the binary seats it at x = -70 and the capture has
## it about a hundred further right, the same shape of residual the waveform shows.
## createNewsButton (0x18017a0). The banner is in the scene already - its Animate atlas and
## the three frame-label animations are built by tools/animania/build_news_button.gd - and
## what belongs here is the entrance: the mod parks it 350 further left than its seat
## (0x1801d7e) and tweens it back with expoOut over 0.65s after a 1s delay
## (0x1801df6 / 0x1801e8a), then hangs a click on it that opens the changelog.
const NEWS_SLIDE := 350.0
const NEWS_DELAY := 1.0
const NEWS_TIME := 0.65

var _news_button: Node2D = null


func _create_news_button() -> void:
	_news_button = get_node_or_null("NewsButton") as Node2D
	if _news_button == null:
		return
	var rest: float = _news_button.position.x
	_news_button.position.x = rest - NEWS_SLIDE * FUNKIN_TO_RUBICON
	var slide := create_tween()
	slide.tween_property(_news_button, "position:x", rest, NEWS_TIME) \
		.set_delay(NEWS_DELAY).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)


## createSpecialElements (0x180ec40) is two calls and nothing else: createNewsButton and
## createMusicSocial. The port also drew two black ColorRects over the top and bottom of the
## screen "for depth" - invented, and the top one is the grey band that sat across the
## menu's sky in every render. Gone.
const MUSIC_SOCIAL_FRAMES := "res://animania_mod/source/images/menus/menu/music_social_frames.tres"
## createMusicSocial: scale 0.85 on both axes (0x180e611/0x180e62d), zoomFactor 0.875, and
## the animations "soundtrack basic" (idle), "soundtrack white" (selected) and
## "soundtrack press", all at 24.
const MUSIC_SOCIAL_SCALE := 0.85
## createMusicSocial (0x180e0c2/0x180e0dd) creates the disc at world (570, 590) with a
## 158x134 frame, so Flixel draws it centred on (649, 657). The mod's capture has that
## centre on (645, 620) of a 1278-wide shot. The plate agrees with the binary to within
## seven pixels and the curtains to within four, so the pair below is not a scale or a
## camera - it is one measured offset between this build and that capture, and everything
## this file places against FlxG.width/height takes it so the OST widget stays in one
## piece.
const MUSIC_SOCIAL_WORLD := Vector2(570.0, 590.0)
const MUSIC_SOCIAL_FRAME := Vector2(158.0, 134.0)
const WORLD_OFFSET := Vector2(-4.0, -37.0)
## menus/menu/music_social_lines at (7.5, 625.35) - the two doubles createMusicSocial loads
## right after the disc's scale, first the y then the x, the same order the loading screen's
## FunkinSprite calls take. It is a 661x83 strip that runs from the left edge to just short
## of the disc, and the mod's capture does not show it: showSocialButtons/hideSocialButtons
## and toggleSocialButtons exist, so it belongs to the expanded state, not the resting one.
const MUSIC_LINES := "res://animania_mod/source/images/menus/menu/music_social_lines.png"
const MUSIC_LINES_POS := Vector2(7.5, 625.35)

## createSocialButtons (0x180ce20). Five, not the four this file used to say - amazon is in
## the atlas too - and their seats are a running sum, not five loose numbers: the first is
## at x = 37.3 (0x180d8b7) and each next one starts a full frame width minus six further
## right (0x180d835), all of them on y = 620.9 (0x180d894) at scale 0.85. The last one ends
## at 539, and music_social_lines is 661 wide at 0.85 running from 7.5 to 569 - the strip
## they sit on. That is the check that the sum is read the right way round.
##
## The order is the order the anons are built (0x180ced3 onwards) and the URLs in .rodata
## are in that same order, which is a second source agreeing.
const MUSIC_BUTTONS := "res://animania_mod/source/images/menus/menu/music_social_buttons.png"
const MUSIC_BUTTONS_XML := "res://animania_mod/source/images/menus/menu/music_social_buttons.xml"
const SOCIAL_START_X := 37.3
const SOCIAL_Y := 620.9
const SOCIAL_STEP_TRIM := 6.0
const SOCIAL_SERVICES: Array = [
	["amazon", "https://music.amazon.com/artists/B0DLRGCSTC/animania-crew"],
	["youtube button", "https://www.youtube.com/@animaniacrewyoutube"],
	["soundcloud button", "https://soundcloud.com/animaniacrew"],
	["spotify button", "https://open.spotify.com/artist/2BW1sh84ELs0TO4grqYmT3?si=TuwSLrFMR3uVeswvC_e9aw"],
	["apple music button", "https://music.apple.com/us/artist/animania-crew/1777493090"],
]

var _music_social: AnimatedSprite2D = null
var _music_lines: Sprite2D = null
var _social_buttons: Array[Sprite2D] = []
var _social_open: bool = false


func _create_special_elements() -> void:
	_create_news_button()
	_create_music_social()


func _create_music_social() -> void:
	if not ResourceLoader.exists(MUSIC_SOCIAL_FRAMES):
		return
	_music_social = AnimatedSprite2D.new()
	_music_social.name = "MusicSocial"
	_music_social.centered = true
	_music_social.sprite_frames = load(MUSIC_SOCIAL_FRAMES) as SpriteFrames
	if _music_social.sprite_frames.has_animation(&"soundtrack basic"):
		_music_social.play(&"soundtrack basic")
	_music_social.scale = Vector2.ONE * MUSIC_SOCIAL_SCALE * FUNKIN_TO_RUBICON
	_music_social.position = _world(MUSIC_SOCIAL_WORLD + MUSIC_SOCIAL_FRAME * 0.5)
	add_child(_music_social)

	if ResourceLoader.exists(MUSIC_LINES):
		_music_lines = Sprite2D.new()
		_music_lines.name = "MusicSocialLines"
		_music_lines.centered = false
		_music_lines.texture = load(MUSIC_LINES)
		_music_lines.scale = Vector2.ONE * MUSIC_SOCIAL_SCALE * FUNKIN_TO_RUBICON
		_music_lines.position = _world(MUSIC_LINES_POS)
		_music_lines.visible = false
		add_child(_music_lines)

	_create_social_buttons()


## The mod hides these until the disc is clicked (set_visible(false) at 0x180d665) and hangs
## a FlxMouseEventManager click on each; here the tap goes through _touch like every other
## button on this screen.
func _create_social_buttons() -> void:
	_social_buttons.clear()
	var sheet: Texture2D = load(MUSIC_BUTTONS) as Texture2D
	if sheet == null:
		return
	var regions: Dictionary = _sparrow_regions(MUSIC_BUTTONS_XML)
	var pen: float = SOCIAL_START_X
	for service: Array in SOCIAL_SERVICES:
		var key: String = String(service[0])
		if not regions.has(key):
			continue
		var region: Rect2 = regions[key] as Rect2
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = region

		var button := Sprite2D.new()
		button.name = "Social_" + key
		button.centered = false
		button.texture = atlas
		button.scale = Vector2.ONE * MUSIC_SOCIAL_SCALE * FUNKIN_TO_RUBICON
		button.position = _world(Vector2(pen, SOCIAL_Y))
		button.visible = false
		button.set_meta(&"url", String(service[1]))
		add_child(button)
		_social_buttons.append(button)
		# The step is the UNSCALED frame width: the mod calls updateHitbox before it scales,
		# so `width` is still the atlas frame's when the sum is taken.
		pen += region.size.x - SOCIAL_STEP_TRIM


func _sparrow_regions(path: String) -> Dictionary:
	var out: Dictionary = {}
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		return out
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if parser.get_node_name() != "SubTexture":
			continue
		var raw_name: String = parser.get_named_attribute_value_safe("name")
		var key: String = raw_name.substr(0, raw_name.length() - 4)
		if key.is_empty() or out.has(key):
			continue
		out[key] = Rect2(
			float(parser.get_named_attribute_value_safe("x")),
			float(parser.get_named_attribute_value_safe("y")),
			float(parser.get_named_attribute_value_safe("width")),
			float(parser.get_named_attribute_value_safe("height")))
	return out


## FlxG-space (1280x720) into this scene's 1920x1080, through the one offset the disc fixes.
func _world(p: Vector2) -> Vector2:
	return (p + WORLD_OFFSET) * FUNKIN_TO_RUBICON


## toggleSocialButtons.
func _social_hit(at: Vector2) -> bool:
	if _music_social == null or not _music_social.visible:
		return false
	if _music_social.sprite_frames == null:
		return false
	var tex: Texture2D = _music_social.sprite_frames.get_frame_texture(
		_music_social.animation, 0)
	if tex == null:
		return false
	var half: Vector2 = tex.get_size() * _music_social.scale * 0.5
	return Rect2(_music_social.position - half, half * 2.0).has_point(at)


## The staggered reveal, from showSocialButtons (0x17fc870) and its timer closure
## (0x18081f0). The port used to flip `visible` on all five at once.
##
##     652  showSocialButtons(onDone): new FlxTimer().start(0.1, ...)   // one shot
##     654  for (i in 0...musicSocialButtons.length) {
##     656      button.visible = true; button.scale.set(1, 1); button.setPosition(...)
##     662      var d = 1.0 - i / musicSocialButtons.length;
##     664      FlxTween.tween(button, {x: ..., y: ...}, 0.8,
##                             { ease: backOut, startDelay: (d + 0.2) * 0.8 })
##          }
##
## With five buttons that is 0.96s, 0.80s, 0.64s, 0.48s, 0.32s - the FAR one arrives first
## and the one nearest the disc last, about a sixth of a second apart. hideSocialButtons
## (0x17fcae0) is the same shape.
const SOCIAL_REVEAL_WAIT := 0.1
const SOCIAL_REVEAL_TIME := 0.8
const SOCIAL_REVEAL_BIAS := 0.2
const SOCIAL_REVEAL_SPAN := 0.8

## toggleSocialButtons (0x17fcd00) lines 647-648. Opening and closing are not mirror images:
##
##     FlxTween.tween(newsButton.<0x160>, {x: 500}, 0.7, {ease: cubeIn})    // opening
##     FlxTween.tween(newsButton.<0x160>, {x: 0},   1.3, {ease: cubeOut})   // closing
##
## The target is the news banner (field 0x120, named `newsButton` by __GetFields) - the OST
## row unfolds along the bottom of the screen, which is where the banner sits, so the banner
## is pushed out of the way and takes nearly twice as long to come back.
const NEWS_PUSH := 500.0
const NEWS_PUSH_OUT := 0.7
const NEWS_PUSH_BACK := 1.3
var _social_tween: Tween = null
var _news_push_tween: Tween = null


func _toggle_social() -> void:
	_social_open = not _social_open
	if _music_lines != null:
		_music_lines.visible = _social_open

	if _social_tween != null and _social_tween.is_valid():
		_social_tween.kill()
	var seat: Vector2 = Vector2.ONE * MUSIC_SOCIAL_SCALE * FUNKIN_TO_RUBICON
	if _social_buttons.size() > 0:
		_social_tween = create_tween().set_parallel(true)
		var total: int = _social_buttons.size()
		for i: int in total:
			var button: Sprite2D = _social_buttons[i]
			var delay: float = SOCIAL_REVEAL_WAIT \
				+ (1.0 - float(i) / float(total) + SOCIAL_REVEAL_BIAS) * SOCIAL_REVEAL_SPAN
			if _social_open:
				button.visible = true
				button.scale = Vector2.ZERO
			var step: PropertyTweener = _social_tween.tween_property(
				button, "scale", seat if _social_open else Vector2.ZERO,
				SOCIAL_REVEAL_TIME)
			step.set_delay(delay).set_trans(Tween.TRANS_BACK)
			step.set_ease(Tween.EASE_OUT if _social_open else Tween.EASE_IN)
		if not _social_open:
			# Only once every one of them has shrunk away, so the row does not blink out
			# from under its own stagger. A named method rather than a lambda: the Tween
			# owns the callback and frees it with itself, and nothing captures the array.
			_social_tween.chain().tween_callback(_park_social_buttons)

	_push_news_button()

	if _music_social == null or _music_social.sprite_frames == null:
		return
	# Through musicSocialPlayAnim rather than around it: that is the method the mod has for
	# choosing the disc's state, and leaving it uncalled would make it dead code that only
	# looks ported.
	_music_social_play_anim(&"selected" if _social_open else &"basic")


## destroy() (0x1813fc0, line 1055). Most of it is the mod's own bookkeeping - three
## FlxSound cleanups, MusicFilterController.clearFilter/clearEffect/applyNow, and resetting
## FlxTransitionableState's skip flags - and the port's equivalents already ride on the
## scene tree or on menu_visualizer's own _exit_tree. One thing does not: destroy's FIRST
## act is `Cursor.cursorMode = CursorMode.Default` (0x181401d). The hover callbacks set the
## pointer shape, and without this the next screen inherits a hand cursor because the menu
## happened to be left with the mouse over a plaque.
func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _park_social_buttons() -> void:
	for button: Sprite2D in _social_buttons:
		button.visible = false
		button.scale = Vector2.ONE * MUSIC_SOCIAL_SCALE * FUNKIN_TO_RUBICON


func _push_news_button() -> void:
	if _news_button == null:
		return
	if not _news_button.has_meta(&"rest_x"):
		_news_button.set_meta(&"rest_x", _news_button.position.x)
	var rest: float = float(_news_button.get_meta(&"rest_x"))
	if _news_push_tween != null and _news_push_tween.is_valid():
		_news_push_tween.kill()
	_news_push_tween = create_tween()
	# Flixel draws a sprite at `x - offset.x`, so a positive offset pushes it LEFT.
	var to: float = rest - NEWS_PUSH * FUNKIN_TO_RUBICON if _social_open else rest
	_news_push_tween.tween_property(_news_button, "position:x", to,
		NEWS_PUSH_OUT if _social_open else NEWS_PUSH_BACK) 		.set_trans(Tween.TRANS_CUBIC) 		.set_ease(Tween.EASE_IN if _social_open else Tween.EASE_OUT)


## createInteractiveButton (0x17fc0c0) hands every unblocked button to
## FlxMouseEventManager.add with three callbacks, and this port had none of them - the menu
## only answered clicks, so on a desktop the plaques never lit up under the pointer.
##
##   onMouseOver, 0x17fe080:
##       334  if (canInteract) {
##       336      changeItem(button.ID - curSelected);     // no blocked skip: a direct jump
##       337      Cursor.cursorMode = CursorMode.Pointer; }
##
##   onMouseOut, 0x17ff350:
##       340  if (canInteract) {
##       342      Cursor.cursorMode = CursorMode.Default;
##       343      if (button.ID == curSelected) changeItem(-444); }   // the whole menu blanks
##
##   onMouseUp, 0x18066a0:
##       326  if (canInteract) {
##       328      if (button.ID != curSelected) changeItem(button.ID - curSelected);
##       330      doSelect(button.ID); }
##
## Godot has no per-node over/out for plain Node2Ds, so one motion event drives both: the
## rect under the cursor is compared with the last one and the two callbacks fire off the
## difference. The rects are the same `touch_rect` metas the tap path already uses.
##
## Blocked buttons are excluded here rather than inside change_item, exactly as the mod
## excludes them: createButtons never calls createInteractiveButton for a blocked name
## (0x18075b7), so a locked plaque simply has no callbacks to run.
var _mouse_hover: int = -1


func _init_mouse_events() -> void:
	# Motion arrives through _unhandled_input like everything else on this screen; there is
	# nothing to register, but the mod's own method is a real step and this names it.
	_mouse_hover = -1


func _hover(at: Vector2) -> void:
	if _confirmed or not _live():
		return
	var over: int = _button_at(at)
	if over >= 0 and BLOCKED.has(BUTTONS[over]):
		over = -1
	if over == _mouse_hover:
		return
	var left: int = _mouse_hover
	_mouse_hover = over

	if over >= 0:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		if over != _selected:
			change_item(over - _selected, false)
		return

	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if left == _selected:
		deselect()


## spawnHelpMouseText (0x1802d10). The string is the mod's own, out of .rodata, and so is
## the face: `assets/fonts/Inconsolata-Black.ttf`, which ships inside the executable rather
## than beside it and is extracted next to the VCR one. "Click to select!" in an 18px
## default font was this port's invention.
##
##     box  = new FunkinSprite(-85, 125); box.makeGraphic(51, 30); box.alpha = 0.6
##     text = new FlxText(box.x + 5, box.y, FlxG.width, "  Use your mouse ...")
##     text.alpha = 0.9; text.font = Inconsolata-Black; text.alignment = left
##     box.setGraphicSize(text.textWidth + 10)                     # 0x18032b2
##     tween both in, quadOut, 1.3s, after 1.55s and 1.65s        # 0x1803390 / 0x180355a
##     new FlxTimer().start(7.0, ...)                             # 0x18036f4
##
## Both start at x = -85 with a width the text has not been measured for yet, so the only
## reading that makes those two tweens an entrance rather than an exit is that they slide
## to the screen edge - the same argument the intro's curtains needed.
const HELP_TEXT := "  Use your mouse and keys to navigate and choose!"
const HELP_FONT := "res://animania_mod/source/fonts/Inconsolata-Black.ttf"
const HELP_POS := Vector2(-85.0, 125.0)
const HELP_BOX_HEIGHT := 30.0
const HELP_TEXT_INSET := 5.0
const HELP_BOX_PAD := 10.0
const HELP_BOX_ALPHA := 0.6
const HELP_TEXT_ALPHA := 0.9
const HELP_DELAY_BOX := 1.55
const HELP_DELAY_TEXT := 1.65
const HELP_SLIDE := 1.3
const HELP_HOLD := 7.0
const HELP_SIZE := 24

var _help_box: ColorRect = null
var _help_label: Label = null


## finalizeSetup only spawns it when `Save.instance.animania.seenMainMenuHelp` is unset
## (0x1803cb7) - it is a first-run hint, not furniture. GameOptions is this port's save; the
## key is read with get_value and compared, NOT with get_bool, because an unknown key comes
## back null and `bool(null)` is not a conversion GDScript has.
const HELP_SEEN_KEY := "seenMainMenuHelp"


func _spawn_help_mouse_text() -> void:
	if GameOptions.get_value(HELP_SEEN_KEY) == true:
		return
	GameOptions.set_value(HELP_SEEN_KEY, true)
	var font: Font = load(HELP_FONT) as Font if ResourceLoader.exists(HELP_FONT) else null

	_help_label = Label.new()
	_help_label.name = "HelpText"
	_help_label.text = HELP_TEXT
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		_help_label.add_theme_font_override("font", font)
	_help_label.add_theme_font_size_override("font_size",
		int(HELP_SIZE * FUNKIN_TO_RUBICON))
	_help_label.add_theme_color_override("font_color", Color(1, 1, 1, HELP_TEXT_ALPHA))

	_help_box = ColorRect.new()
	_help_box.name = "HelpBox"
	_help_box.color = Color(0, 0, 0, HELP_BOX_ALPHA)
	_help_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_help_box)
	add_child(_help_label)

	var text_width: float = _help_label.get_theme_font("font").get_string_size(
		HELP_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_help_label.get_theme_font_size("font_size")).x
	_help_box.size = Vector2(text_width + HELP_BOX_PAD * FUNKIN_TO_RUBICON,
		HELP_BOX_HEIGHT * FUNKIN_TO_RUBICON)
	_help_box.position = HELP_POS * FUNKIN_TO_RUBICON
	_help_label.position = _help_box.position \
		+ Vector2(HELP_TEXT_INSET * FUNKIN_TO_RUBICON, 0.0)

	var rest_x: float = 0.0
	var slide := create_tween().set_parallel(true)
	slide.tween_property(_help_box, "position:x", rest_x, HELP_SLIDE) \
		.set_delay(HELP_DELAY_BOX).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	slide.tween_property(_help_label, "position:x",
		rest_x + HELP_TEXT_INSET * FUNKIN_TO_RUBICON, HELP_SLIDE) \
		.set_delay(HELP_DELAY_TEXT).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	slide.chain().tween_interval(HELP_HOLD)
	slide.chain().set_parallel(true)
	slide.tween_property(_help_box, "position:x", HELP_POS.x * FUNKIN_TO_RUBICON,
		HELP_SLIDE).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	slide.tween_property(_help_label, "position:x",
		(HELP_POS.x + HELP_TEXT_INSET) * FUNKIN_TO_RUBICON, HELP_SLIDE) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## musicSocialPlayAnim(name, reverse) (0x180fc10). A map of name to frame indices with two
## entries - "press" and "selected" - and it plays the one asked for, then writes the disc's
## scale (0x118/0x120). What was here was an endless alpha pulse on a node called
## "SocialButtons/MusicSocial", which is neither the name this scene uses nor anything the
## mod does.
func _music_social_play_anim(anim: StringName = &"basic") -> void:
	if _music_social == null or _music_social.sprite_frames == null:
		return
	var wanted: StringName = &"soundtrack basic"
	if anim == &"press":
		wanted = &"soundtrack press"
	elif anim == &"selected":
		wanted = &"soundtrack white"
	if _music_social.sprite_frames.has_animation(wanted):
		_music_social.play(wanted)


## initMusic. Initializes the menu music track with proper settings.
## From the binary's initMusic method.
func _init_music() -> void:
	if music != null:
		music.add_to_group("menu_music")
		music.bus = &"Music"


## setupEventListeners. Sets up event listeners for state changes.
## From the binary's setupEventListeners method.
func _setup_event_listeners() -> void:
	# The binary subscribes to events like language changes,
	# season changes, etc. In Godot, most of these are handled
	# by the node tree and scene transitions.
	pass


## create() plus finalizeSetup, which this port does in one pass because it has no separate
## create(). Two calls that were here are NOT in either of them: _create_news_button, which
## _create_special_elements already makes (so the banner was parked 350 twice and started
## a screen further left than it should), and _music_social_play_anim, which plays the
## disc's `selected` state - at startup that left the OST disc looking hovered for ever.
## musicSocialPlayAnim takes the state to play; it belongs to the toggle, not to setup.
## createSeasonalEffects (0x1808ab0) does more than drop leaves or snow: it hangs an
## AdjustColorShader on FlxG.camera, one grade per season, and winter also loads a second
## music layer and fades it in over the loop.
##
##     autum   hue -10  sat -35  contrast  30  brightness -25   (0x1808d70..)
##     winter  hue  12  sat  -6  contrast  10  brightness  -5   (0x1808fa6..)
##
## The autumn branch also adds a RuntimeRainShader (intensity 0.1, scale/200) that
## updateSeasonalEffects drives at elapsed * 0.2. That one is NOT here: writing a rain
## shader from nothing is inventing one, and the grade is the part that is measured.
const SEASON_GRADE := {
	"autum": {"hue": -10.0, "saturation": -35.0, "contrast": 30.0, "brightness": -25.0},
	"winter": {"hue": 12.0, "saturation": -6.0, "contrast": 10.0, "brightness": -5.0},
}
const GRADE_SHADER := "res://animania_mod/shaders/adjust_color.gdshader"
## Winter loads animaniaLOOP/bells and tweens its volume 0 -> 1 (0x18090d7 / 0x1809358).
const WINTER_BELLS := "res://animania_mod/source/music/animaniaLOOP/bells.ogg"
const BELLS_FADE := 1.0

var _grade: CanvasLayer = null
var _bells: AudioStreamPlayer = null


func _create_seasonal_effects() -> void:
	var seasonal: Node = get_node_or_null("Seasonal")
	var season: String = String(seasonal.call("current_season")) if seasonal != null \
		and seasonal.has_method("current_season") else ""
	if not SEASON_GRADE.has(season):
		return

	if ResourceLoader.exists(GRADE_SHADER):
		var grade: Dictionary = SEASON_GRADE[season] as Dictionary
		var material := ShaderMaterial.new()
		material.shader = load(GRADE_SHADER) as Shader
		for key: String in grade:
			material.set_shader_parameter(key, float(grade[key]))
		var rect := ColorRect.new()
		rect.name = "Grade"
		rect.material = material
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Over everything, because the mod puts it on the CAMERA and the camera draws the
		# curtains too - a grade under them would leave two unstained black bars.
		_grade = CanvasLayer.new()
		_grade.name = "SeasonGrade"
		_grade.layer = 10
		_grade.add_child(rect)
		add_child(_grade)

	if season == "winter" and ResourceLoader.exists(WINTER_BELLS):
		_bells = AudioStreamPlayer.new()
		_bells.name = "Bells"
		_bells.stream = load(WINTER_BELLS)
		_bells.bus = &"Music"
		_bells.volume_db = -60.0
		add_child(_bells)
		_bells.play()
		var fade := create_tween()
		fade.tween_property(_bells, "volume_db", 0.0, BELLS_FADE)


## The mod splits this across create() and finalizeSetup (0x1803be0); this port keeps one
## method because the split does not change anything observable. finalizeSetup itself is
## short:
##
##     611  changeItem();                                    // see _ready()
##     612  startIntroAnimation();
##     614  if (Save.instance.animania.seenMainMenuHelp == 0)
##     615      spawnHelpMouseText();
##     617  refresh();                                       // MusicBeatState.refresh
##     618  changePresence(RANDOM_MESSAGES[FlxG.random.int(0, RANDOM_MESSAGES.length - 1)],
##     619                 'MainMenu Screen', ...);
##
## `refresh()` (vtable 0x370) is MusicBeatState's zIndex sort of the WHOLE state, not just
## the buttons - here it is covered by construction, because build_main_menu.gd emits the
## scene already in draw order and _sort_by_z() handles the one group that reorders.
##
## `changePresence` (vtable 0x388) is Discord Rich Presence, picking one of the statics in
## RANDOM_MESSAGES (0x7e568b0). There is no Discord on a phone and nothing to port.
##
## Two more things handleInput can reach that are deliberately not here: a `ManagerPlayState`
## behind a field at 0x1a8 that is only ever WRITTEN false (__construct 0x17fe8bd,
## createNewsButton 0x180c8da, handleInput 0x180ef84 - never set true anywhere), and
## `DebugMenuSubState` on the DEBUG_MENU action. Both are dev doors.
func _finalize_setup() -> void:
	# create() (0x18110d0) runs initMouseEvents and initMusic FIRST, before anything is
	# built, and createSeasonalEffects only after the buttons: the music is playing by the
	# time the winter layer is spun up against it.
	_init_mouse_events()
	_init_music()
	_create_seasonal_effects()
	_sort_by_z()
	_create_special_elements()
	_spawn_help_mouse_text()
	_setup_event_listeners()


const SCROLL_RANGE_X := Vector2(-10.0, 3.0)
const SCROLL_RANGE_Y := Vector2(-1.0, 1.0)
const SCROLL_LERP := 3.0
var _scroll_target := Vector2.ZERO

## Flixel's scrollFactor, which this port had no equivalent for. createBackground gives the
## background 0.65 (0x18006b0) and MenuDude.makeDude gives the dancer 0.95 (0x4884ca3), so
## neither of them follows the camera all the way. In Godot the camera moves the whole world
## by -offset, so a node with factor f gets `offset * (1 - f)` added back.
const PARALLAX := {"Background": 0.65, "Dude": 0.95}
var _parallax_base: Dictionary = {}


func _apply_parallax() -> void:
	if camera == null:
		return
	for path: String in PARALLAX:
		var node: Node2D = get_node_or_null(NodePath(path)) as Node2D
		if node == null:
			continue
		if not _parallax_base.has(path):
			_parallax_base[path] = node.position
		node.position = Vector2(_parallax_base[path]) \
			+ camera.offset * (1.0 - float(PARALLAX[path]))


## updateCameraScroll (0x1804ac0), which was a pair of sines off the music's playback
## position - invented, and it left the camera permanently off centre the moment the intro
## finished. What the mod does is follow the MOUSE:
##
##     scroll.x = lerp(scroll.x, remapToRange(mouse.x, 0, FlxG.width,  -10, 3), elapsed * 3)
##     scroll.y = lerp(scroll.y, remapToRange(mouse.y, 0, FlxG.height, -1,  1), elapsed * 3)
##
## - the two ranges out of .rodata at 0x59fa9e8/0x59fa7e0 and 0x59fa5a8/0x59fa558, and the
## lerp factor is the 3.0 the elapsed is multiplied by at 0x1804b1f. Ten pixels across the
## whole screen, so it is a lean and not a pan.
##
## With no mouse there is nothing to follow, and a phone has none: the drift is skipped
## rather than fed a mouse position the platform is inventing.
func _update_camera_scroll(delta: float) -> void:
	if camera == null or not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE):
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	_scroll_target = Vector2(
		remap(mouse.x, 0.0, view.x, SCROLL_RANGE_X.x, SCROLL_RANGE_X.y),
		remap(mouse.y, 0.0, view.y, SCROLL_RANGE_Y.x, SCROLL_RANGE_Y.y)) * FUNKIN_TO_RUBICON
	camera.offset = camera.offset.lerp(_scroll_target, minf(1.0, SCROLL_LERP * delta))


## showSocialButtons / hideSocialButtons (0x17fc870 and 0x17fcae0). They used to poke a
## "SocialButtons" node the scene does not have; the real toggle is _toggle_social, up with
## the disc it belongs to.
func _show_social() -> void:
	if not _social_open:
		_toggle_social()


func _hide_social() -> void:
	if _social_open:
		_toggle_social()


## sortByZ (0x17fe280) is `FlxSort.byValues(order, a.zIndex, b.zIndex)` - a.zIndex < b.zIndex
## returns the order, equal returns 0, otherwise -order - and changeItem calls it with
## FlxSort.ASCENDING. The key is _refresh()'s `sort_z` meta rather than Godot's own z_index:
## z_index is a real layer here and the negative values the mod uses would push the plaques
## behind the background, whereas in flixel zIndex is only ever this sort's key.
##
## Only the eight plaques take part. The three lock sprites live in the same node and stay
## where they are, last, so they keep drawing over the button they belong to.
func _sort_by_z() -> void:
	if buttons == null:
		return
	var seats: Array[int] = []
	var nodes: Array[Node] = []
	for i: int in BUTTONS.size():
		var node: Node = _button_node(BUTTONS[i])
		if node == null:
			continue
		seats.append(node.get_index())
		nodes.append(node)
	seats.sort()
	nodes.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta(&"sort_z", 0)) < int(b.get_meta(&"sort_z", 0)))
	for i: int in nodes.size():
		buttons.move_child(nodes[i], seats[i])



## handleInput's BACK branch (0x180f370): `cancelMenu`, then startTransitionToMenu with a
## closure that switches to animania::states::TitleScreen (0x17f636b). This port had no way
## out of the main menu at all - on a phone that means the hardware back button did nothing.
const TITLE := "res://animania_mod/menus/title/title_screen.tscn"


func go_back() -> void:
	if _confirmed or _exit >= 0.0 or not _live():
		return
	_confirmed = true
	_play(SOUND_CANCEL)
	_start_exit()
	await get_tree().create_timer(EXIT_SECONDS).timeout
	get_tree().change_scene_to_file(TITLE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


func _unhandled_input(event: InputEvent) -> void:
	# Motion is not a press, so it is asked before the press gate.
	if event is InputEventMouseMotion:
		_hover((event as InputEventMouseMotion).position)
		return

	if _confirmed or not event.is_pressed() or not _live():
		return

	# handleInput (0x180ee10) reads the four UI actions as TWO pairs, and they are not the
	# same code:
	#
	#     815  if (UI_LEFT_P || UI_RIGHT_P)            // Controls 0x38 / 0x40
	#     816      changeItem(UI_LEFT_P ? -1 : 1, true);
	#     818  if (UI_DOWN_P || UI_UP_P) {             // Controls 0x48 / 0x30
	#     821      if (curSelected == -1) changeItem(0, true);
	#     823      else changeItem(UI_UP_P ? -1 : 1, true); }
	#
	# Line 821 is the one that was missing. With nothing selected, up or down does NOT step
	# by one - it passes 0, and `FlxMath.wrap(-1, 0, 7)` is 7, so it lands on the LAST
	# button. Left and right have no such branch and step from -1 the ordinary way.
	# (0x30 is UI_UP: OptionsSubMenu.update, a plain vertical list, tests that same offset
	# for its own -1 at 0x3f7a736.)
	#
	# Both pairs pass `true` for the blocked skip (0x180f1da, 0x180f2c9): they walk the
	# list, so they have to step over a locked plaque rather than stop on it.
	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				change_item(0 if _selected < 0 else -1, true)
			KEY_DOWN, KEY_S:
				change_item(0 if _selected < 0 else 1, true)
			KEY_LEFT, KEY_A:
				change_item(-1, true)
			KEY_RIGHT, KEY_D:
				change_item(1, true)
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				do_select()
			KEY_ESCAPE, KEY_BACKSPACE:
				go_back()
		return

	# handleInput reads FlxG.mouse.wheel straight into changeItem, negated.
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_item(-1, true)
			return
		if button == MOUSE_BUTTON_WHEEL_DOWN:
			change_item(1, true)
			return
		if button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		_touch((event as InputEventScreenTouch).position)


## On a phone the buttons ARE the controls: there are no lane hitboxes on this screen, and
## the eight rects the mod ships are exactly the areas to aim at.
##
## A tap on a button selects it and confirms it in one go, which is what a tap on a menu
## item means. A tap that lands on nothing does nothing - the background is not a button.
func _touch(at: Vector2) -> void:
	# The OST disc is not one of the eight, so it gets asked first.
	if _social_hit(at):
		_toggle_social()
		_play(SOUND_SWITCH)
		return
	var service: String = _social_button_at(at)
	if not service.is_empty():
		OS.shell_open(service)
		_play(SOUND_CONFIRM)
		return
	if _news_hit(at):
		_open_changelog()
		return
	var hit: int = _button_at(at)
	if hit < 0:
		return
	if hit != _selected:
		_selected = hit
		_refresh()
		_play(SOUND_SWITCH)
	do_select()


## The banner's own rect. createNewsButton hangs a FlxMouseEventManager click on it
## (0x1802032) and this screen's taps all go through _touch, so it is asked here with the
## rest. Its `selected` state is the hover the mouse manager drives; on a phone there is no
## hover, so the tap goes straight to `open`.
func _news_hit(at: Vector2) -> bool:
	if _news_button == null or not _news_button.visible:
		return false
	if not _news_button.has_meta(&"touch_rect"):
		return false
	# The rect travels with the slide: it is authored at the banner's seat and the entrance
	# moves the node, so the tap target follows rather than sitting where the art will end up.
	var rect: Rect2 = _news_button.get_meta(&"touch_rect") as Rect2
	rect.position = _news_button.position
	return rect.has_point(at)


## The URL of whichever open OST button was hit, or "".
func _social_button_at(at: Vector2) -> String:
	for button: Sprite2D in _social_buttons:
		if not button.visible or button.texture == null:
			continue
		var size: Vector2 = button.texture.get_size() * button.scale
		if Rect2(button.position, size).has_point(at):
			return String(button.get_meta(&"url", ""))
	return ""


## Which button's rect contains a point, or -1. The rects are set on the nodes by
## build_main_menu.gd, from the same JSON and the same mapping that place the art.
func _button_at(at: Vector2) -> int:
	if buttons == null:
		return -1
	for i: int in BUTTONS.size():
		var node: Node = _button_node(BUTTONS[i])
		if node == null or not node.has_meta(&"touch_rect"):
			continue
		if (node.get_meta(&"touch_rect") as Rect2).has_point(at):
			return i
	return -1
