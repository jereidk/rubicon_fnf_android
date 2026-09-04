# Generates animania_mod/menus/loading/loading_screen.tscn.
#
# The scene is only the five sprites the mod's LoadingState builds plus the
# music player; every coordinate lives in loading_screen.gd, next to the address
# it was read from, so this builder just wires the nodes and their art.
#
#   godot --headless --path . --script tools/animania/build_loading_screen.gd

extends SceneTree

const OUT := "res://animania_mod/menus/loading/loading_screen.tscn"
const SCRIPT := "res://animania_mod/menus/loading/loading_screen.gd"
const ART := "res://animania_mod/source/images/loadingScreen"
const MUSIC := "res://animania_mod/source/music/loadingThemeLol.ogg"


func _init() -> void:
	var root := Node2D.new()
	root.name = "LoadingScreen"
	root.set_script(load(SCRIPT))

	# The order here IS the draw order: the mod adds them in this sequence and
	# never assigns a zIndex to any of them.
	var background := Sprite2D.new()
	background.name = "Background"
	background.centered = false
	background.texture = load("%s/funkin.png" % ART)
	root.add_child(background)

	var noodle := Sprite2D.new()
	noodle.name = "LongNoodle"
	noodle.centered = false
	noodle.texture = load("%s/longNoodle.png" % ART)
	root.add_child(noodle)

	var box := Sprite2D.new()
	box.name = "BoxOfNoodles"
	box.centered = false
	box.texture = load("%s/boxOfNoodles.png" % ART)
	root.add_child(box)

	var bf := AnimatedSprite2D.new()
	bf.name = "Bf"
	bf.centered = false
	bf.sprite_frames = load("%s/bf_frames.tres" % ART)
	root.add_child(bf)

	var press := AnimatedSprite2D.new()
	press.name = "PressEnter"
	press.centered = false
	press.sprite_frames = load("%s/pressEnter_frames.tres" % ART)
	root.add_child(press)

	var music := AudioStreamPlayer.new()
	music.name = "Music"
	music.stream = load(MUSIC) if ResourceLoader.exists(MUSIC) else null
	music.bus = &"Master"
	root.add_child(music)

	for child: Node in root.get_children():
		child.owner = root

	root.set(&"background", background)
	root.set(&"noodle", noodle)
	root.set(&"box", box)
	root.set(&"bf", bf)
	root.set(&"press_enter", press)
	root.set(&"music", music)

	var packed := PackedScene.new()
	packed.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err: int = ResourceSaver.save(packed, OUT)
	print("OUT %s %s" % ["saved" if err == OK else "FAILED", OUT])
	quit(0 if err == OK else 1)
