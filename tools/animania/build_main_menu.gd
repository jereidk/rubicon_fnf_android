# Authors animania_mod/menus/main/main_menu.tscn - a first cut, enough to LOOK at.
#
#   godot --headless --path . --script tools/animania/build_main_menu.gd
#
# The layout is not invented: every button ships a butts/<name>.json with an id and a rect,
# and MainMenuScreen's own BUTTONS_LIST is those eight names in id order (read out of the
# binary - see animania_mod/source/README.md). What is NOT settled yet is how the mod puts
# its 1352x790 authoring space on the screen, so that mapping is one constant here and the
# render is what will decide it.
extends SceneTree

const OUT := "res://animania_mod/menus/main/main_menu.tscn"
const DIR := "res://animania_mod/menus/main"
const ART := "res://animania_mod/source/images/menus/menu"
const SCREEN := Vector2(1920.0, 1080.0)

## menu background.png's own size. The buttons' rects live in THIS space, not in Funkin's
## 1280x720: the shop button's right edge lands at 1348, which only fits here.
const AUTHORED := Vector2(1352.0, 790.0)

## Funkin is 1280x720 and this project is 1920x1080. Anything the mod places against
## FlxG.width/height lives in THAT space, not in the background's.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## MEASURED, and it used to be a guess ("scale to cover, centre it"). The mod's own capture
## settles it: the panel's gaps fall on rows 423-430, 553-560 and 682-689 and on column
## 904-911 of a 1278-wide shot, and those are the seams between the button rects the JSONs
## carry - website ends at y=424 where options starts at 435, options ends at x=928 where
## credits starts at 941, and so on. Fitting the three row seams and the two column ones:
##
##     screen_1280 = 0.9033 * P + (62.5, 43.9)
##
## the same scale on both axes to within 0.2%. Times this project's 1.5. It is not a
## "cover" - it is the mod's camera resting at a zoom of 0.9 (which is what
## startIntroAnimation tweens to) looking at (646, 450) rather than at the screen centre.
## The same pair main_menu.gd carries: the one measured offset between this build and the
## mod's capture, taken by anything placed against FlxG.width/height.
const WORLD_OFFSET := Vector2(-4.0, -37.0)

const AUTHORED_SCALE := 0.9033
## The y carries a -6.6 the fit did not: rendered with 43.9 the three seams land on 433,
## 565 and 688 against the capture's 426, 556 and 685, all low by about the same. Measured
## residual, applied where it was measured.
const AUTHORED_ORIGIN := Vector2(62.5, 43.9 - 6.6)

var _scale: float = AUTHORED_SCALE * FUNKIN_TO_RUBICON
var _origin: Vector2 = AUTHORED_ORIGIN * FUNKIN_TO_RUBICON

var _root: Node2D


func _init() -> void:
	_root = Node2D.new()
	_root.name = "MainMenu"
	_root.set_script(load("res://animania_mod/menus/main/main_menu.gd"))

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = SCREEN * 0.5
	_add(camera)

	# The background does NOT take the buttons' mapping, and it is not a "cover" either -
	# that was this builder's guess. createBackground (0x1800500) is four lines:
	#
	#     bg.loadTexture("menus/menu/menu background")     # slot 0x448
	#     bg.x = (FlxG.width  - bg.width)  * 0.5           # 0x1800633
	#     bg.y = (FlxG.height - bg.height) * 0.5           # 0x1800680
	#     bg.scrollFactor.set(0.65, 0.65)                  # field 0x70, 0x18006b0
	#     bg.x -= 75                                       # 0x18006ee
	#
	# No scale anywhere: the 1352x790 art is drawn at its own size on a 1280x720 screen, so
	# it overhangs by 36 a side and 35 top and bottom, and then slides 75 left. Covering it
	# instead made it 5% too small AND centred, and lost the 75.
	const BG_PUSH := 75.0
	var background := Sprite2D.new()
	background.name = "Background"
	background.texture = load("%s/menu background.png" % ART)
	background.centered = false
	var bg_size: Vector2 = background.texture.get_size()
	background.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	background.position = (SCREEN - bg_size * FUNKIN_TO_RUBICON) * 0.5 \
		- Vector2(BG_PUSH * FUNKIN_TO_RUBICON, 0.0)
	_add(background)
	print("OUT fondo en (%.0f, %.0f) a x%.2f"
		% [background.position.x, background.position.y, FUNKIN_TO_RUBICON])

	# createParticles runs between the background and the visualisers (0x181118b).
	var particles := Node2D.new()
	particles.name = "Particles"
	particles.set_script(load("res://animania_mod/menus/main/menu_particles.gd"))
	_add(particles)

	# create() runs createVisualizers between the background and the plate (0x181119b), so
	# the waveform and the FFT bars sit behind everything else the menu draws. The node was
	# written months ago and never added to the scene, which is why nothing of it has ever
	# shown up in a render.
	var visualizer := Node2D.new()
	visualizer.name = "Visualizer"
	visualizer.set_script(load("res://animania_mod/menus/main/menu_visualizer.gd"))
	_add(visualizer)

	# `buttons back`, and its placement is MEASURED now rather than derived. It used to be
	# centred on the eight buttons' bounding box, which was the only thing those two sizes
	# allowed without the binary. createUIComponents does this instead:
	#
	#     plate.x = (FlxG.width  - plate.width)  * 0.5
	#     plate.y = (FlxG.height - plate.height) * 0.5
	#
	# - two cvtsi2sd of FlxG.width/height, a subsd of the sprite's own size and a multiply
	# by the 0.5 at .rodata 0x59fa5e0. So it is centred on the SCREEN and has nothing to do
	# with where the buttons are.
	# ...and THEN pushed right by 390: right after the two centring calls,
	# createUIComponents does `plate.set_x(390 + <x>)` (movsd of the 390 at .rodata
	# 0x59fad58, an addsd of a field 0x30 - which is `x` - and set_x through slot 0x210).
	# Centred alone puts the panel at 310 and the mod's own capture has its left edge on
	# column 701; 310 + 390 = 700. The port was drawing it across the middle of the screen,
	# behind the characters, instead of behind the buttons.
	#
	# Scaled by the project's flat 1.5 and not by the background's factor: it is placed
	# against FlxG.width/height, which is Funkin's 1280x720, so it lives in that space and
	# not in the background's 1352x790. That it comes out TALLER and WIDER than the screen
	# is the mod's own doing - (720 - 738) * 0.5 is a negative y, and 700 + 660 is past
	# 1280, so the code expects it to bleed on both.
	const PLATE_PUSH := 390.0
	var plate := Sprite2D.new()
	plate.name = "ButtonsBack"
	plate.texture = load("%s/buttons back.png" % ART)
	plate.centered = false
	plate.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	plate.position = (SCREEN - plate.texture.get_size() * FUNKIN_TO_RUBICON) * 0.5 \
		+ Vector2(PLATE_PUSH * FUNKIN_TO_RUBICON, 0.0)
	_add(plate)
	print("OUT placa centrada en pantalla en (%.0f, %.0f)"
		% [plate.position.x, plate.position.y])

	var atlas: Resource = load("%s/menu_buttons_atlas.tres" % DIR)
	var library: AnimationLibrary = load("%s/menu_buttons_library.tres" % DIR)
	# `basic` and `white` are idle cycles - six and four frames - and have to loop, or a
	# button plays its handful of frames once and then sits there dead. `confirm` is the
	# one that must not: doSelect waits it out and then leaves.
	#
	# The player only ever runs `confirm`, though: the idles are driven by the menu itself
	# off one shared clock (see main_menu.gd IDLE_FPS), which is what the mod does. The loop
	# flag stays right anyway so the library reads correctly on its own.
	var looped: int = 0
	for animation_name: StringName in library.get_animation_list():
		var wants_loop: bool = String(animation_name).ends_with("_basic") \
			or String(animation_name).ends_with("_white")
		library.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR \
			if wants_loop else Animation.LOOP_NONE
		looped += 1 if wants_loop else 0
	ResourceSaver.save(library, "%s/menu_buttons_library.tres" % DIR)
	print("OUT %d de %d animaciones de boton en bucle" % [
		looped, library.get_animation_list().size()])
	var buttons := Node2D.new()
	buttons.name = "Buttons"
	_add(buttons)

	var rects: Dictionary = {}
	var order: PackedStringArray = [
		"storymode", "shop", "freeplay", "website", "options", "credits", "awards", "exit",
	]
	for id: int in order.size():
		var name: String = order[id]
		var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("%s/butts/%s.json" % [ART, name]))
		var pos: Array = data["pos"]
		rects[name] = Rect2(float(pos[0]), float(pos[1]), float(pos[2]), float(pos[3]))
		var symbol := AnimateSymbol.new()
		symbol.name = name.capitalize()
		symbol.atlases = [atlas] as Array[AnimateAtlas]
		symbol.atlas_index = 0
		symbol.symbol = "render/eng/%s basic" % name
		symbol.centered = false
		symbol.scale = Vector2.ONE * _scale
		symbol.position = _origin + Vector2(float(pos[0]), float(pos[1])) * _scale
		# The rect a tap has to land in, in SCREEN pixels. It is the button's own rect from
		# its JSON put through the same mapping the sprite is, so the touch area and the art
		# cannot drift apart: on a phone the buttons ARE the menu's controls.
		symbol.set_meta(&"touch_rect", Rect2(
			_origin + Vector2(float(pos[0]), float(pos[1])) * _scale,
			Vector2(float(pos[2]), float(pos[3])) * _scale))
		# What each state IS, taken off the library rather than named again here: the
		# composition the symbol has to show and how many frames its cycle is. The menu
		# needs both to drive the idles itself, and reading them from the animation that
		# already carries them is one source instead of two that can disagree.
		symbol.set_meta(&"states", _states_of(library, name))
		buttons.add_child(symbol)
		symbol.owner = _root

		var player := AnimationPlayer.new()
		player.name = "AnimationPlayer"
		player.add_animation_library(&"", library)
		player.autoplay = StringName("menu_buttons_%s_basic" % name)
		symbol.add_child(player)
		player.owner = _root
		print("OUT %-10s id=%d rect=(%s, %s, %s, %s) -> pantalla (%.0f, %.0f)" % [
			name, int(data["id"]), pos[0], pos[1], pos[2], pos[3],
			symbol.position.x, symbol.position.y])

	# createNewsButton (0x18017a0): the changelog banner, at (-70, 620) at scale 0.5, with
	# its three states taken off FRAME LABELS rather than symbols - see build_news_button.gd.
	# createSpecialElements calls it before createMusicSocial, so it draws under the disc.
	const NEWS_POS := Vector2(-70.0, 620.0)
	const NEWS_SCALE := 0.5
	var news_atlas: Resource = load("%s/news_button_atlas.tres" % DIR)
	var news_library: AnimationLibrary = load("%s/news_button_library.tres" % DIR)
	if news_atlas != null and news_library != null:
		var news := AnimateSymbol.new()
		news.name = "NewsButton"
		news.atlases = [news_atlas] as Array[AnimateAtlas]
		news.atlas_index = 0
		news.centered = false
		news.scale = Vector2.ONE * (NEWS_SCALE * FUNKIN_TO_RUBICON)
		news.position = (NEWS_POS + WORLD_OFFSET) * FUNKIN_TO_RUBICON
		# AnimateSymbol has no bounds to ask for, so the tap rect comes from the mod's own
		# flattened copy of the same banner: new_update_bub.png is 1184x106, which is the
		# composition at scale 1 (its spritemap is 1183 wide).
		news.set_meta(&"touch_rect", Rect2(news.position,
			Vector2(1184.0, 106.0) * NEWS_SCALE * FUNKIN_TO_RUBICON))
		_add(news)
		var news_player := AnimationPlayer.new()
		news_player.name = "AnimationPlayer"
		news_player.add_animation_library(&"", news_library)
		news_player.autoplay = &"news_button_idle"
		news.add_child(news_player)
		news_player.owner = _root
		print("OUT boton de novedades en (%.0f, %.0f)" % [news.position.x, news.position.y])

	# caramelDance.json: the caramen-dance atlas at (-75, 225), scale 1.1, animation
	# `caramel`. Straight out of the file, like the buttons' rects.
	var dude_data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/dudes/caramelDance.json" % ART))
	var dude_pos: Array = dude_data["pos"]
	var dude := AnimatedSprite2D.new()
	dude.name = "Dude"
	dude.sprite_frames = load("%s/menu_dude_frames.tres" % DIR)
	dude.animation = &"caramel"
	dude.centered = false
	dude.autoplay = "caramel"
	dude.scale = Vector2.ONE * float(dude_data["scale"]) * _scale
	dude.position = _origin + Vector2(float(dude_pos[0]), float(dude_pos[1])) * _scale
	_root.add_child(dude)
	# Over the plate and under the buttons: caramelDance.json calls it layer 1, and he
	# stands on the left where the buttons are not. Put at index 1 he went BEHIND the
	# background and disappeared - the background is index 1.
	_root.move_child(dude, plate.get_index() + 1)
	dude.owner = _root
	print("OUT el que baila en (%.0f, %.0f), escala %.2f" % [
		dude.position.x, dude.position.y, dude.scale.x])

	# button_lock.png over each of the three MainMenuScreen.BLOCKED_BUTTONS. Centred on the
	# button it covers: the lock is 17 frames of animation and the rect is what it locks.
	var blocked: PackedStringArray = ["shop", "website", "awards"]
	var lock_frames: SpriteFrames = load("%s/menu_lock_frames.tres" % DIR)
	var lock_animation: StringName = lock_frames.get_animation_names()[0]
	var lock_size: Vector2 = lock_frames.get_frame_texture(lock_animation, 0).get_size()
	# createBlockedButton's first line (0x1806989): the button UNDER the lock is greyed to
	# 0xFFAAAAAA before the padlock goes on it. Without it the three locked entries were as
	# bright as the four you can actually press.
	const BLOCKED_TINT := Color(0xAA / 255.0, 0xAA / 255.0, 0xAA / 255.0)
	for name: String in blocked:
		var rect: Rect2 = rects[name]
		var under: Node2D = buttons.get_node_or_null(NodePath(name.capitalize())) as Node2D
		if under != null:
			under.modulate = BLOCKED_TINT
		var lock := AnimatedSprite2D.new()
		lock.name = "%sLock" % name.capitalize()
		lock.sprite_frames = lock_frames
		lock.animation = lock_animation
		lock.autoplay = String(lock_animation)
		lock.centered = false
		lock.scale = Vector2.ONE * _scale
		lock.position = _origin + (rect.get_center() - lock_size * 0.5) * _scale
		buttons.add_child(lock)
		lock.owner = _root

	# SeasonalEmitter. Which season is exact - getCurrentSeason reads the month - and only
	# winter and autumn have art.
	var seasonal := Node2D.new()
	seasonal.name = "Seasonal"
	seasonal.set_script(load("res://animania_mod/menus/main/menu_seasonal.gd"))
	seasonal.set(&"snow_frames", load("%s/menu_snow_frames.tres" % DIR))
	seasonal.set(&"leaf_frames", load("%s/menu_leafs_frames.tres" % DIR))
	seasonal.set(&"area", SCREEN)
	_add(seasonal)

	# initMusic. `playMusic` starts the loop the title's intro leads into, and
	# `AnimaniaLOOPbass` is loaded beside it as a second track with LOWPASS and GAIN
	# filters on it - a bass layer the screen ducks in and out. Only the loop is wired
	# here; the layer is vendored and waits for what drives its filter.
	var music := AudioStreamPlayer.new()
	music.name = "Music"
	music.stream = load("res://animania_mod/source/music/animaniaLOOP/animaniaLOOP.ogg")
	music.bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	music.autoplay = true
	if music.stream is AudioStreamOggVorbis:
		(music.stream as AudioStreamOggVorbis).loop = true
	_add(music)

	# blackLineUp and blackLineDown: two FunkinSprites made solid 0xFF000000,
	# Std.int(FlxG.width * 1.25) wide by FlxG.height tall. A whole screen each, and wider
	# than one so the intro's random angle and offset cannot uncover an edge. They are
	# world space, like the mod's - scrollFactor 1, so the camera moves over them.
	var curtains: Array[Control] = []
	for which: String in ["BlackLineUp", "BlackLineDown"]:
		var curtain := ColorRect.new()
		curtain.name = which
		curtain.color = Color(0.0, 0.0, 0.0, 1.0)
		curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		curtain.size = Vector2(SCREEN.x * 1.25, SCREEN.y)
		curtain.position = Vector2((SCREEN.x - SCREEN.x * 1.25) * 0.5, 0.0)
		_add(curtain)
		curtains.append(curtain)

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	_root.set(&"buttons", buttons)
	_root.set(&"sfx", sfx)
	_root.set(&"music", music)
	_root.set(&"camera", camera)
	_root.set(&"dude", dude)
	_root.set(&"curtain_up", curtains[0])
	_root.set(&"curtain_down", curtains[1])

	var packed := PackedScene.new()
	packed.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	ResourceSaver.save(packed, OUT)
	print("OUT espacio %s escalado x%.4f, origen (%.0f, %.0f)" % [
		AUTHORED, _scale, _origin.x, _origin.y])
	print("OUT saved %s" % OUT)
	quit(0)


func _add(node: Node) -> void:
	_root.add_child(node)
	node.owner = _root


## { state: { "symbol": String, "frames": int } } for one button, read out of the
## AnimationLibrary the same animations are built from.
func _states_of(library: AnimationLibrary, name: String) -> Dictionary:
	var states: Dictionary = {}
	for state: String in ["basic", "white", "confirm"]:
		var key := StringName("menu_buttons_%s_%s" % [name, state])
		if not library.has_animation(key):
			continue
		var animation: Animation = library.get_animation(key)
		var entry: Dictionary = {"symbol": "", "frames": 0}
		for track: int in animation.get_track_count():
			var path: NodePath = animation.track_get_path(track)
			if path == ^".:symbol" and animation.track_get_key_count(track) > 0:
				entry["symbol"] = String(animation.track_get_key_value(track, 0))
			elif path == ^".:frame":
				entry["frames"] = animation.track_get_key_count(track)
		states[state] = entry
	return states
