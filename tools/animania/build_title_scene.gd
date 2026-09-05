# Authors animania_mod/menus/title/title_screen.tscn.
#
#   godot --headless --path . --script tools/animania/build_title_scene.gd
extends SceneTree

const OUT := "res://animania_mod/menus/title/title_screen.tscn"
const DIR := "res://animania_mod/menus/title"
const SCREEN := Vector2(1920.0, 1080.0)

## Funkin is 1280x720 and this project is 1920x1080.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## Measured, not chosen - see tools/animania/harness/measure_title.gd, which renders each
## composition into a padded viewport and counts opaque pixels. Placing these by hand went
## wrong twice: once at screen coordinates, which put the logo in a corner, and once at the
## project's flat 1.5x, which filled the screen with a quarter of it.
##
## The two are authored at different scales. The logo is a 2277x1643 drawing - far bigger
## than Funkin's 1280x720 stage, so the compiled TitleScreen must scale it down - while the
## press-enter prompt at 816x139 is stage-sized and only wants the project's 1.5x.
const LOGO_DRAWN := Vector2(2277.0, 1643.0)
const LOGO_CORNER := Vector2(-122.0, -22.0)
const PRESS_DRAWN := Vector2(816.0, 139.0)
const PRESS_CORNER := Vector2(11.0, 11.0)

## How far off the bottom the prompt sits, in screen pixels.
const PRESS_BOTTOM_MARGIN := 90.0

var _root: Node2D


func _init() -> void:
	_root = Node2D.new()
	_root.name = "TitleScreen"
	_root.set_script(load("res://animania_mod/menus/title/title_screen.gd"))

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = SCREEN * 0.5
	_add(camera)

	var background := Sprite2D.new()
	background.name = "Background"
	background.texture = load("res://animania_mod/source/images/title/void gradient.png")
	background.centered = false
	if background.texture != null:
		background.scale = SCREEN / background.texture.get_size()
	_add(background)

	# Hidden until the intro's 31 beats are spelled out.
	var title := Node2D.new()
	title.name = "Title"
	title.visible = false
	_add(title)
	# The logo fits the screen, keeping its aspect; the prompt keeps the project's 1.5x and
	# sits centred near the bottom. Both are placed by their DRAWN bounds rather than by
	# their node origin, which is what the measured corner is for.
	var logo_scale: float = minf(SCREEN.x / LOGO_DRAWN.x, SCREEN.y / LOGO_DRAWN.y)
	_symbol(title, "Logo", "logo", &"logo_idle", "Logolol", logo_scale,
		(SCREEN - LOGO_DRAWN * logo_scale) * 0.5 - LOGO_CORNER * logo_scale)

	var press_at := Vector2(
		(SCREEN.x - PRESS_DRAWN.x * FUNKIN_TO_RUBICON) * 0.5,
		SCREEN.y - PRESS_DRAWN.y * FUNKIN_TO_RUBICON - PRESS_BOTTOM_MARGIN)
	_symbol(title, "PressEnter", "press_enter", &"press_enter_loop", "main",
		FUNKIN_TO_RUBICON, press_at - PRESS_CORNER * FUNKIN_TO_RUBICON)

	# The falling props, behind the title and in front of the gradient. Read out of the
	# Linux build's disassembly of updateProps() rather than transcribed - see the script.
	var props := Node2D.new()
	props.name = "Props"
	props.set_script(load("res://animania_mod/menus/title/title_props.gd"))
	props.set(&"frames", load("%s/props_frames.tres" % DIR))
	_root.add_child(props)
	props.owner = _root
	_root.move_child(props, 2)

	# create() lines 186-206: nonIntroGroup, and the two FallCharacters in it. Both are
	# screenCenter()ed and then moved - BF left by FlxG.width/3, GF right by the same, both
	# up 100 - and each gets addByPrefix('fall', '<who> fall', 24) off title/fallguys. They
	# are two of the three pieces update()'s confirm branch flings off screen.
	var non_intro := Node2D.new()
	non_intro.name = "NonIntro"
	non_intro.visible = false
	_root.add_child(non_intro)
	non_intro.owner = _root
	_root.move_child(non_intro, 3)

	var fall_frames: SpriteFrames = _sparrow(
		"res://animania_mod/source/images/title/fallguys.png")
	if fall_frames != null:
		ResourceSaver.save(fall_frames, "%s/fallguys_frames.tres" % DIR)
		_fall(non_intro, "FallBF", fall_frames, &"bf fall", -1.0)
		_fall(non_intro, "FallGF", fall_frames, &"gf fall", 1.0)

	# create() lines 229-241, the two texts.
	#
	#     229  txtVersion = new FlxFixedText(10, 10, ?, 'Animania! Mod ' + VERSION_clear);
	#     230      font = 'assets/fonts/vcr.ttf';
	#     231      x = FlxG.initialWidth - x - width;      // right edge, same 10 margin
	#     232      alpha = 0.9;                            // vtable 0x3a8
	#     237  titleText = new FlxFixedText(0, 0, FlxG.width, 'ANIMANIA!CREW');
	#     238      alignment = 'center';
	#     240      font = 'Blueprint.ttf';
	#
	# `VERSION_clear` is 'v' + the manifest's version, and the binary carries 0.6.0.
	# 'Hello there! :>' is NOT a text field - it is the Discord presence string that goes
	# with 'Title Screen' through changePresence at line 137, which is why it sits next to
	# these in .rodata.
	#
	# Both go under NonIntro rather than under Title: same visibility timing, and Title
	# carries the boil displacement, which is not something to run text through.
	_text(non_intro, "TitleText", "ANIMANIA!CREW", BLUEPRINT_FONT, TITLE_TEXT_SIZE,
		1.0, HORIZONTAL_ALIGNMENT_CENTER, Vector2(0.0, 0.0), SCREEN.x)
	_text(non_intro, "TxtVersion", "Animania! Mod v%s" % MOD_VERSION, VCR_FONT,
		VERSION_TEXT_SIZE, 0.9, HORIZONTAL_ALIGNMENT_RIGHT,
		Vector2(0.0, TEXT_MARGIN * FUNKIN_TO_RUBICON),
		SCREEN.x - TEXT_MARGIN * FUNKIN_TO_RUBICON)

	# The intro text is screen-space: the camera zooms on beats 28-31 and the line must not
	# zoom with it, the same way Funkin puts it on a camera of its own.
	var layer := CanvasLayer.new()
	layer.name = "IntroLayer"
	_add(layer)

	var text := RichTextLabel.new()
	text.name = "IntroText"
	text.bbcode_enabled = true
	text.scroll_active = false
	text.fit_content = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.anchor_right = 1.0
	text.anchor_bottom = 1.0
	text.offset_top = 260.0
	text.offset_bottom = -260.0
	text.add_theme_font_size_override("normal_font_size", 84)
	text.add_theme_constant_override("outline_size", 16)
	text.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	layer.add_child(text)
	text.owner = _root

	var music := AudioStreamPlayer.new()
	music.name = "Music"
	music.stream = load("res://animania_mod/source/music/animaniaINTRO/animaniaINTRO.ogg")
	_add(music)

	# The boil goes on the title's own composition rather than on the whole screen: the
	# field lives on TitleScreen beside logoTV, and a displacement over the intro text would
	# make it unreadable.
	var boil := ShaderMaterial.new()
	boil.shader = load("res://animania_mod/menus/title/boil.gdshader")
	boil.set_shader_parameter(&"boil_texture",
		load("res://animania_mod/source/images/title/boil_texture.png"))
	title.material = boil

	_root.boil = boil
	_root.music = music
	_root.intro_text = text
	_root.title = title
	_root.camera = camera

	var packed := PackedScene.new()
	var err: int = packed.pack(_root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("OUT %s %s" % ["saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)


## FlxG.width / 3 and the 100 are in Funkin's 1280x720; the third is a fraction of the
## screen either way, the 100 takes the project's 1.5x.
const FALL_RISE := 100.0

const BLUEPRINT_FONT := "res://animania_mod/source/fonts/Blueprint.ttf"
const VCR_FONT := "res://animania_mod/source/fonts/VCR OSD Mono Cyr.ttf"
## The 10 both of txtVersion's coordinates are given, in Funkin's space.
const TEXT_MARGIN := 10.0
## The two Null<int> sizes are not resolved in the dump, so these are this port's.
const TITLE_TEXT_SIZE := 48
const VERSION_TEXT_SIZE := 24
## Constants.VERSION_clear is 'v' + the manifest version; the binary carries 0.6.0.
const MOD_VERSION := "0.6.0"


func _text(parent: Node2D, node_name: String, body: String, font_path: String,
		size: int, alpha: float, align: int, at: Vector2, width: float) -> void:
	var label := Label.new()
	label.name = node_name
	label.text = body
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = at
	label.size = Vector2(width, float(size) * 1.6)
	if ResourceLoader.exists(font_path):
		label.add_theme_font_override("font", load(font_path))
	label.add_theme_font_size_override("font_size", size)
	label.modulate.a = alpha
	parent.add_child(label)
	label.owner = _root



func _fall(parent: Node2D, node_name: String, frames: SpriteFrames,
		animation: StringName, side: float) -> void:
	if not frames.has_animation(animation):
		push_error("fallguys no tiene la animacion [%s]" % animation)
		return
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name
	sprite.sprite_frames = frames
	sprite.animation = animation
	sprite.autoplay = String(animation)
	sprite.centered = false
	sprite.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	var art: Vector2 = Vector2(frames.get_frame_texture(animation, 0).get_size()) \
		* FUNKIN_TO_RUBICON
	sprite.position = Vector2(
		(SCREEN.x - art.x) * 0.5 + side * SCREEN.x / 3.0,
		(SCREEN.y - art.y) * 0.5 - FALL_RISE * FUNKIN_TO_RUBICON)
	parent.add_child(sprite)
	sprite.owner = _root


func _sparrow(png: String) -> SpriteFrames:
	if not ResourceLoader.exists(png):
		push_error("no existe %s" % png)
		return null
	var data := SparrowImporterSpriteData.new()
	data.texture = load(png)
	data.atlas_path = png.get_basename() + ".xml"
	data.fps = 24
	data.loop = true
	data.use_frame_duration = false
	var importer: SpriteImporter = load(
		"res://addons/sprite_importer/importers/sparrow.gd").new()
	return importer.convert_sprite([data])


func _add(node: Node) -> void:
	_root.add_child(node)
	node.owner = _root


## One gdanimate AnimateSymbol playing a composition's stage timeline on loop.
func _symbol(parent: Node2D, node_name: String, basename: String, animation: StringName,
		stage: String, scale: float, at: Vector2) -> void:
	var symbol := Node2D.new()
	symbol.name = node_name
	symbol.set_script(load("res://addons/gdanimate/animate_symbol.gd"))
	symbol.position = at
	symbol.scale = Vector2.ONE * scale
	symbol.set(&"centered", false)
	symbol.set(&"symbol", stage)
	var atlases: Array = symbol.get(&"atlases")
	atlases.append(load("%s/%s_atlas.tres" % [DIR, basename]))
	symbol.set(&"atlases", atlases)
	parent.add_child(symbol)
	symbol.owner = _root

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	symbol.add_child(player)
	player.owner = _root
	player.add_animation_library(&"", load("%s/%s_library.tres" % [DIR, basename]))
	var library: AnimationLibrary = player.get_animation_library(&"")
	if library.has_animation(animation):
		library.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
	player.autoplay = animation
