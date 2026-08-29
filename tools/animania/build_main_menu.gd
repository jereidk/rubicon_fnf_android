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

	# The plate the buttons sit on. DERIVED, not measured: `buttons back.png` is 660x738 and
	# the eight rects span 591x704, so it is that block with a margin - centred on it is the
	# only placement those two numbers allow. Where MainMenuScreen.create() actually puts it
	# is at 0x1804250 in the Linux build, which loads "menus/menu/buttons back"; tracing the
	# cvtsi2sd that feeds its position is the way to replace this reading with a fact.
	var block := Rect2(Vector2(757.0, 7.0), Vector2(1348.0 - 757.0, 711.0 - 7.0))
	var plate := Sprite2D.new()
	plate.name = "ButtonsBack"
	plate.texture = load("%s/buttons back.png" % ART)
	plate.centered = false
	plate.scale = Vector2.ONE * _scale
	plate.position = _origin + (block.get_center()
		- plate.texture.get_size() * 0.5) * _scale
	_add(plate)
	print("OUT placa detras de los botones en (%.0f, %.0f), derivada del bloque"
		% [plate.position.x, plate.position.y])

	var atlas: Resource = load("%s/menu_buttons_atlas.tres" % DIR)
	var library: AnimationLibrary = load("%s/menu_buttons_library.tres" % DIR)
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
	# Right after the background and before the plate: caramelDance.json calls it layer 1,
	# and he stands on the left where the buttons are not. Put at index 1 he went BEHIND the
	# background and disappeared - the background is index 1.
	_root.move_child(dude, background.get_index() + 1)
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

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	_root.set(&"buttons", buttons)
	_root.set(&"sfx", sfx)

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
