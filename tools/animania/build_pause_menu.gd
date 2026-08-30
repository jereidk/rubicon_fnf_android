# Authors animania_mod/menus/pause/pause_menu.tscn, the overlay a level instances.
#
#   godot --headless --path . --script tools/animania/build_pause_menu.gd
#
# The art is the mod's. The LAYOUT is not: PauseSubState is base Funkin and the mod's own
# subclass is compiled, and neither was recovered - so the panel and the list are placed
# against the art's own sizes and this comment is the marker for that.
extends SceneTree

const OUT := "res://animania_mod/menus/pause/pause_menu.tscn"
const DIR := "res://animania_mod/menus/pause"
const ART := "res://animania_mod/source/images/pause"
const SCREEN := Vector2(1920.0, 1080.0)
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## The panel sits against the left edge and the options run down it.
const LIST_TOP := 300.0
const LIST_SPACING := 150.0
const LIST_X := 260.0

var _root: CanvasLayer


func _init() -> void:
	_root = CanvasLayer.new()
	_root.name = "PauseMenu"
	# Above the HUD (which the level puts on 10) and above the mobile controls (15).
	_root.layer = 40
	_root.set_script(load("res://animania_mod/menus/pause/pause_menu.gd"))

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.owner = _root
	dim.set(&"layout_mode", 0)
	dim.size = SCREEN

	var panel := Sprite2D.new()
	panel.name = "Panel"
	panel.texture = load("%s/menuleft.png" % ART)
	panel.centered = false
	panel.scale = Vector2.ONE * FUNKIN_TO_RUBICON
	panel.position = Vector2(0.0, SCREEN.y - panel.texture.get_size().y * FUNKIN_TO_RUBICON)
	_root.add_child(panel)
	panel.owner = _root

	var buttons := Node2D.new()
	buttons.name = "Buttons"
	_root.add_child(buttons)
	buttons.owner = _root

	# The option names as the atlases spell them - the frames are "<prefix> basic" and
	# "<prefix> white", and the prefix is the file's own name lowercased.
	var prefixes := {
		"resume": "resume", "restart": "restart",
		"change_difficulty": "change difficulty", "options": "options", "exit": "exit",
	}
	var options: PackedStringArray = _root.get_script().get_script_constant_map()["OPTIONS"]
	for i: int in options.size():
		var option: String = options[i]
		var button := AnimatedSprite2D.new()
		button.name = option.to_pascal_case()
		button.sprite_frames = load("%s/pause_%s_frames.tres" % [DIR, option])
		button.centered = true
		button.scale = Vector2.ONE * 0.55 * FUNKIN_TO_RUBICON
		button.position = Vector2(LIST_X, LIST_TOP + LIST_SPACING * float(i))
		button.set_meta(&"prefix", prefixes[option])
		var first: StringName = StringName("%s basic" % prefixes[option])
		if button.sprite_frames.has_animation(first):
			button.animation = first
		var size: Vector2 = button.sprite_frames.get_frame_texture(
			button.animation, 0).get_size() * button.scale
		# In the button's LOCAL space, so the list can move without the hitbox drifting -
		# the same shape freeplay's disks and story's titles use.
		button.set_meta(&"hitbox", Rect2(-size * 0.5, size))
		buttons.add_child(button)
		button.owner = _root
		print("OUT %-18s %s %dx%d" % [option, button.animation, size.x, size.y])

	var sfx := AudioStreamPlayer.new()
	sfx.name = "Sfx"
	sfx.bus = &"Master"
	_root.add_child(sfx)
	sfx.owner = _root

	var music := AudioStreamPlayer.new()
	music.name = "Music"
	music.stream = load("%s/breakfast-phonecall.ogg"
		% "res://animania_mod/source/music/breakfast")
	music.bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else &"Master"
	if music.stream is AudioStreamOggVorbis:
		(music.stream as AudioStreamOggVorbis).loop = true
	_root.add_child(music)
	music.owner = _root

	_root.set(&"dim", dim)
	_root.set(&"buttons", buttons)
	_root.set(&"sfx", sfx)
	_root.set(&"music", music)

	var packed := PackedScene.new()
	packed.pack(_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %s %s" % ["saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)
