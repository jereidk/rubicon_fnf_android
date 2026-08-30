# Builds a playable level for any song, from the mod's own metadata.
#
#   godot --headless --path . --script tools/animania/build_song_scene.gd -- <song id>
#
# This is the generic path. build_level_scene.gd stays phone-call's alone and is not
# touched: that song has a baked camera timeline, an events script, subtitles, cinematic
# bars and a death sequence, all of them its own, and folding them into a general builder
# would put the one working song at risk to serve songs that do not exist yet.
#
# What this builds is a PLAIN level - stage, cast, charts, audio, HUD, health, touch
# controls and the pause menu - which is what every song needs before it needs anything
# else. A song that wants more gets it added here behind its own id, or gets its own
# builder the way phone-call has one.
#
# Everything comes from data:
#   * <song>-metadata.json  - the stage, the cast, the difficulties and the tempo map
#   * <difficulty>_{Player,Opponent}.tres - the converted charts
#   * Meta.tres             - the converter's own tempo resource
#   * stg_<stage>.tscn      - built by build_stage_from_json.gd, carrying the stage's
#                             character positions and cameraOffsets as meta
extends SceneTree

const CLOCK_SCRIPT := "res://addons/rubicon/scripts/scene/rubicon_level_clock.gd"
const SONG_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level_song.gd"
const HEALTH_SCRIPT := "res://addons/rubicon/scripts/scene/game/modules/rubicon_health_module.gd"
const LEVEL_SCRIPT := "res://addons/rubicon/scripts/scene/game/rubicon_level.gd"
const CONTROLLER_SCRIPT := \
	"res://addons/rubicon/scripts/scene/game/rubicon_level_note_controller.gd"
const HEALTH_BAR := "res://animania_mod/ui/health_bar.tscn"
const JUDGMENT := "res://addons/rubicon/resources/levels/ui/default/Judgment.tscn"
const NOTE_OVERRIDES := "res://animania_mod/songs/phone_call_note_overrides.tres"
## The amtake-base receptors, which is the note style every Animania song uses.
const LANE := "res://animania_mod/notestyle/Lane.tscn"
const INPUT_MAP := "res://addons/rubicon_mania/resources/default_input_map.tres"
const MOBILE_CONTROLS := "res://addons/rubicon_mobile_controls/mobile_controls.tscn"
const MOBILE_CONTROLS_OPACITY := 0.4
const PAUSE_MENU := "res://animania_mod/menus/pause/pause_menu.tscn"

const SOURCE := "res://animania_mod/source/songs"
const STAGES := "res://animania_mod/stages"
const CHARACTERS := "res://animania_mod/characters"

## Funkin is 1280x720 and this project is 1920x1080, and that 1.5x lives on the camera -
## the stage's coordinates and the character positions stay verbatim.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

var _root: Node2D
var _song_id: String


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: <song id> [difficulty]")
		quit(1)
		return
	_song_id = args[0]
	var difficulty: String = args[1] if args.size() > 1 else "normal"

	var meta_path: String = "%s/%s/%s-metadata.json" % [SOURCE, _song_id, _song_id]
	if not FileAccess.file_exists(ProjectSettings.globalize_path(meta_path)):
		push_error("no metadata at %s" % meta_path)
		quit(1)
		return
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var play: Dictionary = meta["playData"]
	var cast_names: Dictionary = play["characters"]

	_root = Node2D.new()
	_root.name = _song_id.to_pascal_case()
	_root.set_script(load(LEVEL_SCRIPT))
	_root.metadata = load("%s/%s/Meta.tres" % [SOURCE, _song_id])

	# The clock reads its time off this player's current_animation_position, so the "scene"
	# animation IS the song's timeline and its length is the instrumental's - not a rounded
	# guess.
	var instrumental: AudioStream = load("res://songs/%s/Inst.ogg" % _song_id)
	if instrumental == null:
		push_error("no Inst.ogg for %s" % _song_id)
		quit(1)
		return
	var clock: Node = _add(Node.new(), "RubiconLevelClock", CLOCK_SCRIPT)
	var clock_player := AnimationPlayer.new()
	clock_player.name = "AnimationPlayer"
	clock_player.callback_mode_discrete = \
		AnimationMixer.ANIMATION_CALLBACK_MODE_DISCRETE_FORCE_CONTINUOUS
	var library := AnimationLibrary.new()
	var scene_animation := Animation.new()
	scene_animation.length = instrumental.get_length()
	library.add_animation(&"scene", scene_animation)
	library.add_animation(&"RESET", Animation.new())
	clock_player.add_animation_library(&"", library)
	clock_player.autoplay = &"scene"
	clock.add_child(clock_player)
	clock_player.owner = _root

	var song: Node = _add(Node.new(), "RubiconLevelSongModule", SONG_SCRIPT)
	var players: Array[AudioStreamPlayer] = []
	# Inst first: the module syncs everything else to the first player.
	for track: Array in _tracks(cast_names):
		var file: String = "res://songs/%s/%s" % [_song_id, track[1]]
		if not ResourceLoader.exists(file):
			continue
		var player := AudioStreamPlayer.new()
		player.name = track[0]
		player.stream = load(file)
		player.bus = &"Music"
		song.add_child(player)
		player.owner = _root
		players.append(player)
	song.audio_players = players
	song.sync_reference_player = players[0]
	print("OUT pistas: %s" % [players.map(func(p: Node) -> String: return p.name)])

	var stage_scene: String = "%s/stg_%s.tscn" % [
		STAGES, String(play["stage"]).to_snake_case()]
	if not ResourceLoader.exists(stage_scene):
		push_error("no stage scene at %s - build it with build_stage_from_json.gd" % stage_scene)
		quit(1)
		return
	var stage: Node2D = load(stage_scene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	stage.name = "Stage"
	_root.add_child(stage)
	stage.owner = _root
	_root.set_editable_instance(stage, true)

	var ui: Dictionary = _build_ui(difficulty)
	var where: Dictionary = stage.get_meta(&"characters", {})
	_place_cast(stage, cast_names, where)
	_build_camera(where, cast_names, float(stage.get_meta(&"camera_zoom", 1.0)))

	var health: Node = _add(Node.new(), "RubiconHealthModule", HEALTH_SCRIPT)
	health.note_controller = ui["Player"]
	health.starting_health = 50.0
	ui["HealthBar"].health_module = health

	var controls: Node = load(MOBILE_CONTROLS).instantiate()
	controls.name = "MobileControls"
	controls.set(&"opacity", MOBILE_CONTROLS_OPACITY)
	_root.add_child(controls)
	controls.owner = _root

	var pause: Node = load(PAUSE_MENU).instantiate()
	pause.name = "PauseMenu"
	_root.add_child(pause)
	pause.owner = _root

	var out: String = "res://songs/%s/%s.tscn" % [_song_id, _song_id.to_snake_case()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var packed := PackedScene.new()
	packed.pack(_root)
	var err: int = ResourceSaver.save(packed, out)
	print("OUT %s %s" % ["saved" if err == OK else "FAILED", out])
	quit(0 if err == OK else 1)


## Which audio files a song has. The metadata names the vocal characters but the files are
## `Voices-<name>.ogg`, and a song with no split vocals just has `Voices.ogg`.
func _tracks(cast_names: Dictionary) -> Array:
	var tracks: Array = [["Instrumental", "Inst.ogg"]]
	for key: String in ["playerVocal", "opponentVocal", "player", "opponent"]:
		var who: String = String(cast_names.get(key, ""))
		if who.is_empty():
			continue
		var file: String = "Voices-%s.ogg" % who
		var already: bool = false
		for track: Array in tracks:
			already = already or track[1] == file
		if not already:
			tracks.append(["Voices%s" % who.to_pascal_case(), file])
	tracks.append(["Voices", "Voices.ogg"])
	return tracks


func _build_ui(difficulty: String) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	layer.layer = 2
	_root.add_child(layer)
	layer.owner = _root

	var ui := Control.new()
	ui.name = "UI"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	ui.owner = _root

	var built: Dictionary = {}

	var judgment: Control = load(JUDGMENT).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	judgment.name = "Judgment"
	ui.add_child(judgment)
	judgment.owner = _root

	var health_bar: Control = load(HEALTH_BAR).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	health_bar.name = "HealthBar"
	ui.add_child(health_bar)
	health_bar.owner = _root
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
		# The converter writes one pair per difficulty, which is why this takes one.
		controller.chart = load("%s/%s/%s-%s_%s.tres" % [
			SOURCE, _song_id, _song_id, difficulty, side])
		controller.note_overrides = load(NOTE_OVERRIDES)
		if side == "Player":
			controller.inputs = load(INPUT_MAP)
		else:
			controller.autoplay = true
		ui.add_child(controller)
		controller.owner = _root
		built[side] = controller

		# Four lanes, 160px apart, centred: -240, -80, 80, 240. Without these a controller
		# has a chart and nothing to draw it on - which is what the first build of tutorial
		# was, and it read as "the strumlines are off-frame" until it turned out they had
		# never been made.
		for lane_id: int in 4:
			var lane: Control = load(LANE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			lane.name = "Lane" if lane_id == 0 else "Lane%d" % [lane_id + 1]
			lane.offset_left = -240.0 + lane_id * 160.0
			lane.offset_right = lane.offset_left
			lane.lane_id = lane_id
			# An autoplayed lane's AnimationTree only ever observes NEUTRAL unless this is
			# on: hit_note() sets HIT and clears it in the same _process call, one frame
			# before the tree gets to see it, so the receptor's confirm flash never fires.
			if side == "Opponent":
				lane.lane_autoplay_hit_lingers = true
			controller.add_child(lane)
			lane.owner = _root

	judgment.level_note_controller = built["Player"]
	return built


## The cast, anchored the way Funkin does it: a stage position is where the character's
## FEET go, and the character scenes are already built with that origin (measured, see
## build_character_scenes.gd). So the position goes on verbatim.
func _place_cast(stage: Node2D, cast_names: Dictionary, where: Dictionary) -> void:
	for slot: String in ["opponent", "girlfriend", "player"]:
		var who: String = String(cast_names.get(slot, ""))
		if who.is_empty():
			continue
		var scene: String = "%s/chr_%s.tscn" % [CHARACTERS, who.replace("-", "_")]
		if not ResourceLoader.exists(scene):
			print("OUT %-11s %s SIN ESCENA - se salta" % [slot, who])
			continue
		var character: Node2D = load(scene).instantiate()
		character.name = who.to_pascal_case().replace("-", "")
		# The stage names its slots bf/dad/gf, not player/opponent/girlfriend.
		var key: String = {"player": "bf", "opponent": "dad", "girlfriend": "gf"}[slot]
		var at: Array = (where.get(key, {}) as Dictionary).get("position", [640, 500])
		character.position = Vector2(float(at[0]), float(at[1]))
		stage.add_child(character)
		character.owner = _root
		print("OUT %-11s %-20s en (%.0f, %.0f)" % [
			slot, who, character.position.x, character.position.y])


func _build_camera(where: Dictionary, cast_names: Dictionary, zoom: float) -> void:
	for slot: String in ["player", "opponent", "girlfriend"]:
		var key: String = {"player": "bf", "opponent": "dad", "girlfriend": "gf"}[slot]
		var entry: Dictionary = where.get(key, {})
		var at: Array = entry.get("position", [640, 500])
		var offsets: Array = entry.get("cameraOffsets", [0, 0])
		var marker := Marker2D.new()
		marker.name = "%sCameraPoint" % slot.to_pascal_case()
		# Stage_obj::applyCharacterData adds the STAGE's cameraOffsets on top of the
		# character JSON's own. Only the stage's are here; a character that carries its own
		# adds them when it is built.
		marker.position = Vector2(float(at[0]) + float(offsets[0]),
			float(at[1]) + float(offsets[1]))
		_add(marker, marker.name, "")

	var camera := Camera2D.new()
	camera.name = "RubiconInterpolatedCamera2D"
	camera.set_script(load(
		"res://addons/rubicon_interpolated_camera/scripts/rubicon_interpolated_camera_2d.gd"))
	# Between the two who sing, not on one of them. A song with no camera events sits in
	# the middle and stays there; phone-call moves because its chart tells it to, and that
	# is its builder's job and not this one's.
	var middle := Vector2.ZERO
	var counted: int = 0
	for slot: String in ["player", "opponent"]:
		var point: Node2D = _root.get_node_or_null("%sCameraPoint" % slot.to_pascal_case())
		if point != null:
			middle += point.position
			counted += 1
	var at: Vector2 = middle / float(counted) if counted > 0 else Vector2(640.0, 400.0)
	# The interpolated camera does not draw from `position`, it eases toward its targets -
	# setting only the position leaves it wherever the script starts and the shot comes out
	# framing a curtain. Both have to be set, and set to the same thing so it opens there
	# instead of sliding in from somewhere else.
	camera.position = at
	camera.zoom = Vector2.ONE * FUNKIN_TO_RUBICON * zoom
	_root.add_child(camera)
	camera.owner = _root
	camera.set(&"position_interpolate_target", at)
	camera.set(&"zoom_interpolate_target", camera.zoom)


func _add(node: Node, node_name: String, script_path: String) -> Node:
	node.name = node_name
	if not script_path.is_empty():
		node.set_script(load(script_path))
	_root.add_child(node)
	node.owner = _root
	return node
