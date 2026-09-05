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

	# Only tv glow's y is a constant; its x is worked out from something buildBg computes
	# earlier, and the TV's placement is not a constant at all - it is created through
	# Paths.imageGraphic and positioned by setters that read other sprites. So both x's are
	# placed rather than read, and the arithmetic says where: the wall is 912 wide in a
	# 1280 screen, which leaves 368 of nothing to the right, and the TV is 727 wide. Put
	# its right edge on the screen's, at x = 553, and it covers that gap exactly while
	# overlapping the wall by the rest. The glow is 997 wide and lands the same way.
	_sprite("TvGlow", "bg/tv glow.png", Vector2(283.0, 493.0))
	_sparrow("Tv", "freeplay_tv", "freeplay tv образец ", Vector2(553.0, 60.0))

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
		disk.centered = true
		disk.scale = Vector2.ONE * FUNKIN_TO_RUBICON
		# The rect a tap has to land in, around the disk's own middle - the sprite is
		# centred, so this is too. Kept in the disk's LOCAL space so the carousel can move
		# it without the hitbox drifting.
		var size: Vector2 = disk.texture.get_size() * FUNKIN_TO_RUBICON
		disk.set_meta(&"hitbox", Rect2(-size * 0.5, size))
		disk.set_meta(&"index", i)
		disk.set_meta(&"target", Vector2.ZERO)
		disk.set_meta(&"scale", 1.0)
		disk.set_meta(&"alpha", 1.0)
		disks.add_child(disk)
		disk.owner = _root
		print("OUT disco %d: %s %dx%d" % [i, song["disk"], size.x, size.y])

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
