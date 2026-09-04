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
##   loadingScreen/funkin<sfx>  the art, setGraphicSize(FlxG.width) then
##                              updateHitbox then x = (width - w) * 0.5, which is
##                              "fill the screen across". The suffix is picked by
##                              SONG, in HScript - see BG_SUFFIX.
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
## The camera, and what create() writes into field 0x260:
##
##   update 0x36c90de  zoom -> 1 + (zoom - 1) * exp(-3.125 * elapsed * 2)
##   update 0x36c9237  zoom -> zoom + 0.03, on the keypress
##   update 0x36c94b2  BF's x eases to 147.05 with exp(-3.125 * elapsed * 2.5)
##                     when there is no progress left to ride
##
## and 0x260 is `zoomFactor` - it is read by exactly four methods, all of them
## FunkinSprite's zoom-scale procedure (_hx___shouldDoScaleProcedure,
## _hx___doPreZoomScaleProcedure, doAdditionalMatrixStuff and getScreenPosition).
## create() gives the noodle, BF and the box 0.4 and pressEnter 0.7
## (0x36c8764..0x36c87d5), and it means "zoom this at a FRACTION of what the
## camera does". The mod implements it inside draw by rewriting the scale and
## the origin; here the same result comes out of moving the sprite in world
## space, which is what _apply_zoom does - a sprite at P with factor f under a
## camera at Z has to sit where a camera at 1 + (Z - 1) * f would have drawn it.
##
## So the whole thing is a 3% punch on a keypress that five sprites take at 40%
## and 70% of. Small, but it is the difference between a still screen and one
## that answers the button.
##
## There is no capture of this screen to compare against; everything with an
## address beside it above IS the mod's own number, and nothing else was
## invented.

const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCENE := "res://animania_mod/menus/loading/loading_screen.tscn"
const ART := "res://animania_mod/source/images/loadingScreen"
const MUSIC := "res://animania_mod/source/music/loadingThemeLol.ogg"
## The dadbattle screen throws the theme away and loads its own, which the
## visualiser is then an FFT of.
const MUSIC_DADBATTLE := "res://animania_mod/source/music/loadingThemeLol-dadbattle.ogg"

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
## The camera settles with exp(-3.125 * elapsed * 2) and jumps by 0.03 on a press.
const CAM_DECAY := 3.125 * 2.0
const CAM_PUNCH := 0.03
## zoomFactor, per sprite. The background has none, so it takes the zoom whole.
const ZOOM_FACTOR := {"noodle": 0.4, "box": 0.4, "bf": 0.4, "press": 0.7}
## Where BF parks once there is nothing left to eat.
const BF_REST_X := 147.05
const BF_REST_DECAY := 3.125 * 2.5

## Which drawing to wear, and it is chosen by the SONG, not by the level or the
## stage. This is not inferred: create() builds the key as
## "loadingScreen/funkin" + this.field0x100 (0x36c7e8f), that field comes from an
## HScript the constructor loads by the name "data/loadingScreen" (0x36c6566),
## and the mod ships that script in assets/data/loadingScreen.script. Its
## onLoadParams is a switch on `targetSong.id.toLowerCase()`, transcribed here:
##
##   case "tutorial" | "bopeebo" | "fresh": "-week1";
##   case "dadbattle":                      "-week1-dadbattle";
##   case "phone-call" | "how2funk":        "-komi";
##   case "winter-horrorland":              "-wh";
##   default:                               "";
##
## The port used the LEVEL id for one commit, which is close enough to look
## right on week1 and wrong everywhere else - dadbattle is a week1 song with its
## own screen, and phone-call is a tutorial song with komi's.
const BG_SUFFIX := {
	"tutorial": "-week1",
	"bopeebo": "-week1",
	"fresh": "-week1",
	"dadbattle": "-week1-dadbattle",
	"phone-call": "-komi",
	"how2funk": "-komi",
	"winter-horrorland": "-wh",
}
const BACKGROUNDS := {
	"": "%s/funkin.png" % ART,
	"-week1": "%s/funkin-week1.png" % ART,
	"-week1-dadbattle": "%s/funkin-week1-dadbattle.png" % ART,
	"-komi": "%s/funkin-komi.png" % ART,
	"-wh": "%s/funkin-wh.png" % ART,
}
## onCreateBG, for the two suffixes that have one. Also from the script.
##   -wh              music pitch to 0.1 over 2.5s, expoOut; box, BF and the
##                    noodle hidden; pressEnter grey at 0.7 scale; the screen
##                    black behind, under a black sheet that fades over 2s.
##   -week1-dadbattle the theme swapped for loadingThemeLol-dadbattle with a 4s
##                    fade in; the same three hidden; the same black sheet.
const WH_PITCH := 0.1
const WH_PITCH_TIME := 2.5
const WH_PRESS_SCALE := 0.7
const WH_PRESS_TINT := Color(0.5, 0.5, 0.5)
const BLACKOUT_TIME := 2.0

## Where to go once loaded, and the id of the SONG being loaded - the screen
## reads its own look off that. Statics because change_scene_to_file() takes no
## arguments; set them through go_to().
static var target_scene: String = ""
static var target_song: String = ""

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
var _fade: Tween = null
var _zoom: float = 1.0
var _base: Dictionary = {}
var _bf_x: float = 0.0
var _cam: Camera2D = null


## The one way in. Anything that used to call change_scene_to_file() with a song
## goes through here instead.
static func go_to(tree: SceneTree, scene: String, song: String = "") -> void:
	target_scene = scene
	target_song = song
	tree.change_scene_to_file(SCENE)


func suffix() -> String:
	return String(BG_SUFFIX.get(target_song.to_lower(), ""))


func _ready() -> void:
	_apply_background()
	_place()
	if bf != null:
		var ate: StringName = _anim(bf, "bf ate")
		if ate != &"":
			bf.play(ate)
	if press_enter != null:
		# create() hides it - the call at 0x36c8748 goes through vtable slot
		# 0x128, which resolves to FlxBasic::set_visible, with a 0 - and only
		# onLoaded() starts its animation, so the prompt is not up until the
		# song is in memory.
		press_enter.visible = false
	_start_music()
	_on_create_bg()

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
	var path: String = BACKGROUNDS.get(suffix(), BACKGROUNDS[""])
	if not ResourceLoader.exists(path):
		path = BACKGROUNDS[""]
	var tex: Texture2D = load(path)
	if tex == null:
		return
	background.texture = tex
	background.centered = false
	var screen: Vector2 = _screen()
	var s: float = screen.x / tex.get_size().x
	background.scale = Vector2(s, s)
	background.position = Vector2((screen.x - tex.get_size().x * s) * 0.5, 0.0)


func _place() -> void:
	var screen_w: float = _screen().x
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
	_remember_base()


## The camera compensation rewrites position and scale every frame, so the values
## it starts from have to be kept somewhere that is not the node itself.
func _remember_base() -> void:
	_base.clear()
	for pair: Array in [["noodle", noodle], ["box", box], ["bf", bf],
			["press", press_enter]]:
		var node: Node2D = pair[1]
		if node != null:
			_base[pair[0]] = [node.position, node.scale]
	if bf != null:
		_bf_x = bf.position.x


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


## The mod's onCreateBG. Two of the five screens are not just a different
## drawing: winter-horrorland drops the pitch through the floor and goes black,
## and dadbattle throws the theme away for its own. Both hide the box, BF and the
## noodle - on those two screens there is no progress bar at all, which is why
## the port must not just swap the art and stop there.
func _on_create_bg() -> void:
	var sfx: String = suffix()
	if sfx != "-wh" and sfx != "-week1-dadbattle":
		return

	for node: Node2D in [box, bf, noodle]:
		if node != null:
			node.visible = false

	if sfx == "-wh":
		if music != null:
			var pitch: Tween = create_tween()
			pitch.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			pitch.tween_property(music, ^"pitch_scale", WH_PITCH, WH_PITCH_TIME)
		if press_enter != null:
			press_enter.modulate = WH_PRESS_TINT
			press_enter.scale = Vector2.ONE * FUNKIN_TO_RUBICON * WH_PRESS_SCALE
			# Re-centre: the mod scales it after the centring in create(), and
			# FlxSprite centres on its own width.
			press_enter.position.x = (_screen().x
				- _frame_size(press_enter).x * press_enter.scale.x) * 0.5
	else:
		# FunkinSound.load(...loadingThemeLol-dadbattle) then fadeIn(4, 0, 1),
		# replacing whatever create() started.
		if music != null and ResourceLoader.exists(MUSIC_DADBATTLE):
			music.stop()
			music.stream = load(MUSIC_DADBATTLE)
			_start_music()

	_blackout()


## `blackScreeen` in the script (their spelling): a solid black 2000x2000 over
## everything, tweened to alpha 0 over two seconds. On -wh the screen behind it
## is black too (bgColor = FlxColor.BLACK), so the art fades in out of nothing.
func _blackout() -> void:
	var screen: Vector2 = _screen()
	if suffix() == "-wh":
		var backdrop := ColorRect.new()
		backdrop.color = Color.BLACK
		backdrop.size = screen
		backdrop.z_index = -100
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)
		move_child(backdrop, 0)

	var sheet := ColorRect.new()
	sheet.color = Color.BLACK
	sheet.size = screen
	sheet.z_index = 100
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(sheet, ^"color:a", 0.0, BLACKOUT_TIME)
	tw.tween_callback(sheet.queue_free)


func _screen() -> Vector2:
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))


func _start_music() -> void:
	if music == null:
		return
	if music.stream == null and ResourceLoader.exists(MUSIC):
		music.stream = load(MUSIC)
	if music.stream == null:
		return
	music.volume_db = linear_to_db(0.001)
	music.play()
	# Killed first: dadbattle calls this a second time to swap the track, and two
	# live tweens on one volume fight each other.
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_method(func(v: float) -> void:
		music.volume_db = linear_to_db(maxf(v, 0.001)), 0.0, 1.0, MUSIC_FADE)


func _process(delta: float) -> void:
	if not _done and target_scene != "":
		_poll()
	_drive_noodle(delta)
	_zoom = 1.0 + (_zoom - 1.0) * exp(-CAM_DECAY * delta)
	_apply_zoom()


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
	if bf == null:
		return
	if _done and _progress >= 1.0:
		# Nothing left to ride: BF eases back beside the box.
		var rest: float = BF_REST_X * FUNKIN_TO_RUBICON
		_bf_x = rest + (_bf_x - rest) * exp(-BF_REST_DECAY * delta)
	else:
		_bf_x = noodle.position.x + (width - BF_LEAD) * FUNKIN_TO_RUBICON
	if _base.has("bf"):
		var b: Array = _base["bf"]
		_base["bf"] = [Vector2(_bf_x, (b[0] as Vector2).y), b[1]]


## A sprite with zoomFactor f, under a camera at Z about the screen centre, has
## to be drawn where a camera at 1 + (Z - 1) * f would have put it. In world
## space, before the camera multiplies everything by Z, that is a position and a
## scale divided down by Z / Z'.
func _apply_zoom() -> void:
	var camera: Camera2D = _camera()
	if camera != null:
		camera.zoom = Vector2.ONE * _zoom
	var centre: Vector2 = _screen() * 0.5
	for key: Variant in _base:
		var node: Node2D = _node_for(String(key))
		if node == null:
			continue
		var b: Array = _base[key]
		var base_pos: Vector2 = b[0]
		var base_scale: Vector2 = b[1]
		var f: float = float(ZOOM_FACTOR.get(key, 1.0))
		var k: float = (1.0 + (_zoom - 1.0) * f) / _zoom
		node.position = centre + (base_pos - centre) * k
		node.scale = base_scale * k


func _node_for(key: String) -> Node2D:
	match key:
		"noodle": return noodle
		"box": return box
		"bf": return bf
		"press": return press_enter
	return null


func _camera() -> Camera2D:
	if _cam == null:
		_cam = Camera2D.new()
		_cam.name = "LoadingCamera"
		_cam.position = _screen() * 0.5
		# DRAG_CENTER, not FIXED_TOP_LEFT: the camera sits ON the screen centre,
		# which is the point the zoom has to happen about. Anchored top-left it
		# put the origin at the centre and showed a magnified bottom-right
		# quarter of the screen.
		_cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
		add_child(_cam)
		_cam.make_current()
	return _cam


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
	if _leaving or not event.is_pressed():
		return
	# The punch happens on the press itself, whether or not the song is ready:
	# update checks the key and adds 0.03 before it ever looks at the loader.
	_zoom += CAM_PUNCH
	if not _done:
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
