# Authors animania_mod/menus/freeplay/freeplay_screen.tscn.
#
#   godot --headless --path . --script tools/animania/build_freeplay_scene.gd
#
# The diorama's placements come out of FreeplayScreen.buildBg in the Linux build: a black
# backdrop, `freeplay backwall`, the `bed` sparrow, `tv glow`, the TV itself, and the
# `player` with its `player-layer` over it.
#
# Reading a FunkinSprite.create call takes one step of care. It takes two Null<double>, each
# a 16-byte block of {flag byte, double}, and the caller builds both on the stack - so which
# block is x is not obvious from the loads. create() itself settles it: it does
# `cmpb $0,(%rsi); jne skip; mov 0x8(%rsi),%r13` for the first and the same on %rdx for the
# second, and buildBg loads %rsi from the block at -0x70 and %rdx from the one at -0x60. So
# the FIRST block is x, and a flag byte of zero means the value is there.
#
# Read that way: backwall (0, 18.75), bed (0, 254), tv glow (computed, 493), player
# (50, 505), player-layer (45.75, 515) - a bedroom with the wall behind, the bed under it
# and the VCR at the bottom left. Getting it backwards put the VCR in the sky.
extends SceneTree

const OUT := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const DIR := "res://animania_mod/menus/freeplay"
const ART := "res://animania_mod/source/images/freeplay"
const SCREEN := Vector2(1920.0, 1080.0)

## Funkin is 1280x720 and this project is 1920x1080. buildBg places everything against
## FlxG.width/height, so the whole diorama lives in that space.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

var _root: Node2D


func _init() -> void:
	# Los dos atlas de televisor los adelgaza tools/animania/optimize_atlas.py; sus
	# SpriteFrames se generan aqui para que la escena no dependa de un .tres a mano.
	_build_frames("TVNOISE", "freeplay_tvnoise", 24.0)
	_build_frames("TVBACK", "freeplay_tvback", 24.0)

	_root = Node2D.new()
	_root.name = "FreeplayScreen"
	_root.set_script(load("res://animania_mod/menus/freeplay/freeplay_screen.gd"))

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.position = SCREEN * 0.5
	_add(camera)

	# buildBg's first sprite: a black FlxSprite blown up to 1500x1500 and centred. It is
	# what the diorama sits on, and why nothing behind it can show through.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(backdrop)
	backdrop.set(&"layout_mode", 0)
	backdrop.size = Vector2.ONE * 1500.0 * FUNKIN_TO_RUBICON
	backdrop.position = (SCREEN - backdrop.size) * 0.5

	_sprite("Backwall", "bg/freeplay backwall.png", Vector2(0.0, 18.75))

	# The bed. Three frames that are three STATES rather than a cycle. buildBg names them
	# with addByIndices: `light` -> [0], `normal` -> [1], `none` -> [2] (the third one is
	# `none`, read out of the binary rather than guessed), and checkBed(name) plays one of
	# them. create() ends on checkBed('none'), so the screen opens on frame 2.
	#
	# `pause()` here did nothing to the saved scene: _sparrow sets `autoplay`, which the
	# packed scene keeps, so the bed came back cycling all three frames at 24 fps on load.
	# Clear autoplay, or the bed flickers through its own states for ever.
	var bed: AnimatedSprite2D = _sparrow("Bed", "freeplay_bed", "bed", Vector2(0.0, 254.0))
	bed.autoplay = ""
	bed.frame = 2

	# shadowsOnBed is a funkin.graphics.framebuffer.FlxLayerGroup (buildBg line 1216), and
	# shakeShadows scales its matrix. Nothing is inside it yet - the shadow art rides on
	# tvNoiseBack, which is not ported - so this is an empty seat, but _resolve_nodes looks
	# it up and it has to exist. It sits between the bed and the glow in draw order.
	var shadows := Node2D.new()
	shadows.name = "ShadowsOnBed"
	_add(shadows)

	# Only tv glow's y is a constant; its x is worked out from something buildBg computes
	# earlier, and the TV's placement is not a constant at all - it is created through
	# Paths.imageGraphic and positioned by setters that read other sprites. So both x's are
	# placed rather than read, and the arithmetic says where: the wall is 912 wide in a
	# 1280 screen, which leaves 368 of nothing to the right, and the TV is 727 wide. Put
	# its right edge on the screen's, at x = 553, and it covers that gap exactly while
	# overlapping the wall by the rest. The glow is 997 wide and lands the same way.
	_sprite("TvGlow", "bg/tv glow.png", Vector2(283.0, 493.0))

	# La pantalla del televisor, leida de buildBg linea por linea. Todo lo de dentro
	# comparte esquina en (117, 128) y el rectangulo mide 375x305; el zIndex de cada pieza
	# sale de su `movl $N,0x28(%rax)` y es lo que decide el orden:
	#
	#   1247-1255  tvBg           createSparrow(0, 0, 'bg/TVBACK'), anim 'a' de 'pink' @24, z 10
	#   1289-1297  tvBackBG       makeGraphic(375, 305, 0xFF000000), invisible, z 20
	#   1299-1307  tvSpriteFlash  makeGraphic(375, 305, 0xFFFFFFFF), invisible, z 29
	#   1309-1317  tvNoiseBack    createSparrow(117, 128, 'bg/TVNOISE'), 'noise sprite' @24, z 26
	#   1327-1336  tvNoiseForward igual, alpha 0.45, z 28
	#   1337       tvNoiseForward.animation.onFrameChange.add(_ -> shakeShadows())
	#
	# La animacion de tvBg se llama 'a' en el mod (addByPrefix('a', 'pink')); aqui se queda
	# con el nombre del prefijo, que es como las nombra el importador de sparrow.
	#
	# El orden completo del diorama, por si hace falta: bgWall 1, bgBed 2, shadowsOnBed 3,
	# tvGlow 7, darkOverlay 8, tvBg 10, diskPlayer 16, grpDisks 19, tvBackBG 20,
	# diskPlayerMask 24, tvNoiseBack 26, albumRoll 27, tvNoiseForward 28, tvSpriteFlash 29,
	# tvSprite 30, difficultyStars 35, selectorsGroup 100, bossfightSkull 900.
	const TV_INNER := Vector2(117.0, 128.0)
	const TV_INNER_SIZE := Vector2(375.0, 305.0)

	var tv_bg: AnimatedSprite2D = _sparrow("TvBg", "freeplay_tvback", "pink", Vector2.ZERO)
	tv_bg.z_index = 10

	var tv_back_bg := _panel("TvBackBG", TV_INNER, TV_INNER_SIZE, Color(0, 0, 0, 1))
	tv_back_bg.z_index = 20
	tv_back_bg.visible = false

	var noise_back: AnimatedSprite2D = _sparrow(
		"TvNoiseBack", "freeplay_tvnoise", "noise sprite", TV_INNER)
	noise_back.z_index = 26

	var noise_forward: AnimatedSprite2D = _sparrow(
		"TvNoiseForward", "freeplay_tvnoise", "noise sprite", TV_INNER)
	noise_forward.z_index = 28
	noise_forward.modulate.a = 0.45

	var tv_flash := _panel("TvSpriteFlash", TV_INNER, TV_INNER_SIZE, Color(1, 1, 1, 1))
	tv_flash.z_index = 29
	tv_flash.visible = false

	# El televisor NO estaba en (553, 60) ni mostraba el fotograma que toca. Esa x se habia
	# colocado por aritmetica -"el muro mide 912 de 1280, quedan 368 a la derecha y el tele
	# mide 727"- porque buildBg lo posiciona con setters en vez de con constantes. Pero las
	# piezas de DENTRO si son constantes, y son ellas las que lo fijan.
	#
	# El sparrow trae seis fotogramas en tres tamanos: 727x627 con la pantalla opaca y un
	# halo azul, y dos pares huecos de 451x473 y 466x457. buildBg hace addByPrefix('f'),
	# que casa con los seis, y luego finish() (linea 1281), que deja la animacion en el
	# ULTIMO: el 466x457, cuya pantalla es un agujero transparente. El puerto se quedaba en
	# el primero, con la pantalla tapada, y por eso nada de lo de dentro se veia.
	#
	# La posicion es la del constructor, linea 1277: new FunkinSprite(-60, -198). Cuadra
	# hasta el pixel una vez se tiene en cuenta que el sparrow viene RECORTADO: los seis
	# fotogramas declaran frameWidth 727 x frameHeight 749, y el hueco de 466x457 se pega
	# dentro de ese lienzo en (135, 288). El agujero de su pantalla va de (60, 49) a
	# (402, 326), o sea (195, 337) + 342x277 dentro del lienzo; con el sprite en (-60, -198)
	# eso cae en (135, 139)-(477, 416), justo dentro del rectangulo de (117, 128)+375x305,
	# que sobresale unos pixeles por cada lado para que el bisel redondeado no deje huecos.
	#
	# El importador de sparrow rellena los tres fotogramas al lienzo comun, asi que aqui son
	# tres de 727x749 y el hueco es el indice 2.
	const TV_FRAME := 2
	var tv: AnimatedSprite2D = _sparrow(
		"Tv", "freeplay_tv", "freeplay tv образец ", Vector2(-60.0, -198.0))
	tv.z_index = 30
	tv.autoplay = ""
	tv.frame = TV_FRAME

	# The VCR and the layer that goes over it, four pixels left and ten down from it.
	_sparrow("Player", "freeplay_player", "player", Vector2(50.0, 505.0))
	_sprite("PlayerLayer", "bg/player-layer.png", Vector2(45.75, 515.0))

	var disks := Node2D.new()
	disks.name = "Disks"
	_add(disks)

	var songs: Array = _root.get_script().get_script_constant_map()["SONGS"]
	for i: int in songs.size():
		var song: Dictionary = songs[i]
		var disk := Sprite2D.new()
		disk.name = "Disk%d" % i
		disk.texture = load("%s/disks/%s.png" % [ART, song["disk"]])
		# updateDisks (linea 800) escribe disk.x, y en flixel eso es el borde IZQUIERDO:
		# la fila se alinea por ahi, no por el centro, y los discos no miden todos igual.
		disk.centered = false
		disk.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		# The rect a tap has to land in, around the disk's own middle - the sprite is
		# centred, so this is too. Kept in the disk's LOCAL space so the carousel can move
		# it without the hitbox drifting.
		var size: Vector2 = disk.texture.get_size() * FUNKIN_TO_RUBICON
		disk.set_meta(&"hitbox", Rect2(Vector2.ZERO, size))
		disk.set_meta(&"index", i)
		disk.set_meta(&"target", Vector2.ZERO)
		disk.set_meta(&"scale", 1.0)
		disk.set_meta(&"alpha", 1.0)
		disks.add_child(disk)
		disk.owner = _root
		print("OUT disco %d: %s %dx%d" % [i, song["disk"], size.x, size.y])

	# The UI layer. These are the placeholders the script's _resolve_nodes() looks up; they
	# were hand-added to the scene once and this builder did not know about them, so a
	# rebuild wiped them. Anything the script resolves has to be built HERE.
	var ui := Node2D.new()
	ui.name = "UI"
	_add(ui)
	_label(ui, "HighScore", Rect2(1400.0, 50.0, 450.0, 40.0), "0")
	var clear_box := Sprite2D.new()
	clear_box.name = "ClearBox"
	clear_box.texture = load("%s/bg/clearBox.png" % ART)
	clear_box.position = Vector2(1500.0, 100.0)
	clear_box.scale = Vector2.ONE * 0.8
	ui.add_child(clear_box)
	clear_box.owner = _root
	_label(ui, "InfoTitle", Rect2(100.0, 30.0, 500.0, 40.0), "")
	_label(ui, "InfoBpm", Rect2(100.0, 70.0, 500.0, 40.0), "")
	_label(ui, "InfoDifficulty", Rect2(100.0, 110.0, 500.0, 40.0), "Normal")
	var stars := Node2D.new()
	stars.name = "DifficultyStars"
	stars.position = Vector2(100.0, 130.0)
	ui.add_child(stars)
	stars.owner = _root
	var album := Node2D.new()
	album.name = "AlbumRoll"
	ui.add_child(album)
	album.owner = _root
	var help := Sprite2D.new()
	help.name = "HelpButton"
	help.position = Vector2(1800.0, 1000.0)
	ui.add_child(help)
	help.owner = _root

	# fadeOut / doIntroAnim drive this; it is opaque black at rest and the intro clears it.
	var dark := ColorRect.new()
	dark.name = "DarkOverlay"
	dark.set(&"layout_mode", 0)
	dark.offset_left = -200.0
	dark.offset_top = -200.0
	dark.offset_right = 2120.0
	dark.offset_bottom = 1280.0
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.color = Color(0.0, 0.0, 0.0, 1.0)
	_add(dark)

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_add(sfx)

	_root.set(&"disks", disks)
	_root.set(&"sfx", sfx)
	_root.set(&"bed", bed)

	var packed := PackedScene.new()
	packed.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %s %s" % ["saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)


## makeGraphic(w, h, color): un rectangulo liso, colocado por su esquina como todo aqui.
## Genera un SpriteFrames a partir de un sparrow vendorizado. Se reconstruye siempre, sin
## comprobar si ya existe: un builder que se salta su propio trabajo cuando encuentra la
## version anterior es la trampa de siempre.
func _build_frames(source_name: String, basename: String, fps: float) -> void:
	var data := SparrowImporterSpriteData.new()
	data.texture = load("%s/bg/%s.png" % [ART, source_name])
	data.atlas_path = "%s/bg/%s.xml" % [ART, source_name]
	data.fps = fps
	data.loop = true
	# Igual que en build_icons.gd: sparrow.gd revienta con las duraciones puestas cuando
	# hay fotogramas repetidos, y TVBACK trae doce.
	data.use_frame_duration = false
	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	var frames: SpriteFrames = importer.convert_sprite([data])
	var out := "%s/%s_frames.tres" % [DIR, basename]
	var err: int = ResourceSaver.save(frames, out)
	print("OUT %s %s  %s" % ["frames" if err == OK else "FALLO", out,
		str(frames.get_animation_names())])


func _panel(node_name: String, at: Vector2, size: Vector2, color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.name = node_name
	panel.set(&"layout_mode", 0)
	panel.offset_left = at.x * FUNKIN_TO_RUBICON
	panel.offset_top = at.y * FUNKIN_TO_RUBICON
	panel.offset_right = (at.x + size.x) * FUNKIN_TO_RUBICON
	panel.offset_bottom = (at.y + size.y) * FUNKIN_TO_RUBICON
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.color = color
	_add(panel)
	return panel


func _label(parent: Node, node_name: String, box: Rect2, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.set(&"layout_mode", 0)
	label.offset_left = box.position.x
	label.offset_top = box.position.y
	label.offset_right = box.position.x + box.size.x
	label.offset_bottom = box.position.y + box.size.y
	label.text = text
	parent.add_child(label)
	label.owner = _root
	return label


func _add(node: Node) -> void:
	_root.add_child(node)
	node.owner = _root


## One flat piece of the diorama, placed by its top-left corner the way FunkinSprite.create
## does.
func _sprite(node_name: String, path: String, at: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = load("%s/%s" % [ART, path])
	sprite.centered = false
	sprite.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	sprite.position = at * FUNKIN_TO_RUBICON
	_add(sprite)
	return sprite


func _sparrow(node_name: String, basename: String, animation: String,
		at: Vector2) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name
	sprite.sprite_frames = load("%s/%s_frames.tres" % [DIR, basename])
	sprite.animation = StringName(animation)
	sprite.autoplay = animation
	sprite.centered = false
	sprite.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	sprite.position = at * FUNKIN_TO_RUBICON
	_add(sprite)
	return sprite
