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
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"

## The confirm animation is 18 frames at 24fps. The transition waits it out.
const CONFIRM_SECONDS := 18.0 / 24.0

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
const BEAT_ZOOM := 0.005
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

var _selected: int = 0
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
	_refresh()
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
		return

	if camera != null:
		camera.zoom = Vector2.ONE * (ZOOM_REST
			+ (camera.zoom.x - ZOOM_REST) * exp(-ZOOM_DECAY * delta))
	_update_camera_scroll(delta)

	if music == null or not music.playing:
		return
	var beat: int = floori(music.get_playback_position() * BPM / 60.0)
	if beat == _beat:
		return
	_beat = beat
	if camera != null:
		camera.zoom += Vector2.ONE * BEAT_ZOOM


## The walk skips blocked buttons rather than stopping on them, and wraps.
##
## Deaf until the intro's CAMERA tween lands - `_live()` - and not until the curtains stop:
## the mod only reaches changeItem through handleInput, and update() stops calling
## handleInput when that tween's onComplete fires at 0.75s, a quarter of a second before the
## curtains finish. The guard used to look at whatever moment the frames happened to land on
## and call it "during the intro"; it names the moment now.
func change_item(amount: int, play_sound: bool = true) -> void:
	if _confirmed or amount == 0 or not _live():
		return
	var step: int = signi(amount)
	var at: int = _selected
	# At most one full lap: if every other button were blocked this would otherwise spin.
	for _i: int in BUTTONS.size():
		at = wrapi(at + step, 0, BUTTONS.size())
		if not BLOCKED.has(BUTTONS[at]):
			break
	if at == _selected:
		return
	_selected = at
	_refresh()
	if play_sound:
		_play(SOUND_SWITCH)


## doSelect: the chosen button plays its `confirm` animation and the menu leaves.
func do_select() -> void:
	if _confirmed or not _live():
		return
	var name: String = BUTTONS[_selected]
	if BLOCKED.has(name):
		_play(SOUND_LOCKED)
		return

	_confirmed = true
	_play(SOUND_CONFIRM)
	_animate(name, "confirm")
	_start_exit()

	# The confirm animation and the transition are the same 0.75 seconds, which is why the
	# mod can start both and only wait once.
	await get_tree().create_timer(EXIT_SECONDS).timeout

	if not DESTINATIONS.has(name):
		# Nowhere to go yet, so it comes back in the way it went out. A button that is not
		# ported reads as "not yet" instead of as a freeze.
		_exit = -1.0
		_confirmed = false
		_refresh()
		_start_intro()
		return

	# Story mode does not go straight to the story menu. MainMenuScreen::doSelect
	# opens StoryMenuSelectSubState from HERE - the closure at 0x180b180 tests
	# the pressed button's name against "storymode" (0x5a7e5e7) and only then
	# allocates it - and the sub-state calls back into the main menu with
	# startTransitionToMenu once a side is picked. The port had it hanging off
	# the story menu's own confirm, which is one screen too late.
	if name == "storymode":
		_open_story_select()
		return

	get_tree().change_scene_to_file(String(DESTINATIONS[name]))


const STORY_SELECT := "res://animania_mod/menus/story_select/story_menu_select_sub_state.gd"


func _open_story_select() -> void:
	if _story_select != null:
		return
	_story_select = load(STORY_SELECT).new()
	_story_select._menu_state = self
	add_child(_story_select)
	_story_select.tree_exited.connect(func() -> void:
		_story_select = null
		# Backing out of the picker puts the menu back the way it was, the same
		# way an unported destination does.
		if is_inside_tree() and _confirmed:
			_exit = -1.0
			_confirmed = false
			_refresh()
			_start_intro())


## Called by StoryMenuSelectSubState once a side is picked - the mod's
## startTransitionToMenu, which is a method of the MAIN MENU, not of the story
## menu. Only the amtake side is unlocked, in the mod as here.
func start_story(_variant: String) -> void:
	get_tree().change_scene_to_file(String(DESTINATIONS["storymode"]))


## The selected button shows `white` and every other one `basic`.
func _refresh() -> void:
	for i: int in BUTTONS.size():
		_animate(BUTTONS[i], "white" if i == _selected else "basic")


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


## createNewsButton. Creates the news/changelog button from the animated sprite
## atlas. From the binary's createNewsButton method. The button uses the
## news_button sprite atlas and shows/hides based on allowToUseNewsButton.
const NEWS_BUTTON_PATH := "res://animania_mod/source/images/menus/news_button.png"
const NEWS_BUBBLE_PATH := "res://animania_mod/source/images/menus/new_update_bub.png"
var _news_button: Sprite2D = null
var _news_bubble: Sprite2D = null


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
## is where the three giant UPDATEs across the middle of the menu came from. The mod's own
## capture has nothing there.
##
## The button's placement is not measured yet, so it stays off rather than being invented a
## second time: NEWS_BUBBLE_PATH is kept because the asset is real and will be wanted when
## the changelog screen is done.
func _create_news_button() -> void:
	if not ResourceLoader.exists(NEWS_BUTTON_PATH):
		return


## createSpecialElements (0x180ec40) is two calls and nothing else: createNewsButton and
## createMusicSocial. The port also drew two black ColorRects over the top and bottom of the
## screen "for depth" - invented, and the top one is the grey band that sat across the
## menu's sky in every render. Gone.
const MUSIC_SOCIAL_FRAMES := "res://animania_mod/source/images/menus/menu/music_social_frames.tres"
## createMusicSocial: scale 0.85 on both axes (0x180e611/0x180e62d), zoomFactor 0.875, and
## the animations "soundtrack basic" (idle), "soundtrack white" (selected) and
## "soundtrack press", all at 24. Where it SITS is off the mod's own capture - the OST disc
## is centred on (645, 620) of a 1278-wide shot - because createMusicSocial's own placement
## has not been read yet.
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
const MUSIC_SOCIAL_CENTRE := Vector2(645.0, 620.0)
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


func _toggle_social() -> void:
	_social_open = not _social_open
	if _music_lines != null:
		_music_lines.visible = _social_open
	for button: Sprite2D in _social_buttons:
		button.visible = _social_open
	if _music_social == null or _music_social.sprite_frames == null:
		return
	var anim: StringName = &"soundtrack white" if _social_open else &"soundtrack basic"
	if _music_social.sprite_frames.has_animation(anim):
		_music_social.play(anim)


## initMouseEvents. Sets up mouse hover detection on buttons.
## From the binary's initMouseEvents method.
var _mouse_hover: int = -1


func _init_mouse_events() -> void:
	# The binary sets up FlxMouseEventManager for each button.
	# In Godot, we handle this via _unhandled_input which already
	# processes InputEventMouseButton for touch/click.
	pass


## spawnHelpMouseText. Shows a help tooltip near the mouse cursor.
## From the binary's spawnHelpMouseText method.
var _help_label: Label = null


func _spawn_help_mouse_text() -> void:
	_help_label = Label.new()
	_help_label.text = "Click to select!"
	_help_label.add_theme_font_size_override("font_size", 18)
	_help_label.add_theme_color_override("font_color", Color.WHITE)
	_help_label.visible = false
	add_child(_help_label)


## musicSocialPlayAnim. Plays the music social button animation.
## From the binary's musicSocialPlayAnim method.
func _music_social_play_anim() -> void:
	var social := get_node_or_null("SocialButtons/MusicSocial")
	if social != null and social is Sprite2D:
		# Pulse the social button alpha to draw attention
		var tween: Tween = create_tween().set_loops()
		tween.tween_property(social, "modulate:a", 0.6, 0.8)
		tween.tween_property(social, "modulate:a", 1.0, 0.8)


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


## finalizeSetup. Final initialization after all components are created.
## From the binary's finalizeSetup method.
func _finalize_setup() -> void:
	_sort_by_z()
	_init_music()
	_init_mouse_events()
	_create_news_button()
	_create_special_elements()
	_spawn_help_mouse_text()
	_music_social_play_anim()
	_setup_event_listeners()


const SCROLL_RANGE_X := Vector2(-10.0, 3.0)
const SCROLL_RANGE_Y := Vector2(-1.0, 1.0)
const SCROLL_LERP := 3.0
var _scroll_target := Vector2.ZERO


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


## sortByZ. Sorts children of the Buttons node by z_index.
## From the binary's sortByZ method.
func _sort_by_z() -> void:
	if buttons == null:
		return
	var ch: Array[Node] = []
	for child: Node in buttons.get_children():
		ch.append(child)
	ch.sort_custom(func(a: Node, b: Node) -> bool:
		return a.z_index < b.z_index)
	for i: int in ch.size():
		buttons.move_child(ch[i], i)



func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or not event.is_pressed() or not _live():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_LEFT, KEY_W, KEY_A:
				change_item(-1)
			KEY_DOWN, KEY_RIGHT, KEY_S, KEY_D:
				change_item(1)
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				do_select()
		return

	# handleInput reads FlxG.mouse.wheel straight into changeItem, negated.
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_item(-1)
			return
		if button == MOUSE_BUTTON_WHEEL_DOWN:
			change_item(1)
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
	var hit: int = _button_at(at)
	if hit < 0:
		return
	if hit != _selected:
		_selected = hit
		_refresh()
		_play(SOUND_SWITCH)
	do_select()


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
