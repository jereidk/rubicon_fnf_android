# Renders the ported stage with both characters on it, so the port gets looked at rather
# than reasoned about. Everything here is 2D, so unlike the 3D work on the Lullaby branch
# there is no lightmap or Vulkan-only path to invalidate what the software GL draws.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/stage_shot.tscn
extends Node2D

const STAGE := "res://animania_mod/stages/stg_phone_call_street.tscn"

# Funkin is 1280x720 and this project is 1920x1080, so the stage's own cameraZoom is
# multiplied by 1.5 to frame the same amount of world. See build_stage_scene.gd.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

# Each character scene's origin is already Funkin's characterOrigin (bottom centre), so
# placing one is the stage marker plus the character JSON's own `offsets`. The heights
# are what measure_character.gd reports, used only to aim the camera at a midpoint.
const CAST := {
	"tadano": {
		"scene": "res://animania_mod/characters/chr_tadano.tscn",
		"marker": "PlayerPoint", "offsets": Vector2(250, 180),
		"camera_offsets": Vector2(-250, 100), "height": 833.0,
	},
	"komi_opponent": {
		"scene": "res://animania_mod/characters/chr_komi.tscn",
		"marker": "OpponentPoint", "offsets": Vector2(200, 50),
		"camera_offsets": Vector2(-225, 50), "height": 776.0,
	},
	"komi_gf": {
		"scene": "res://animania_mod/characters/chr_komi.tscn",
		"marker": "GirlfriendPoint", "offsets": Vector2(200, 50),
		"camera_offsets": Vector2(425, -150), "height": 776.0,
	},
}

var _frames: int = 0
var _shots: Array = []


func _ready() -> void:
	var stage: Node2D = load(STAGE).instantiate()
	add_child(stage)

	var focus: Dictionary = {}
	for character_name: String in CAST:
		focus[character_name] = _place(stage, character_name, CAST[character_name])

	var camera := Camera2D.new()
	add_child(camera)
	camera.make_current()

	var song_zoom: float = float(stage.get_meta(&"camera_zoom")) * FUNKIN_TO_RUBICON
	var both: Vector2 = (focus["tadano"] + focus["komi_opponent"]) * 0.5
	_shots = [
		{"name": "wide", "zoom": 0.35, "pos": both},
		{"name": "song", "zoom": song_zoom, "pos": both},
		{"name": "player", "zoom": song_zoom, "pos": focus["tadano"]},
		{"name": "opponent", "zoom": song_zoom, "pos": focus["komi_opponent"]},
	]


## Returns the point Funkin's camera would follow: the character's midpoint plus its
## cameraOffsets.
func _place(stage: Node2D, node_name: String, entry: Dictionary) -> Vector2:
	var marker: Marker2D = stage.find_child(entry["marker"], true, false)
	var character: Node2D = load(entry["scene"]).instantiate()
	character.name = node_name
	character.position = marker.position + (entry["offsets"] as Vector2)
	character.z_index = marker.z_index
	marker.get_parent().add_child(character)

	var midpoint: Vector2 = character.position - Vector2(0.0, float(entry["height"]) * 0.5)
	print("OUT placed %-14s at %s z=%-4d under %s" % [
		node_name, character.position, character.z_index, marker.get_parent().name])
	return midpoint + (entry["camera_offsets"] as Vector2)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return

	var index: int = (_frames - 4) / 3
	if index >= _shots.size():
		get_tree().quit()
		return

	var shot: Dictionary = _shots[index]
	var step: int = (_frames - 4) % 3
	if step == 0:
		var camera: Camera2D = get_viewport().get_camera_2d()
		camera.zoom = Vector2.ONE * float(shot["zoom"])
		camera.position = shot["pos"]
	elif step == 2:
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "user://stage_%s.png" % shot["name"]
		image.save_png(path)
		print("OUT shot %-9s zoom=%.3f at %s -> %s" % [
			shot["name"], float(shot["zoom"]), shot["pos"],
			ProjectSettings.globalize_path(path)])
