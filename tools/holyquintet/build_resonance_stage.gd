# Authors holyquintet_mod/stages/stg_resonance.tscn from the mod's own resonance.hx and
# resonance.xml. The XML only carries the two singer slots; every prop in the scene is the
# create() of scripts/data/stages/resonance.hx, in order:
#
#   simpleBG (low-memory fallback, kept as authored), background_bg, madokabg, mamibg,
#   speakersmain, kyubey-big-bald, middleground_fog, foreground_flowerL, foreground_flowerR
#
# Positions, scales and scrollFactors are the script's verbatim numbers in Funkin's
# 1280x720 world; the 1.5x for this project's 1920x1080 lives on the level camera.
# The beat bop (every 2 beats) is driven by stage_bop.gd through the level clock.
extends SceneTree

const OUT := "res://holyquintet_mod/stages/stg_resonance.tscn"
const IMAGES := "res://holyquintet_mod/source/images"

# (name, texture path, position, scale, scroll, alpha)
const STATIC_PROPS := [
	["SimpleBG", "stages/resonance/simpleBG", Vector2(-500, -1200), 1.5, Vector2(1, 1), 1.0],
	["Ground", "stages/resonance/background_bg", Vector2(0, -480), 2.25, Vector2(1, 1), 1.0],
	["Fog", "stages/resonance/middleground_fog", Vector2(-200, 100), 1.75, Vector2(1.1, 1.1), 0.5],
	["FlowerL", "stages/resonance/foreground_flowerL", Vector2(-900, -250), 1.25, Vector2(1.2, 1.2), 1.0],
	["FlowerR", "stages/resonance/foreground_flowerR", Vector2(1250, -100), 1.25, Vector2(1.2, 1.2), 1.0],
]

const ANIMATED_PROPS := [
	# (name, prop scene, position, scale, scroll)
	["Madoka", "res://holyquintet_mod/stages/props/madokabg.tscn", Vector2(790, -470), 0.9, Vector2(1, 1)],
	["Mami", "res://holyquintet_mod/stages/props/mamibg.tscn", Vector2(-780, -480), 0.8, Vector2(1, 1)],
]

func _init() -> void:
	var root := Node2D.new()
	root.name = "Resonance"
	root.set_meta(&"camera_zoom", 1.0)
	root.set_meta(&"camera_speed", 1.0)
	root.set_meta(&"start_cam_pos", Vector2(0, 0))

	# BG layer (scroll 1,1), drawn before the singers - insert(members.indexOf(bf)) order.
	for prop: Array in STATIC_PROPS:
		if prop[0] == "Fog" or prop[0] == "FlowerL" or prop[0] == "FlowerR":
			continue
		var sprite := _sprite(prop, 5)
		root.add_child(sprite)
		sprite.owner = root

	for prop: Array in ANIMATED_PROPS:
		var prop_node := _animated(prop, 10)
		root.add_child(prop_node)
		prop_node.owner = root
		root.set_editable_instance(prop_node, true)

	var speakers := _speakers(20)
	root.add_child(speakers)
	speakers.owner = root
	root.set_editable_instance(speakers, true)

	# kyubey-big-bald, add()'d after bf (in front of the background group).
	var kyubey: Node2D = load("res://holyquintet_mod/characters/chr_kyubey_big_bald.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	kyubey.name = "Kyubey"
	kyubey.position = Vector2(375, -780)
	kyubey.scale = Vector2(0.9, 0.9)
	root.add_child(kyubey)
	kyubey.owner = root
	root.set_editable_instance(kyubey, true)

	for prop: Array in STATIC_PROPS:
		if prop[0] != "Fog" and prop[0] != "FlowerL" and prop[0] != "FlowerR":
			continue
		var layer := Parallax2D.new()
		layer.name = "Scroll_%s" % prop[0]
		layer.scroll_scale = prop[4]
		root.add_child(layer)
		layer.owner = root
		var layer_sprite := _sprite(prop, 0)
		layer.add_child(layer_sprite)
		layer_sprite.owner = root

	_add_markers(root)
	_bop_script(root)

	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("could not pack (%d)" % err)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		push_error("could not save %s (%d)" % [OUT, err])
		quit(1)
		return
	print("OUT saved %s" % OUT)
	quit(0)


func _sprite(prop: Array, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = String(prop[0])
	sprite.texture = load("%s/%s.png" % [IMAGES, prop[1]])
	sprite.centered = false
	sprite.position = prop[2]
	sprite.scale = Vector2(prop[3], prop[3])
	sprite.modulate.a = prop[5]
	sprite.z_index = z
	return sprite


func _animated(prop: Array, z: int) -> Node2D:
	var node: Node2D = load(prop[1]).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	node.name = String(prop[0])
	node.position = prop[2]
	node.scale = Vector2(prop[3], prop[3])
	node.z_index = z
	return node


## speakersmain is a sparrow atlas from the game folder; its bop is built by
## tools/holyquintet/build_sparrow_prop.gd and instanced here.
func _speakers(z: int) -> Node2D:
	var node: Node2D = load("res://holyquintet_mod/stages/props/speakersmain.tscn").instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	node.name = "KyubeySpeaker"
	node.position = Vector2(300, -250)
	node.scale = Vector2(0.9, 0.9)
	node.z_index = z
	return node


func _add_markers(root: Node2D) -> void:
	# resonance.xml: boyfriend / dad slots. gf is not in the stage XML, so her slot is the
	# character default (gf-base.xml x=-850 y=400).
	var slots := {
		"PlayerPoint": {"pos": Vector2(1150, 225), "cam": Vector2(-280, -25)},
		"OpponentPoint": {"pos": Vector2(120, 200), "cam": Vector2(270, -25)},
		"GirlfriendPoint": {"pos": Vector2(-850, 400), "cam": Vector2(700, -700)},
	}
	for name: String in slots:
		var marker := Marker2D.new()
		marker.name = name
		marker.position = slots[name]["pos"]
		marker.set_meta(&"camera_offsets", slots[name]["cam"])
		root.add_child(marker)
		marker.owner = root


## Generic every-2-beats bop for the three animated props, driven by the level clock's
## step_change like the engine's own character dancing.
func _bop_script(root: Node2D) -> void:
	var script := load("res://tools/holyquintet/stage_bop.gd")
	var bop := Node.new()
	bop.name = "StageBop"
	bop.set_script(script)
	bop.set(&"targets", [
		{"node": ^"Madoka", "anim": &"bop"},
		{"node": ^"Mami", "anim": &"bop"},
		{"node": ^"KyubeySpeaker", "anim": &"bop"},
	])
	root.add_child(bop)
	bop.owner = root
