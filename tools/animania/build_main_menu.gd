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

	var order: PackedStringArray = [
		"storymode", "shop", "freeplay", "website", "options", "credits", "awards", "exit",
	]
	for id: int in order.size():
		var name: String = order[id]
		var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("%s/butts/%s.json" % [ART, name]))
		var pos: Array = data["pos"]
		var symbol := AnimateSymbol.new()
		symbol.name = name.capitalize()
		symbol.atlases = [atlas] as Array[AnimateAtlas]
		symbol.atlas_index = 0
		symbol.symbol = "render/eng/%s basic" % name
		symbol.centered = false
		symbol.scale = Vector2.ONE * _scale
		symbol.position = _origin + Vector2(float(pos[0]), float(pos[1])) * _scale
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

	var dude_data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/dudes/caramelDance.json" % ART))
	print("OUT el que baila: %s" % dude_data)

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
