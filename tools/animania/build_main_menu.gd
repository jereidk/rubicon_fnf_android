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

## Scaled to COVER the screen and centred, so the background has no edges showing and the
## buttons keep their positions relative to it. Whether the mod does exactly this is the one
## thing about the layout that is still a reading rather than a measurement.
var _scale: float = maxf(SCREEN.x / AUTHORED.x, SCREEN.y / AUTHORED.y)
var _origin: Vector2 = (SCREEN - AUTHORED * _scale) * 0.5

var _root: Node2D


func _init() -> void:
	_root = Node2D.new()
	_root.name = "MainMenu"
	_root.set_script(load("res://animania_mod/menus/main/main_menu.gd"))

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = SCREEN * 0.5
	_add(camera)

	var background := Sprite2D.new()
	background.name = "Background"
	background.texture = load("%s/menu background.png" % ART)
	background.centered = false
	background.scale = Vector2.ONE * _scale
	background.position = _origin
	_add(background)

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
	# Scaled by the project's flat 1.5 and not by the background's factor: it is placed
	# against FlxG.width/height, which is Funkin's 1280x720, so it lives in that space and
	# not in the background's 1352x790. That it comes out TALLER than the screen is the
	# mod's own doing - (720 - 738) * 0.5 is a negative y, so the code expects it to bleed.
	var plate := Sprite2D.new()
	plate.name = "ButtonsBack"
	plate.texture = load("%s/buttons back.png" % ART)
	plate.centered = false
	plate.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	plate.position = (SCREEN - plate.texture.get_size() * FUNKIN_TO_RUBICON) * 0.5
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
	for name: String in blocked:
		var rect: Rect2 = rects[name]
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

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	_root.set(&"buttons", buttons)
	_root.set(&"sfx", sfx)
	_root.set(&"music", music)
	_root.set(&"camera", camera)

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
