# Authors songs/resonance/resonance.tscn, the first playable Holy Quintet song: stage,
# characters (sayaka-base, gf-base, stock bf), the three audio tracks, the converted
# charts, camera, and the default Rubicon HUD.
#
# Modelled on tools/animania/build_level_scene.gd with the Animania-only pieces left out
# (custom notestyle, death sequence, pause menu, baked camera events). The resonance chart
# has no custom note kinds, so the stock Lane/Note/Judgment work as-is.
extends SceneTree

const OUT := "res://songs/resonance/resonance.tscn"
const SOURCE := "res://holyquintet_mod/source/songs/resonance"
const CHARTS := "res://songs/resonance/data"
const DIFFICULTY := "hard"

const LEVEL_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level.gd"
const CLOCK_SCRIPT := "res://addons/rubicon/scripts/scene/rubicon_level_clock.gd"
const SONG_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level_song.gd"
const CONTROLLER_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level_note_controller.gd"
const HEALTH_SCRIPT := "res://addons/rubicon/scripts/scene/game/modules/rubicon_health_module.gd"
const CAMERA_SCRIPT := "res://addons/rubicon_interpolated_camera/scripts/rubicon_interpolated_camera_2d.gd"
const SETTER_SCRIPT := "res://addons/rubicon_interpolated_camera/scripts/rubicon_position_setter.gd"
const BUMPER_SCRIPT := "res://addons/rubicon_interpolated_camera/scripts/rubicon_camera_bumper.gd"

const STAGE := "res://holyquintet_mod/stages/stg_resonance.tscn"
const SAYAKA := "res://holyquintet_mod/characters/chr_sayaka_base.tscn"
const GF := "res://holyquintet_mod/characters/chr_gf_base.tscn"
const BF := "res://resources/levels/characters/bf.tscn"

const LANE := "res://resources/levels/ui/funkin/mania/Lane.tscn"
const NOTE := "res://resources/levels/ui/funkin/mania/Note.tscn"
const NOTE_OVERRIDES := "res://resources/levels/ui/funkin/funkin_note_override.tres"
const JUDGMENT := "res://addons/rubicon/resources/levels/ui/default/Judgment.tscn"
const HEALTH_BAR := "res://resources/levels/ui/funkin/health_bar.tscn"
const INPUT_MAP := "res://addons/rubicon_mania/resources/default_input_map.tres"
const MOBILE_CONTROLS := "res://addons/rubicon_mobile_controls/mobile_controls.tscn"

const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

# Character FRAME heights, used only to find the midpoint the camera aims at. These are
# MEASURED with tools/animania/harness/measure_character.gd - placeholders until then.
const CAST := {
	"Boyfriend": {"scene": BF, "marker": "PlayerPoint", "offsets": Vector2(0, 0),
		"camera_offsets": Vector2(0, 0), "height": 375.0, "side": "Player"},
	"Sayaka": {"scene": SAYAKA, "marker": "OpponentPoint", "offsets": Vector2(0, 0),
		"camera_offsets": Vector2(0, 0), "height": 900.0, "side": "Opponent"},
	"Girlfriend": {"scene": GF, "marker": "GirlfriendPoint", "offsets": Vector2(0, 0),
		"camera_offsets": Vector2(0, 0), "height": 800.0, "side": ""},
}

const TRACKS := [
	{"node": "Instrumental", "file": "Inst.ogg"},
	{"node": "VocalsOpponent", "file": "Voices-Opponent.ogg"},
	{"node": "VocalsPlayer", "file": "Voices-Player.ogg"},
]

var _root: Node2D
var _clock_player: AnimationPlayer


func _init() -> void:
	_root = Node2D.new()
	_root.name = "Resonance"
	_root.set_script(load(LEVEL_SCRIPT))
	_root.metadata = _metadata()

	var instrumental: AudioStream = load("%s/song/Inst.ogg" % SOURCE)
	var clock: Node = _add(_root, Node.new(), "RubiconLevelClock", CLOCK_SCRIPT)
	var clock_player := AnimationPlayer.new()
	clock_player.name = "AnimationPlayer"
	clock_player.callback_mode_discrete = \
		AnimationMixer.ANIMATION_CALLBACK_MODE_DISCRETE_FORCE_CONTINUOUS
	clock_player.add_animation_library(&"", _clock_library(instrumental.get_length()))
	_clock_player = clock_player
	clock_player.autoplay = &"scene"
	clock.add_child(clock_player)

	var song: Node = _add(_root, Node.new(), "RubiconLevelSongModule", SONG_SCRIPT)
	var players: Array[AudioStreamPlayer] = []
	for track: Dictionary in TRACKS:
		var player := AudioStreamPlayer.new()
		player.name = track["node"]
		player.stream = load("%s/song/%s" % [SOURCE, track["file"]])
		player.bus = &"Music"
		song.add_child(player)
		players.append(player)
	song.audio_players = players
	song.sync_reference_player = players[0]

	var stage: Node2D = load(STAGE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	stage.name = "Stage"
	_root.add_child(stage)
	_root.set_editable_instance(stage, true)

	var ui: Dictionary = _build_ui()
	_place_cast(stage, ui)
	_build_camera()

	var health: Node = _add(_root, Node.new(), "RubiconHealthModule", HEALTH_SCRIPT)
	health.note_controller = ui["Player"]
	health.starting_health = 50.0
	ui["HealthBar"].health_module = health
	_dress_icons(ui)

	var controls: Node = load(MOBILE_CONTROLS).instantiate()
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
	print("OUT saved %s (inst=%.1fs)" % [OUT, instrumental.get_length()])
	quit(0)


func _add(parent: Node, node: Node, node_name: String, script_path: String) -> Node:
	node.name = node_name
	node.set_script(load(script_path))
	parent.add_child(node)
	return node


## The converter's Meta.tres has the time changes and no title; add the title only.
func _metadata() -> Resource:
	var metadata: Resource = load("%s/Meta.tres" % CHARTS)
	if metadata.title.is_empty():
		metadata.title = "Resonance"
		ResourceSaver.save(metadata, "%s/Meta.tres" % CHARTS)
	return metadata


func _clock_library(length: float) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.001
	var track: int = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(track, ^"../RubiconInterpolatedCamera2D/RubiconPositionSetter:current_point")
	reset.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	reset.track_insert_key(track, 0.0, &"Opponent")
	library.add_animation(&"RESET", reset)

	# The resonance chart's Camera Movement events are baked here: focus switches between
	# the two singers at their authored times. Zoom/position events are a later pass.
	var scene := Animation.new()
	scene.length = length
	var focus_track := scene.add_track(Animation.TYPE_VALUE)
	scene.track_set_path(focus_track,
		^"../RubiconInterpolatedCamera2D/RubiconPositionSetter:current_point")
	scene.value_track_set_update_mode(focus_track, Animation.UPDATE_DISCRETE)
	scene.track_set_interpolation_type(focus_track, Animation.INTERPOLATION_NEAREST)
	var events_parse: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/events.json" % SOURCE))
	if events_parse is Dictionary:
		scene.track_insert_key(focus_track, 0.0, &"Opponent")
		for event: Dictionary in (events_parse as Dictionary).get("events", []):
			if event.get("name") != "Camera Movement":
				continue
			var target: StringName = &"Player" if event["params"][0] == 0 else &"Opponent"
			scene.track_insert_key(focus_track, float(event["time"]) / 1000.0, target)
	library.add_animation(&"scene", scene)
	return library


func _build_ui() -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	layer.layer = 2
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
	_root.set_editable_instance(health_bar, true)
	built["HealthBar"] = health_bar

	for side: String in ["Opponent", "Player"]:
		var controller := Control.new()
		controller.name = side
		controller.set_script(load(CONTROLLER_SCRIPT))
		controller.anchor_left = 0.25 if side == "Opponent" else 0.75
		controller.anchor_right = controller.anchor_left
		controller.anchor_top = 1.0
		controller.anchor_bottom = 1.0
		controller.offset_top = -160.0
		controller.offset_bottom = -160.0
		controller.grow_horizontal = Control.GROW_DIRECTION_BOTH
		controller.grow_vertical = Control.GROW_DIRECTION_BEGIN
		controller.chart = load("%s/%s-%s_%s.tres" % [CHARTS, "resonance", DIFFICULTY, side])
		controller.note_overrides = load(NOTE_OVERRIDES)
		if side == "Player":
			controller.inputs = load(INPUT_MAP)
		else:
			controller.autoplay = true
		ui.add_child(controller)
		built[side] = controller

		for lane_id: int in 4:
			var lane: Control = load(LANE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			lane.name = "Lane" if lane_id == 0 else "Lane%d" % [lane_id + 1]
			lane.offset_left = -240.0 + lane_id * 160.0
			lane.offset_right = lane.offset_left
			lane.lane_id = lane_id
			if side == "Opponent":
				lane.lane_autoplay_hit_lingers = true
			_add_control(controller, lane)

	judgment.level_note_controller = built["Player"]
	return built


func _add_control(parent: Control, control: Control) -> void:
	parent.add_child(control)
	control.set(&"layout_mode", 1)
	control.set(&"anchors_preset", -1)


## The default bar ships bf's icon twice; swap in sayaka (opponent) and bf (player).
func _dress_icons(ui: Dictionary) -> void:
	var bar: Control = ui["HealthBar"]
	var icons: Dictionary = {
		"IconL": "res://holyquintet_mod/ui/sayaka_icon.tres",
		"IconR": "res://holyquintet_mod/ui/bf_icon.tres",
	}
	for icon_name: String in icons:
		var icon: AnimatedSprite2D = bar.find_child(icon_name, true, false)
		if icon == null:
			push_error("la barra de vida no tiene %s" % icon_name)
			quit(1)
			return
		icon.sprite_frames = load(icons[icon_name])
		icon.animation = &"neutral"


func _place_cast(stage: Node2D, ui: Dictionary) -> void:
	for character_name: String in CAST:
		var entry: Dictionary = CAST[character_name]
		var marker: Marker2D = stage.find_child(entry["marker"], true, false)
		if marker == null:
			push_error("no %s in the stage" % entry["marker"])
			quit(1)
			return
		var character: Node2D = load(entry["scene"]).instantiate(
			PackedScene.GEN_EDIT_STATE_INSTANCE)
		character.name = character_name
		character.position = marker.position + (entry["offsets"] as Vector2)
		character.z_index = marker.z_index
		marker.get_parent().add_child(character)

		var side: String = entry["side"]
		if not side.is_empty():
			character.level_note_controller = ui[side]

		var stage_offsets: Vector2 = marker.get_meta(&"camera_offsets", Vector2.ZERO)
		var point := Marker2D.new()
		point.name = "%sCameraPoint" % (side if not side.is_empty() else "Girlfriend")
		point.position = (character.position
			- Vector2(0.0, float(entry["height"]) * 0.5)
			+ (entry["camera_offsets"] as Vector2)
			+ stage_offsets)
		_root.add_child(point)


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "RubiconInterpolatedCamera2D"
	camera.set_script(load(CAMERA_SCRIPT))
	var stage: Node2D = _root.get_node("Stage")
	var zoom: float = float(stage.get_meta(&"camera_zoom")) * FUNKIN_TO_RUBICON
	camera.zoom = Vector2.ONE * zoom
	camera.zoom_interpolate_target = Vector2.ONE * zoom
	camera.position_interpolate_speed = float(stage.get_meta(&"camera_speed", 1.0))
	var opponent_point: Marker2D = _root.get_node("OpponentCameraPoint")
	camera.position = opponent_point.position
	camera.position_interpolate_target = opponent_point.position
	_root.add_child(camera)

	var setter: Node = _add(camera, Node.new(), "RubiconPositionSetter", SETTER_SCRIPT)
	var point_map: Dictionary[StringName, Node] = {
		&"Opponent": _root.get_node("OpponentCameraPoint"),
		&"Player": _root.get_node("PlayerCameraPoint"),
		&"Girlfriend": _root.get_node("GirlfriendCameraPoint"),
	}
	setter.set(&"point_map", point_map)
	setter.set(&"current_point", &"Opponent")

	var bumper: Node = _add(camera, Node.new(), "RubiconCameraBumper", BUMPER_SCRIPT)
	bumper.bump_every = 1
	bumper.bump_interval = 4
	bumper.bump_amount = 0.0


func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		if child != owner and child.owner == null:
			child.owner = owner
		_own(child, owner)
