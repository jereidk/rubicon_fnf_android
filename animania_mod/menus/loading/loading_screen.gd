class_name LoadingScreen
extends Node2D
## The mod's loading screen: LoadingState, ported.
##
## MEASURED off funkin.ui.transition.LoadingState_obj::create() at 0x36c7d40 and
## ::updateOnLoadingNoodlePosition() at 0x36c27a0. Every number below is read
## from there, in the mod's 1280x720 space, and multiplied by 1.5 here.
##
## The screen is five pieces:
##
##   loadingScreen/funkin<dir>  the art, setGraphicSize(FlxG.width) then
##                              updateHitbox then x = (width - w) * 0.5, which is
##                              "fill the screen across". <dir> is the stage
##                              directory, so week1 and winter-horrorland each
##                              get their own drawing.
##   loadingScreen/longNoodle   (0, 671.65), centred, with a clipRect whose WIDTH
##                              is the progress bar - the noodle grows out of the
##                              box as the song loads.
##   loadingScreen/boxOfNoodles (17, 581)
##   loadingScreen/bf           (0, 584.75), sparrow, "bf ate" and
##                              "load complete" at 24fps
##   loadingScreen/pressEnter   (0, 631.75), centred, sparrow, "press to start"
##
## and the noodle drives BF:
##
##   clipRect.width -> remapToRange(progress, 0, 1, 38.3, noodle.frameWidth),
##                     smoothed by exp(-3.125 * 4 * dt)
##   bf.x           -> noodle.x + clipRect.width - 52
##
## so BF's mouth rides the growing tip. `onLoaded()` swaps him to "load complete"
## and starts "press to start"; the state then waits on a key rather than cutting
## straight to the song.
##
## NOT ported, and deliberately: create() writes 0.4 into field 0x260 of the
## noodle, BF and the box and 0.7 into pressEnter's (0x36c8764..0x36c87d5).
## Whatever 0x260 is, it is NOT alpha - flixel's set_alpha writes 0x148 - and no
## set_* method in FlxObject or FlxSprite touches 0x260 at all, so it is a plain
## public field this port could not name. Guessing at it would show on screen, so
## those four writes are left out and written down here instead. There is also no
## capture of this screen to compare against; everything with an address beside
## it above IS the mod's own number, and nothing else was invented.

const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCENE := "res://animania_mod/menus/loading/loading_screen.tscn"
const ART := "res://animania_mod/source/images/loadingScreen"
const MUSIC := "res://animania_mod/source/music/loadingThemeLol.ogg"

## remapToRange(progress, 0, 1, 38.3, noodle.frameWidth) at 0x36c286b: the noodle
## is never fully hidden, it starts 38.3px out of the box.
const NOODLE_START := 38.3
## exp(-3.125 * FlxG.elapsed * 4) at 0x36c287c..0x36c2898.
const NOODLE_DECAY := 3.125 * 4.0
## bf.x = noodle.x + clipRect.width - 52, at 0x36c2990.
const BF_LEAD := 52.0
const NOODLE_POS := Vector2(0.0, 671.65)
const BOX_POS := Vector2(17.0, 581.0)
const BF_POS := Vector2(0.0, 584.75)
const PRESS_POS := Vector2(0.0, 631.75)
## FlxTween.num(0, 1, 4) on the music volume, at 0x36c8a41.
const MUSIC_FADE := 4.0

## Which drawing to use. The mod appends the stage directory to the key, so an
## unknown one falls back to the plain "funkin".
const BACKGROUNDS := {
	"": "%s/funkin.png" % ART,
	"week1": "%s/funkin-week1.png" % ART,
	"winter-horrorland": "%s/funkin-wh.png" % ART,
}

## Where to go once loaded, and which background to wear on the way. Statics
## because change_scene_to_file() takes no arguments; set them through go_to().
static var target_scene: String = ""
static var target_variant: String = ""

@export var background: Sprite2D
@export var noodle: Sprite2D
@export var box: Sprite2D
@export var bf: AnimatedSprite2D
@export var press_enter: AnimatedSprite2D
@export var music: AudioStreamPlayer

var _progress: float = 0.0
var _noodle_width: float = 0.0
var _loaded: PackedScene = null
var _done: bool = false
var _leaving: bool = false


## The one way in. Anything that used to call change_scene_to_file() with a song
## goes through here instead.
static func go_to(tree: SceneTree, scene: String, variant: String = "") -> void:
	target_scene = scene
	target_variant = variant
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	_apply_background()
	_place()
	if bf != null:
		var ate: StringName = _anim(bf, "bf ate")
		if ate != &"":
			bf.play(ate)
	if press_enter != null:
		# create() hides it (vtable 0x128 with a 0 at 0x36c8748) and only
		# onLoaded() starts its animation, so the prompt is not up until the
		# song is in memory.
		press_enter.visible = false
	_start_music()

	if target_scene == "" or not ResourceLoader.exists(target_scene):
		# Nothing to load: still draw the screen, but do not sit on it forever.
		_done = true
		_progress = 1.0
		_on_loaded()
		return
	ResourceLoader.load_threaded_request(target_scene)


## setGraphicSize(FlxG.width) + updateHitbox + centre. In Godot that is a scale,
## and the centring is horizontal only - the mod never assigns y.
func _apply_background() -> void:
	if background == null:
		return
	var path: String = BACKGROUNDS.get(target_variant, BACKGROUNDS[""])
	if not ResourceLoader.exists(path):
		path = BACKGROUNDS[""]
	var tex: Texture2D = load(path)
	if tex == null:
		return
	background.texture = tex
	background.centered = false
	var screen: Vector2 = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	var s: float = screen.x / tex.get_size().x
	background.scale = Vector2(s, s)
	background.position = Vector2((screen.x - tex.get_size().x * s) * 0.5, 0.0)


func _place() -> void:
	var screen_w: float = float(ProjectSettings.get_setting(
		"display/window/size/viewport_width", 1920))
	if noodle != null and noodle.texture != null:
		noodle.centered = false
		noodle.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		_noodle_width = noodle.texture.get_size().x
		# region_rect is Godot's clipRect: with centered off, shrinking its
		# width reveals the strip left to right, which is what the mod's
		# FlxRect(0, 0, w, h) does.
		noodle.region_enabled = true
		noodle.region_rect = Rect2(Vector2.ZERO,
			Vector2(NOODLE_START, noodle.texture.get_size().y))
		noodle.position = Vector2(
			(screen_w - _noodle_width * FUNKIN_TO_RUBICON) * 0.5,
			NOODLE_POS.y * FUNKIN_TO_RUBICON)
	for pair: Array in [[box, BOX_POS], [bf, BF_POS]]:
		var node: Node2D = pair[0]
		if node == null:
			continue
		node.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		node.position = (pair[1] as Vector2) * FUNKIN_TO_RUBICON
	if press_enter != null:
		press_enter.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		press_enter.position = Vector2(
			(screen_w - _frame_size(press_enter).x * FUNKIN_TO_RUBICON) * 0.5,
			PRESS_POS.y * FUNKIN_TO_RUBICON)


func _frame_size(node: AnimatedSprite2D) -> Vector2:
	if node == null or node.sprite_frames == null:
		return Vector2.ZERO
	var names: PackedStringArray = node.sprite_frames.get_animation_names()
	if names.is_empty():
		return Vector2.ZERO
	var tex: Texture2D = node.sprite_frames.get_frame_texture(StringName(names[0]), 0)
	return tex.get_size() if tex != null else Vector2.ZERO


## The atlases prefix their animation names, and pressEnter's carries a Cyrillic
## suffix ("press to start образец 1"), so this matches the way the mod's
## addByPrefix does: on the start of the name.
func _anim(node: AnimatedSprite2D, prefix: String) -> StringName:
	if node == null or node.sprite_frames == null:
		return &""
	for n: StringName in node.sprite_frames.get_animation_names():
		if String(n).begins_with(prefix):
			return n
	return &""


func _start_music() -> void:
	if music == null:
		return
	if music.stream == null and ResourceLoader.exists(MUSIC):
		music.stream = load(MUSIC)
	if music.stream == null:
		return
	music.volume_db = linear_to_db(0.001)
	music.play()
	var tw: Tween = create_tween()
	tw.tween_method(func(v: float) -> void:
		music.volume_db = linear_to_db(maxf(v, 0.001)), 0.0, 1.0, MUSIC_FADE)


func _process(delta: float) -> void:
	if not _done and target_scene != "":
		_poll()
	_drive_noodle(delta)


func _poll() -> void:
	var parts: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(target_scene, parts)
	if not parts.is_empty():
		_progress = clampf(float(parts[0]), 0.0, 1.0)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_loaded = ResourceLoader.load_threaded_get(target_scene) as PackedScene
			_progress = 1.0
			_done = true
			_on_loaded()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("LoadingScreen: no se pudo cargar %s" % target_scene)
			_progress = 1.0
			_done = true
			_on_loaded()


## clipRect.width eases toward the mapped progress, and BF's x hangs off the tip.
## The easing is the mod's own: a decay of exp(-12.5 * dt) per frame.
func _drive_noodle(delta: float) -> void:
	if noodle == null or noodle.texture == null:
		return
	var target: float = NOODLE_START + _progress * (_noodle_width - NOODLE_START)
	var rect: Rect2 = noodle.region_rect
	var width: float = target + (rect.size.x - target) * exp(-NOODLE_DECAY * delta)
	rect.size.x = width
	noodle.region_rect = rect
	if bf != null:
		bf.position.x = noodle.position.x \
			+ (width - BF_LEAD) * FUNKIN_TO_RUBICON


func _on_loaded() -> void:
	if press_enter != null:
		press_enter.visible = true
	if bf != null:
		var complete: StringName = _anim(bf, "load complete")
		if complete != &"":
			bf.play(complete)
	if press_enter != null:
		var start: StringName = _anim(press_enter, "press to start")
		if start != &"":
			press_enter.play(start)


## The mod checks the key inside onLoaded() as well as in update(), so a player
## already holding it never sees the prompt. A tap does the same on a phone,
## where there is no ENTER at all.
func _unhandled_input(event: InputEvent) -> void:
	if not _done or _leaving or not event.is_pressed():
		return
	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_enter()
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		_enter()


func _enter() -> void:
	if _leaving:
		return
	_leaving = true
	if music != null:
		music.stop()
	if _loaded != null:
		get_tree().change_scene_to_packed(_loaded)
		return
	if target_scene != "" and ResourceLoader.exists(target_scene):
		get_tree().change_scene_to_file(target_scene)
