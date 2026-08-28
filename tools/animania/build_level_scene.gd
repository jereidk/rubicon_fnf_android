# Authors songs/phone-call/phone_call.tscn: the stage, both characters, the three audio
# tracks, the two converted charts and the camera, wired together.
#
# Modelled on songs/test/test.tscn, which is the only worked example of a Rubicon level in
# this repo. Two things about that scene are worth knowing before reading this one:
#
#   * its Lane children have `Note N` children saved into them. Those are pooled notes the
#     handler spawns at runtime that got serialised by accident. Four Lane nodes per side
#     is the actual requirement; the notes are not authored here.
#   * the camera's aim is an ANIMATION TRACK on the level clock's player, keying
#     RubiconPositionSetter:current_point. That is the seam the chart's 20 FocusCamera
#     events belong in, and it is why this song's clock animation is generated rather
#     than left as the single RESET key test.tscn has.
#
#   godot --headless --path . --script tools/animania/build_level_scene.gd
extends SceneTree

const OUT := "res://songs/phone-call/phone_call.tscn"

# Every sub-scene is instanced with GEN_EDIT_STATE_INSTANCE, not the default. Without the
# edit state a packed node has no record of what it inherited, so pack() writes out every
# property AND every connection as if it were local: the health bar's own
# value_changed -> _on_value_changed ends up authored a second time in this scene and
# errors at load with "already connected", and the rest of the sub-scenes get a frozen copy
# of their properties that stops tracking the file they came from.
const SOURCE := "res://animania_mod/source/songs/phone-call"
const AUDIO := "res://animania_mod/source/songs/audio"

const STAGE := "res://animania_mod/stages/stg_phone_call_street.tscn"
const KOMI := "res://animania_mod/characters/chr_komi.tscn"
const TADANO := "res://animania_mod/characters/chr_tadano.tscn"

const LEVEL_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level.gd"
const CLOCK_SCRIPT := "res://addons/rubicon/scripts/scene/rubicon_level_clock.gd"
const SONG_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level_song.gd"
const CONTROLLER_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level_note_controller.gd"
const HEALTH_SCRIPT := "res://addons/rubicon/scripts/scene/game/modules/rubicon_health_module.gd"
const CAMERA_SCRIPT := "res://addons/rubicon_interpolated_camera/scripts/rubicon_interpolated_camera_2d.gd"
const SETTER_SCRIPT := "res://addons/rubicon_interpolated_camera/scripts/rubicon_position_setter.gd"
const BUMPER_SCRIPT := "res://addons/rubicon_interpolated_camera/scripts/rubicon_camera_bumper.gd"

const LANE := "res://resources/levels/ui/funkin/mania/Lane.tscn"
const JUDGMENT := "res://addons/rubicon/resources/levels/ui/default/Judgment.tscn"
const HEALTH_BAR := "res://resources/levels/ui/funkin/health_bar.tscn"
# Not resources/levels/ui/funkin/funkin_note_override.tres: this chart uses the note kind
# "noAnimation" on two notes, and a kind Rubicon has no database entry for throws on every
# frame the note is alive. See the header of the file itself.
const NOTE_OVERRIDES := "res://animania_mod/songs/phone_call_note_overrides.tres"
const INPUT_MAP := "res://addons/rubicon_mania/resources/default_input_map.tres"
const MOBILE_CONTROLS := "res://addons/rubicon_mobile_controls/mobile_controls.tscn"

# Funkin is 1280x720 and this project is 1920x1080, so the stage's own cameraZoom is
# multiplied by 1.5 to frame the same amount of world. See build_stage_scene.gd.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

# The two singers, with the numbers each one's JSON authors. `height` is what
# tools/animania/harness/measure_character.gd reports and is only used to find the
# midpoint Funkin's camera aims at.
const CAST := {
	"Tadano": {
		"scene": TADANO, "marker": "PlayerPoint", "offsets": Vector2(250, 180),
		"camera_offsets": Vector2(-250, 100), "height": 833.0, "side": "Player",
	},
	"Komi": {
		"scene": KOMI, "marker": "OpponentPoint", "offsets": Vector2(200, 50),
		"camera_offsets": Vector2(-225, 50), "height": 776.0, "side": "Opponent",
	},
	"KomiGirlfriend": {
		"scene": KOMI, "marker": "GirlfriendPoint", "offsets": Vector2(200, 50),
		"camera_offsets": Vector2(425, -150), "height": 776.0, "side": "",
	},
}

# metadata.json playData.characters: player tadano, opponent komi. The vocals are split
# per character, which is a V-Slice feature - RubiconLevelSong takes N players, so this is
# three AudioStreamPlayers rather than the two test.tscn has. Inst goes first because it
# is the sync reference.
const TRACKS := [
	{"node": "Instrumental", "file": "Inst.ogg"},
	{"node": "VocalsTadano", "file": "Voices-tadano.ogg"},
	{"node": "VocalsKomi", "file": "Voices-komi.ogg"},
]

var _root: Node2D


func _init() -> void:
	_root = Node2D.new()
	_root.name = "PhoneCall"
	_root.set_script(load(LEVEL_SCRIPT))
	_root.metadata = _metadata()

	# The clock reads its time straight off this player's current_animation_position, so
	# the "scene" animation IS the song's timeline: when it ends, the song ends. Its length
	# is the instrumental's, not a rounded-up guess.
	var instrumental: AudioStream = load("%s/%s" % [AUDIO, TRACKS[0]["file"]])
	var clock: Node = _add(_root, Node.new(), "RubiconLevelClock", CLOCK_SCRIPT)
	var clock_player := AnimationPlayer.new()
	clock_player.name = "AnimationPlayer"
	clock_player.callback_mode_discrete = AnimationMixer.ANIMATION_CALLBACK_MODE_DISCRETE_FORCE_CONTINUOUS
	clock_player.add_animation_library(&"", _clock_library(instrumental.get_length()))
	clock_player.autoplay = &"scene"
	clock.add_child(clock_player)

	var song: Node = _add(_root, Node.new(), "RubiconLevelSongModule", SONG_SCRIPT)
	var players: Array[AudioStreamPlayer] = []
	for track: Dictionary in TRACKS:
		var player := AudioStreamPlayer.new()
		player.name = track["node"]
		player.stream = load("%s/%s" % [AUDIO, track["file"]])
		player.bus = &"Music"
		song.add_child(player)
		players.append(player)
	song.audio_players = players
	song.sync_reference_player = players[0]

	var stage: Node2D = load(STAGE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	stage.name = "Stage"
	_root.add_child(stage)
	# The opponent goes inside one of the stage's own Parallax2D nodes, and PackedScene
	# drops a node whose parent lives inside an instanced sub-scene unless that instance is
	# marked editable - silently, with no error. Komi vanished from the first build of this
	# scene exactly that way.
	_root.set_editable_instance(stage, true)

	var ui: Dictionary = _build_ui()
	_place_cast(stage, ui)
	_build_camera()

	var health: Node = _add(_root, Node.new(), "RubiconHealthModule", HEALTH_SCRIPT)
	health.note_controller = ui["Player"]
	health.starting_health = 50.0
	ui["HealthBar"].health_module = health

	var controls: Node = load(MOBILE_CONTROLS).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	controls.name = "MobileControls"
	_root.add_child(controls)

	_own(_root, _root)

	var packed := PackedScene.new()
	var err: int = packed.pack(_root)
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


func _add(parent: Node, node: Node, node_name: String, script_path: String) -> Node:
	node.name = node_name
	node.set_script(load(script_path))
	parent.add_child(node)
	return node


# The converter wrote Meta.tres with the song's one time change (152 BPM, 4/4) and no
# title; the title is the only thing added here, so the file stays the converter's output.
func _metadata() -> Resource:
	var metadata: Resource = load("%s/Meta.tres" % SOURCE)
	if metadata.title.is_empty():
		metadata.title = "Phone Call"
		ResourceSaver.save(metadata, "%s/Meta.tres" % SOURCE)
	return metadata


# For now the camera simply alternates on the measure, the way test.tscn does. The chart's
# 103 camera events replace this track wholesale and are a separate pass.
func _clock_library(length: float) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var point_path := ^"../RubiconInterpolatedCamera2D/RubiconPositionSetter:current_point"

	var reset := Animation.new()
	reset.length = 0.001
	var reset_track: int = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(reset_track, point_path)
	reset.value_track_set_update_mode(reset_track, Animation.UPDATE_DISCRETE)
	reset.track_insert_key(reset_track, 0.0, &"Opponent")
	library.add_animation(&"RESET", reset)

	var scene := Animation.new()
	scene.step = 0.1
	var track: int = scene.add_track(Animation.TYPE_VALUE)
	scene.track_set_path(track, point_path)
	scene.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	scene.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)

	# 152 BPM, 4/4: a measure is 4 * 60 / 152 seconds. The chart runs to 132.2s.
	var measure: float = 4.0 * 60.0 / 152.0
	var index: int = 0
	while measure * index < length:
		scene.track_insert_key(track, measure * index,
			&"Player" if index % 2 == 1 else &"Opponent")
		index += 1
	scene.length = length
	library.add_animation(&"scene", scene)

	return library


func _build_ui() -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	_root.add_child(layer)

	var ui := Control.new()
	ui.name = "UI"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)

	var built: Dictionary = {}

	var judgment: Control = load(JUDGMENT).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	judgment.name = "Judgment"
	_add_control(ui, judgment)

	var health_bar: Control = load(HEALTH_BAR).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	health_bar.name = "HealthBar"
	_add_control(ui, health_bar)
	built["HealthBar"] = health_bar

	for side: String in ["Opponent", "Player"]:
		var controller := Control.new()
		controller.name = side
		controller.set_script(load(CONTROLLER_SCRIPT))
		# Opponent at a quarter across, player at three quarters, 160px off the bottom.
		controller.anchor_left = 0.25 if side == "Opponent" else 0.75
		controller.anchor_right = controller.anchor_left
		controller.anchor_top = 1.0
		controller.anchor_bottom = 1.0
		controller.offset_top = -160.0
		controller.offset_bottom = -160.0
		controller.grow_horizontal = Control.GROW_DIRECTION_BOTH
		controller.grow_vertical = Control.GROW_DIRECTION_BEGIN
		controller.chart = load("%s/phone-call_%s.tres" % [SOURCE, side])
		controller.note_overrides = load(NOTE_OVERRIDES)
		if side == "Player":
			controller.inputs = load(INPUT_MAP)
		else:
			controller.autoplay = true
		ui.add_child(controller)
		built[side] = controller

		# Four lanes, 160px apart, centred: -240, -80, 80, 240.
		for lane_id: int in 4:
			var lane: Control = load(LANE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			lane.name = "Lane" if lane_id == 0 else "Lane%d" % [lane_id + 1]
			lane.offset_left = -240.0 + lane_id * 160.0
			lane.offset_right = lane.offset_left
			lane.lane_id = lane_id
			_add_control(controller, lane)

	judgment.level_note_controller = built["Player"]
	return built


## An instanced Control loses its authored anchors unless layout_mode says to keep them.
## Godot recomputes a Control's layout when it is reparented, and with layout_mode unset it
## resets the anchors to zero - the health bar came out 4x27 pixels in the top-left corner
## of the first build of this scene, instead of the bar across the top it is authored as.
## test.tscn carries the same `layout_mode = 1` on every instanced Control for this reason.
func _add_control(parent: Control, control: Control) -> void:
	parent.add_child(control)
	control.set(&"layout_mode", 1)


func _place_cast(stage: Node2D, ui: Dictionary) -> void:
	for character_name: String in CAST:
		var entry: Dictionary = CAST[character_name]
		var marker: Marker2D = stage.find_child(entry["marker"], true, false)
		if marker == null:
			push_error("no %s in the stage" % entry["marker"])
			quit(1)
			return

		var character: Node2D = load(entry["scene"]).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		character.name = character_name
		# The character scenes are anchored by their feet, which is Funkin's
		# characterOrigin, so this is Stage.addCharacter's formula with nothing left over.
		character.position = marker.position + (entry["offsets"] as Vector2)
		character.z_index = marker.z_index
		marker.get_parent().add_child(character)

		var side: String = entry["side"]
		if not side.is_empty():
			character.level_note_controller = ui[side]

			# The camera aims at the character's midpoint plus its cameraOffsets. These
			# markers have to be DIRECT children of the level root: the position setter
			# reads only `target.position` (its _get_node_2d_position always returns zero,
			# because `node is Parallax2D or ParallaxBackground or ParallaxLayer` parses as
			# `(node is Parallax2D) or ParallaxBackground or ...`, and a class used as an
			# expression is truthy). Parent one anywhere else and the parent's offset is
			# dropped in silence.
			var point := Marker2D.new()
			point.name = "%sCameraPoint" % side
			point.position = (character.position
				- Vector2(0.0, float(entry["height"]) * 0.5)
				+ (entry["camera_offsets"] as Vector2))
			_root.add_child(point)


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "RubiconInterpolatedCamera2D"
	camera.set_script(load(CAMERA_SCRIPT))

	var stage: Node2D = _root.get_node("Stage")
	var zoom: float = float(stage.get_meta(&"camera_zoom")) * FUNKIN_TO_RUBICON
	camera.zoom = Vector2.ONE * zoom
	camera.zoom_interpolate_target = Vector2.ONE * zoom
	# phoneCallStreet.json's cameraSpeed.
	camera.position_interpolate_speed = float(stage.get_meta(&"camera_speed"))

	var opponent_point: Marker2D = _root.get_node("OpponentCameraPoint")
	camera.position = opponent_point.position
	camera.position_interpolate_target = opponent_point.position
	_root.add_child(camera)

	var setter: Node = _add(camera, Node.new(), "RubiconPositionSetter", SETTER_SCRIPT)
	var point_map: Dictionary[StringName, Node] = {
		&"Opponent": opponent_point,
		&"Player": _root.get_node("PlayerCameraPoint"),
	}
	setter.point_map = point_map
	setter.set(&"current_point", &"Opponent")

	_add(camera, Node.new(), "RubiconCameraBumper", BUMPER_SCRIPT)


func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		if child != owner and child.owner == null:
			child.owner = owner
		_own(child, owner)
