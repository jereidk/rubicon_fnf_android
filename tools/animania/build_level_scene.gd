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

# The amtake-base receptors, not the stock funkin ones. See tools/animania/build_notestyle.gd.
const LANE := "res://animania_mod/notestyle/Lane.tscn"
const JUDGMENT := "res://addons/rubicon/resources/levels/ui/default/Judgment.tscn"
const HEALTH_BAR := "res://resources/levels/ui/funkin/health_bar.tscn"
# Not resources/levels/ui/funkin/funkin_note_override.tres: this chart uses the note kind
# "noAnimation" on two notes, and a kind Rubicon has no database entry for throws on every
# frame the note is alive. See the header of the file itself.
const NOTE_OVERRIDES := "res://animania_mod/songs/phone_call_note_overrides.tres"
const INPUT_MAP := "res://addons/rubicon_mania/resources/default_input_map.tres"
const MOBILE_CONTROLS := "res://addons/rubicon_mobile_controls/mobile_controls.tscn"
const EVENTS_SCRIPT := "res://animania_mod/scripts/phone_call_events.gd"
const ICON_SCRIPT := "res://animania_mod/scripts/animated_health_icon.gd"
## bf_icon.tres's frame height, which is what health_bar.tscn's icon placement assumes.
const BF_ICON_HEIGHT := 150.0
const CHART_JSON := "res://animania_mod/source/songs/phone-call/phone-call-chart.json"

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

# phone-call.script's standUP() destroys the phone characters and fetches these two from the
# registry; here they are in the scene from the start and hidden, because instantiating two
# multisparrow characters mid-song on a phone is a stall for nothing. setPosition() places
# an FlxSprite by its CORNER, so the script's (-175, 325) and (300, 325) become these once
# the scenes' own bottom-centre anchor is taken off.
const STAND_CAST := {
	"TadanoStand": {
		"scene": "res://animania_mod/characters/chr_tadano_stand.tscn",
		"corner": Vector2(-175, 325), "frame": Vector2(290, 667), "slot": "boyfriend",
	},
	"KomiStand": {
		"scene": "res://animania_mod/characters/chr_komi_stand.tscn",
		"corner": Vector2(300, 325), "frame": Vector2(269, 670), "slot": "dad",
	},
}
## standUP(): boyfriend.zIndex = oldZIndex + 500, and the phone pair sit at 210.
const STAND_Z := 710
## phone-call.script calls standUP() on beat 232.
const STAND_UP_BEAT := 232.0

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
var _clock_player: AnimationPlayer


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
	_clock_player = clock_player
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
	_place_stand_cast(stage)
	_build_camera()

	_build_bars()

	var health: Node = _add(_root, Node.new(), "RubiconHealthModule", HEALTH_SCRIPT)
	health.note_controller = ui["Player"]
	health.starting_health = 50.0
	ui["HealthBar"].health_module = health
	_dress_icons(ui, health)

	var controls: Node = load(MOBILE_CONTROLS).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	controls.name = "MobileControls"
	_root.add_child(controls)

	_bake_camera_events(instrumental.get_length())

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


## Only RESET at this point: the "scene" animation needs the camera focus points, which do
## not exist until the characters are placed, so it is built in _bake_camera_events().
func _clock_library(length: float) -> AnimationLibrary:
	var library := AnimationLibrary.new()

	var reset := Animation.new()
	reset.length = 0.001
	var reset_track: int = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(reset_track, ^"../CinematicBars/Top:size")
	reset.value_track_set_update_mode(reset_track, Animation.UPDATE_DISCRETE)
	reset.track_insert_key(reset_track, 0.0, Vector2(1920.0, 0.0))
	library.add_animation(&"RESET", reset)

	var placeholder := Animation.new()
	placeholder.length = length
	library.add_animation(&"scene", placeholder)

	return library


## Replaces the placeholder "scene" animation with the chart's 97 camera events.
func _bake_camera_events(length: float) -> void:
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART_JSON))
	var stage: Node2D = _root.get_node("Stage")
	var base_zoom: float = float(stage.get_meta(&"camera_zoom")) * FUNKIN_TO_RUBICON

	# Funkin's `char` index: 0 boyfriend, 1 dad, 2 girlfriend.
	var focus_points: Dictionary = {
		0: _root.get_node("PlayerCameraPoint").position,
		1: _root.get_node("OpponentCameraPoint").position,
		2: _root.get_node("GirlfriendCameraPoint").position,
	}

	# After standUP() the same FocusCamera `char` means the standing pair, somewhere else.
	# Their cameraOffsets are komi-stand [50, 50] and tadano-stand [200, 50].
	var stand_points: Dictionary = {}
	for character_name: String in STAND_CAST:
		var entry: Dictionary = STAND_CAST[character_name]
		var character: Node2D = _root.find_child(character_name, true, false)
		var offsets := Vector2(200.0, 50.0) if entry["slot"] == "boyfriend" \
			else Vector2(50.0, 50.0)
		stand_points[0 if entry["slot"] == "boyfriend" else 1] = (character.position
			- Vector2(0.0, (entry["frame"] as Vector2).y * 0.5)
			+ offsets * FUNKIN_TO_RUBICON)

	var baker: RefCounted = load("res://tools/animania/camera_events.gd").new(
		focus_points, base_zoom, stand_points, STAND_UP_BEAT * 60.0 / 152.0)
	var scene: Animation = baker.build(chart["events"], length)

	var library: AnimationLibrary = _clock_player.get_animation_library(&"")
	library.remove_animation(&"scene")
	library.add_animation(&"scene", scene)
	print("OUT %d pistas, %.1fs" % [scene.get_track_count(), scene.length])


func _build_ui() -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	# Above CinematicBars (1) and below MobileControls (15).
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
	# The two icons live INSIDE this instance, and _dress_icons rewrites them. Overrides on
	# an instance's children are only stored when the instance is editable - the same rule
	# that dropped komi out of the stage - so without this the bar keeps shipping bf's face.
	_root.set_editable_instance(health_bar, true)
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


## The health bar ships with bf's two-frame icon and no code that ever changes it. These
## are Animania's: state machines with transition animations, and komi's sings along with
## her. IconL is the opponent's and IconR the player's, which is the order the bar's own
## fill runs in.
func _dress_icons(ui: Dictionary, health: Node) -> void:
	var bar: Control = ui["HealthBar"]
	var icons: Dictionary = {
		"IconL": {
			"frames": "res://animania_mod/characters/komi_icon.tres",
			# phone-call.script's onStartSong: playerId 0 (Dad) gets updateHealthIcon(health)
			# and playerId 1 (Boyfriend) gets updateHealthIcon(2 - health). So it is the
			# PLAYER's icon that reads the inverse in this song, not the opponent's - the
			# reverse of stock Funkin, and of the first version of this port. The song also
			# sets healthBar.flipped, which is the other half of the same mirroring.
			"controller": ui["Opponent"], "inverted": false, "alt": true,
			# komi.hx sets icon.flipX, and the atlas's poses are authored for it - which is
			# why its "right" art is this port's sing_left.
			"flip": true,
		},
		"IconR": {
			"frames": "res://animania_mod/characters/tadano_icon.tres",
			"controller": ui["Player"], "inverted": true, "alt": false, "flip": false,
		},
	}

	for icon_name: String in icons:
		var entry: Dictionary = icons[icon_name]
		var icon: AnimatedSprite2D = bar.find_child(icon_name, true, false)
		if icon == null:
			push_error("la barra de vida no tiene %s" % icon_name)
			quit(1)
			return

		icon.set_script(load(ICON_SCRIPT))
		icon.sprite_frames = load(entry["frames"])
		icon.animation = &"idle"
		icon.health_module = health
		icon.note_controller = entry["controller"]
		icon.inverted = entry["inverted"]
		icon.has_alt_poses = entry["alt"]
		# Fitted to the height the bar was laid out for rather than left at native size.
		# Rubicon centres its icons on the bar, so bf's 150px icon already runs 19px off the
		# top of the screen; tadano's is 171 and would run 30px off. Matching bf's height
		# keeps Animania's icons in exactly the space Rubicon's layout expects instead of
		# moving the layout to suit them - and both character JSONs carry
		# healthIcon.scale 0.9, so the mod scales them down too.
		var frame: Texture2D = icon.sprite_frames.get_frame_texture(&"idle", 0)
		var fit: float = BF_ICON_HEIGHT / float(frame.get_height())
		icon.scale = Vector2(-fit if entry["flip"] else fit, fit)

		# offset is in the sprite's own space, and the bar authors -73 for bf's 138px icon:
		# half its width. Keeping -73 for a 167px icon slides it out of place and overlaps
		# it with the other one in the middle of the bar.
		icon.offset = Vector2(-frame.get_width() * 0.5, icon.offset.y)


## An instanced Control loses its authored anchors unless layout_mode says to keep them.
## Godot recomputes a Control's layout when it is reparented, and with layout_mode unset it
## resets the anchors to zero - the health bar came out 4x27 pixels in the top-left corner
## of the first build of this scene, instead of the bar across the top it is authored as.
## test.tscn carries the same `layout_mode = 1` on every instanced Control for this reason.
func _add_control(parent: Control, control: Control) -> void:
	parent.add_child(control)
	control.set(&"layout_mode", 1)


## standUP()'s camGame.flash(WHITE, 1.5) and beat 348's camGame.fade(BLACK, 3). Both are on
## the GAME camera in Funkin, so they go above the stage and below the HUD - the same place
## the letterbox sits. That is right for the fade too: by the time it runs, beat 332 has
## already tweened the HUD away.
func _build_overlays() -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "Overlays"
	layer.layer = 1
	_root.add_child(layer)

	var built: Dictionary = {}
	for entry: Array in [["White", Color(1, 1, 1, 0), "flash"],
			["Black", Color(0, 0, 0, 0), "fade"]]:
		var rect := ColorRect.new()
		rect.name = entry[0]
		rect.color = entry[1]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.size = Vector2(1920.0, 1080.0)
		layer.add_child(rect)
		rect.set(&"layout_mode", 0)
		built[entry[2]] = rect
	return built


## Letterbox bars for the chart's seven CinematicBars events.
##
## They sit ABOVE the stage and BELOW the HUD, which is a deliberate departure from where
## Funkin puts them. Funkin's receptors are at the top of the screen and its bars can cover
## the bottom freely; Rubicon's are anchored to the BOTTOM (anchor_top 1.0, offset -160,
## the same as test.tscn), and the chart asks for 120px bars at 90.8s while notes are still
## arriving. Drawn over the HUD that is a bar across the strumline you are being asked to
## hit. So the letterbox frames the scene and leaves the notes alone.
func _build_bars() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CinematicBars"
	layer.layer = 1
	_root.add_child(layer)

	for bar_name: String in ["Top", "Bottom"]:
		var bar := ColorRect.new()
		bar.name = bar_name
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2.ZERO if bar_name == "Top" else Vector2(0.0, 1080.0)
		bar.size = Vector2(1920.0, 0.0)
		layer.add_child(bar)
		# An animated size is not a layout: anchors would fight the track every frame.
		bar.set(&"layout_mode", 0)


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
		else:
			# phone-call.script's onCreatePost: currentStage.getGirlfriend().visible = false.
			character.visible = false

		# The camera aims at a character's midpoint plus its cameraOffsets, and the chart's
		# FocusCamera events add their own offset on top of that. All three get a marker,
		# girlfriend included: `char` is an index into the cast, and this chart uses 0 and
		# 1 but the format allows 2.
		#
		# These are DIRECT children of the level root on purpose. RubiconPositionSetter, if
		# anything ever points at them, reads only `target.position` - its ancestor walk is
		# inert, because `node is Parallax2D or ParallaxBackground or ParallaxLayer` parses
		# as `(node is Parallax2D) or ParallaxBackground or ...` and a class used as an
		# expression is truthy - so a marker under any transform loses it in silence.
		var point := Marker2D.new()
		point.name = "%sCameraPoint" % (side if not side.is_empty() else "Girlfriend")
		point.position = (character.position
			- Vector2(0.0, float(entry["height"]) * 0.5)
			+ (entry["camera_offsets"] as Vector2))
		_root.add_child(point)


func _place_stand_cast(stage: Node2D) -> void:
	for character_name: String in STAND_CAST:
		var entry: Dictionary = STAND_CAST[character_name]
		var character: Node2D = load(entry["scene"]).instantiate(
			PackedScene.GEN_EDIT_STATE_INSTANCE)
		character.name = character_name
		var frame: Vector2 = entry["frame"]
		character.position = (entry["corner"] as Vector2) + Vector2(frame.x * 0.5, frame.y)
		character.z_index = STAND_Z
		character.visible = false
		stage.add_child(character)


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

	# No RubiconPositionSetter. That node picks between NAMED points, which is the right
	# shape for a level that alternates between two singers on the measure; this song
	# authors 20 camera moves with their own offsets, durations and eases, and the baked
	# position_interpolate_target track carries all of it.
	var bumper: Node = _add(camera, Node.new(), "RubiconCameraBumper", BUMPER_SCRIPT)
	bumper.bump_every = 1  # BumpTime.BEAT - SetCameraBop's `rate` is in beats
	bumper.bump_interval = 4
	bumper.bump_amount = 0.0  # the chart's first SetCameraBop turns the bop off

	var events: Node = _add(_root, Node.new(), "PhoneCallEvents", EVENTS_SCRIPT)
	events.camera = camera
	events.bumper = bumper
	events.hud = _root.get_node("UILayer")
	# The chart names characters the way Funkin does, and uses both "boyfriend" and "bf".
	var cast_map: Dictionary[StringName, Node] = {
		&"boyfriend": _root.find_child("Tadano", true, false),
		&"bf": _root.find_child("Tadano", true, false),
		&"dad": _root.find_child("Komi", true, false),
		&"gf": _root.find_child("KomiGirlfriend", true, false),
	}
	events.cast = cast_map
	var stand_map: Dictionary[StringName, Node] = {}
	for character_name: String in STAND_CAST:
		stand_map[StringName((STAND_CAST[character_name] as Dictionary)["slot"])] = \
			_root.find_child(character_name, true, false)
	events.stand_cast = stand_map
	events.stage = _root.get_node("Stage")
	var overlays: Dictionary = _build_overlays()
	events.flash = overlays["flash"]
	events.fade = overlays["fade"]

	# onBeatHit case 332: the bar and its icons go one way, the strumlines the other.
	var up: Array[Node] = [_root.get_node("UILayer/UI/HealthBar")]
	var down: Array[Node] = [
		_root.get_node("UILayer/UI/Opponent"), _root.get_node("UILayer/UI/Player")]
	events.hud_up = up
	events.hud_down = down


func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		if child != owner and child.owner == null:
			child.owner = owner
		_own(child, owner)
