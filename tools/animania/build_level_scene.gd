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
## Not Rubicon's funkin bar: Animania's is a drawn stroke that arches and tapers, in the
## two characters' own icon colours, and it ships as art rather than as a rectangle. Built
## by tools/animania/build_health_bar.gd.
const HEALTH_BAR := "res://animania_mod/ui/health_bar.tscn"
# Not resources/levels/ui/funkin/funkin_note_override.tres: this chart uses the note kind
# "noAnimation" on two notes, and a kind Rubicon has no database entry for throws on every
# frame the note is alive. See the header of the file itself.
const NOTE_OVERRIDES := "res://animania_mod/songs/phone_call_note_overrides.tres"
const INPUT_MAP := "res://addons/rubicon_mania/resources/default_input_map.tres"

const EVENTS_SCRIPT := "res://animania_mod/scripts/phone_call_events.gd"
const ICON_SCRIPT := "res://animania_mod/scripts/animated_health_icon.gd"
const DEATH_SCRIPT := "res://animania_mod/scripts/death_sequence.gd"
const GAMEOVER_AUDIO := "res://animania_mod/source/audio/gameover"
## How tall the mod draws its icons, measured on a capture of it running: their art spans
## y 37..129 of a 1280x720 frame, which is 140 of this project's pixels. Both characters
## are fitted to it, since their own frames differ - tadano's is 146 tall and komi's 158.
const ICON_HEIGHT := 140.0

## phone-call.script's POSITION_OFFSET. Pulls both icons back toward the bar's centre by
## this many Funkin pixels on each side - see the comment on `icon.offset` below for the
## algebra that turns it into the same correction for both icons regardless of width.
const ICON_POSITION_OFFSET := 26.0
const CHART_JSON := "res://animania_mod/source/songs/phone-call/phone-call-chart.json"

# Funkin is 1280x720 and this project is 1920x1080, so the stage's own cameraZoom is
# multiplied by 1.5 to frame the same amount of world. See build_stage_scene.gd.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

# The two singers, with the numbers each one's JSON authors. `height` is the height of
# Funkin's FRAME and is used only to find the midpoint its camera aims at - not the height
# of the art drawn in it. For komi they coincide (sparrow frame 776, art 769 sitting on its
# bottom edge); for tadano, an Animate atlas with no authored frame, they do not, and 1133
# is measured against a capture of the original - see build_character_scenes.gd.
const CAST := {
	"Tadano": {
		"scene": TADANO, "marker": "PlayerPoint", "offsets": Vector2(250, 180),
		"camera_offsets": Vector2(-250, 100), "height": 1133.0, "side": "Player",
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
## onCreatePost's `barHeight`, in Funkin pixels. The sprites are 20 taller and hang 20 off
## each edge, so this is what actually shows.
const SCRIPT_BAR_HEIGHT := 100.0
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
	# Before the camera: _build_camera wires the events node, and that now points at the
	# opening's letterbox.
	_build_bars()

	_build_camera()

	var health: Node = _add(_root, Node.new(), "RubiconHealthModule", HEALTH_SCRIPT)
	health.note_controller = ui["Player"]
	health.starting_health = 50.0
	ui["HealthBar"].health_module = health
	_dress_icons(ui, health)

	_build_death(health, song)

	# No touch controls here. They are an AUTOLOAD - project.godot loads
	# addons/rubicon_mobile_controls/mobile_controls.tscn globally - and the addon has no
	# singleton guard, so a copy in the level meant two of them running _setup_buttons and
	# both drawing. Their alpha stacked, which is why the hitboxes read as a slab on a
	# device however low either one was set, and setting the opacity here changed the copy
	# that was not in charge. The autoload alone is right: it also covers the title screen,
	# which needs a tap to skip the intro.

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
	#
	# TWO sets of offsets, not one - the same rule the phone pair already follow.
	# Stage_obj::applyCharacterData adds the STAGE's own cameraOffsets on top of the ones
	# the character JSON carries, and standUP() puts these two into the SAME slots
	# (addCharacter(.., CharacterType.BF/DAD)), so phoneCallStreet's [-80, -150] for bf and
	# [-300, -150] for dad count for them too. Dropped, the camera sat 300px right of komi
	# and 150px low on both, which is a device run reporting the framing after the swap does
	# not match the mod - measured at 94.3s with the camera at world x=588 where komi's own
	# point puts it at 288.
	#
	# NOT scaled by FUNKIN_TO_RUBICON. Same bug as the chart's own FocusCamera offsets: these
	# are world-space pixels and this port keeps world coordinates verbatim, the 1.5 lives
	# on the camera's zoom. Scaled, tadano's point landed at world x=270 instead of 170 -
	# 100px right of where his own cameraOffsets put it - which is what put empty stage to
	# the right of him in frame instead of centring him after the character swap.
	var stand_points: Dictionary = {}
	for character_name: String in STAND_CAST:
		var entry: Dictionary = STAND_CAST[character_name]
		var character: Node2D = _root.find_child(character_name, true, false)
		var offsets := Vector2(200.0, 50.0) if entry["slot"] == "boyfriend" \
			else Vector2(50.0, 50.0)
		# The slot's own marker, which is where the stage's offsets were read onto.
		var marker_name: String = "PlayerPoint" if entry["slot"] == "boyfriend" \
			else "OpponentPoint"
		var marker: Marker2D = stage.find_child(marker_name, true, false)
		var stage_offsets: Vector2 = Vector2.ZERO if marker == null \
			else marker.get_meta(&"camera_offsets", Vector2.ZERO)
		stand_points[0 if entry["slot"] == "boyfriend" else 1] = (character.position
			- Vector2(0.0, (entry["frame"] as Vector2).y * 0.5)
			+ offsets + stage_offsets)

	# case 168 slides tadano 800px right and leaves him there until standUP. Read off the
	# events script rather than repeated here, so the slide and the camera cannot disagree
	# about how far he went or how long it took.
	var slide: Dictionary = load(EVENTS_SCRIPT).get_script_constant_map()
	var slide_beat: float = 168.0 * 60.0 / 152.0
	var moved_offsets: Dictionary = {
		0: Vector2(float(slide["SLIDE_DISTANCE"]), 0.0),
	}

	var baker: RefCounted = load("res://tools/animania/camera_events.gd").new(
		focus_points, base_zoom, stand_points, STAND_UP_BEAT * 60.0 / 152.0,
		moved_offsets, slide_beat + float(slide["SLIDE_SECONDS"]))
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
			# onCreatePost's `disableKeys = true`. Set on the SCENE and not only in the
			# events script's opening(), because onCreatePost runs before the song exists:
			# a level that has been instantiated but not entered the tree has not run
			# _ready, and it should still be deaf.
			controller.disable_inputs = true
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
			# An autoplayed lane's AnimationTree only ever observes NEUTRAL: hit_note()
			# sets HIT and clears it again inside the SAME _process call, one frame before
			# the tree - a child, so it runs after its handler - gets to see it. The
			# "neutral -> hit_init" transition that draws the receptor's confirm flash
			# never fires, so komi's side never lit up on a hit while tadano's did. This
			# is documented, upstream Rubicon behaviour with a one-frame opt-in built for
			# exactly this: an autoplayed strumline someone deliberately put on screen.
			if side == "Opponent":
				lane.lane_autoplay_hit_lingers = true
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
			# The OPPONENT reads the inverse - see animania_health_icon.gd, and
			# AnimaniaStuff's own `isPlayer = (icon.playerId == 0)`, which is what settles
			# it against the song script's backwards comments.
			"controller": ui["Opponent"], "inverted": true, "alt": true, "tilt": 50.0,
			# komi.hx sets icon.flipX, and the atlas's poses are authored for it - which is
			# why its "right" art is this port's sing_left.
			"flip": true,
			# And her ART flips back. `flip` only picks the side: Rubicon places an icon by
			# the SIGN of scale.x, so the one on the far side of the follow point is
			# mirrored as a side effect of being put there. Against a capture of the mod
			# that came out backwards - the curved strand that sits on the right of her face
			# was on the left - so the drawing is mirrored again, which leaves her where she
			# was and facing the way the mod draws her.
			"mirror": true,
		},
		"IconR": {
			"frames": "res://animania_mod/characters/tadano_icon.tres",
			"controller": ui["Player"], "inverted": false, "alt": false, "flip": false,
			"mirror": false, "tilt": -30.0,
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
		# onCreatePost sets bopEvery on BOTH icons, so both take the clock.
		icon.clock = _root.get_node("RubiconLevelClock")
		icon.inverted = entry["inverted"]
		icon.tilt_degrees = entry["tilt"]
		icon.has_alt_poses = entry["alt"]
		# Fitted to the height the MOD draws them at rather than left at native size. That
		# height is measured off a capture rather than taken from healthIcon.scale: the
		# JSONs say 0.9, which on tadano's 146px frame would be 131 Funkin pixels, and the
		# capture puts him at 93.
		var frame: Texture2D = icon.sprite_frames.get_frame_texture(&"idle", 0)
		var fit: float = ICON_HEIGHT / float(frame.get_height())
		icon.scale = Vector2(-fit if entry["flip"] else fit, fit)
		# flip_h and not another sign on the scale: the sign is what puts the icon on its
		# side of the follow point, so mirroring the art has to happen inside the sprite.
		icon.flip_h = entry["mirror"]

		# offset is in the sprite's own space, and the bar authors -73 for bf's 138px icon:
		# half its width. Keeping -73 for a 167px icon slides it out of place instead of
		# scaling with it.
		#
		# ICON_POSITION_OFFSET pulls both icons back toward the anchor by the same amount.
		# phone-call.script never sets icon.x from half a width alone: `icon.x = C - 26` for
		# one side and `C - (width - 26)` for the other, and the 26 survives the algebra
		# regardless of which side or how wide the icon is - working through both cases
		# reduces to the same "offset.x = -width/2 + 26" for both. Left out, the two icons
		# sit edge to edge with no overlap; a capture of the mod has their heads overlapping.
		icon.offset = Vector2(
			-frame.get_width() * 0.5 + ICON_POSITION_OFFSET * FUNKIN_TO_RUBICON,
			icon.offset.y)


## An instanced Control loses its authored anchors unless layout_mode says to keep them.
## Godot recomputes a Control's layout when it is reparented, and with layout_mode unset it
## resets the anchors to zero - the health bar came out 4x27 pixels in the top-left corner
## of the first build of this scene, instead of the bar across the top it is authored as.
## test.tscn carries the same `layout_mode = 1` on every instanced Control for this reason.
func _add_control(parent: Control, control: Control) -> void:
	parent.add_child(control)
	control.set(&"layout_mode", 1)
	# And PRESET_CUSTOM, or layout_mode picks a preset that happens to match the anchors and
	# the instance saves `anchors_preset = N`, which RE-APPLIES that preset on load and
	# throws the authored offsets away. The health bar is anchored dead centre at the top,
	# which is preset 5, so it came out pinned to the top of the screen 45px above its own
	# mark. -1 records "custom" and moves nothing.
	control.set(&"anchors_preset", -1)


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


## Tadano's death sequence. Rubicon emits health_depleted and nothing in the engine listens,
## so every piece of this is new: the dark wash, the two black panels, the retry text and
## the three audio tracks. It all sits on its own CanvasLayer above the stage and below the
## HUD, because Funkin puts it on the game camera and over PlayState's persistent draw.
func _build_death(health: Node, song: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "Death"
	layer.layer = 1
	_root.add_child(layer)

	var dark := ColorRect.new()
	dark.name = "Dark"
	dark.color = Color(0.0, 0.0, 0.0, 0.0)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.size = Vector2(1920.0, 1080.0)
	layer.add_child(dark)
	dark.set(&"layout_mode", 0)

	var panels: Dictionary = {}
	for panel_name: String in ["LeftPanel", "RightPanel"]:
		var panel := ColorRect.new()
		panel.name = panel_name
		panel.color = Color.BLACK
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.size = Vector2(600.0, 1080.0)
		panel.visible = false
		layer.add_child(panel)
		panel.set(&"layout_mode", 0)
		panels[panel_name] = panel

	# The retry text is an Adobe atlas driven by FRAME LABELS, not symbols - see
	# tools/animania/build_death_text.gd. Its library is swapped in at death time for
	# whichever form the song is in.
	var retry := AnimateSymbol.new()
	retry.name = "RetryText"
	retry.atlases = [
		load("res://animania_mod/characters/tadano_death_text_atlas.tres"),
		load("res://animania_mod/characters/tadano_stand_death_text_atlas.tres"),
	] as Array[AnimateAtlas]
	retry.atlas_index = 0
	retry.centered = false
	retry.modulate.a = 0.0
	# On the death layer, above the dark wash - Funkin adds it to GameOverSubState, which
	# draws over darkBg. death_sequence.gd puts it back under the camera every frame.
	layer.add_child(retry)

	var retry_player := AnimationPlayer.new()
	retry_player.name = "AnimationPlayer"
	retry.add_child(retry_player)

	var sequence: Node = _add(_root, Node.new(), "DeathSequence", DEATH_SCRIPT)
	sequence.health_module = health
	sequence.song = song
	sequence.clock = _root.get_node("RubiconLevelClock")
	sequence.camera = _root.get_node("RubiconInterpolatedCamera2D")
	sequence.events = _root.get_node("PhoneCallEvents")
	sequence.dark = dark
	sequence.left_panel = panels["LeftPanel"]
	sequence.right_panel = panels["RightPanel"]
	sequence.retry_text = retry
	sequence.retry_player = retry_player
	sequence.phone_player = _root.find_child("Tadano", true, false)
	sequence.phone_opponent = _root.find_child("Komi", true, false)
	sequence.stand_player = _root.find_child("TadanoStand", true, false)
	sequence.stand_opponent = _root.find_child("KomiStand", true, false)
	sequence.phone_text = load("res://animania_mod/characters/tadano_death_text_library.tres")
	sequence.stand_text = load(
		"res://animania_mod/characters/tadano_stand_death_text_library.tres")

	for entry: Array in [
			["Music", "gameOver-tadano.ogg", "music"],
			["LossSound", "fnf_loss_sfx-tadano.ogg", "loss_sound"],
			["ConfirmMusic", "gameOverEnd-tadano.ogg", "confirm_music"]]:
		var player := AudioStreamPlayer.new()
		player.name = entry[0]
		player.stream = load("%s/%s" % [GAMEOVER_AUDIO, entry[1]])
		player.bus = &"Music"
		sequence.add_child(player)
		sequence.set(StringName(entry[2]), player)


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

	_build_script_bars(layer)


## onCreatePost's barTop and barBottom, which are NOT the chart's CinematicBars.
##
## The script adds its own pair at zIndex 4999 in onCreatePost and kills them at beat 33.
## They are sprites `barHeight + 20` tall placed 20px past each edge, so what shows is
## exactly barHeight - a hundred Funkin pixels top and bottom - and it is there from the
## FIRST FRAME. The chart's own bars animate up from nothing over the first 0.69 seconds,
## so without these the song opens on an unletterboxed frame that the mod never shows.
##
## They ride in the chart's own CanvasLayer so there is one decision about where the
## letterbox sits relative to the HUD, not two.
func _build_script_bars(layer: CanvasLayer) -> void:
	var holder := Control.new()
	holder.name = "ScriptBars"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	holder.set(&"layout_mode", 0)

	var height: float = SCRIPT_BAR_HEIGHT * FUNKIN_TO_RUBICON
	for bar_name: String in ["Top", "Bottom"]:
		var bar := ColorRect.new()
		bar.name = bar_name
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(bar)
		# layout_mode first, then size, then position: setting position before either lets
		# the later two re-derive the offsets and lose it. The bottom bar came out pinned to
		# the top exactly that way, and only the guard's rect check saw it.
		bar.set(&"layout_mode", 0)
		bar.size = Vector2(1920.0, height)
		bar.position = Vector2.ZERO if bar_name == "Top" else Vector2(0.0, 1080.0 - height)


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
		# Two sets of offsets, not one. Stage_obj::applyCharacterData in the mod's own
		# binary does `cameraFocusPoint.x += charData.cameraOffsets[0]` and the same for y,
		# ON TOP of the ones BaseCharacter_obj::resetCameraFocusPoint already added from the
		# character JSON - so phoneCallStreet.json's [-80, -150] for bf, [-300, -150] for
		# dad and [425, -150] for gf all count, and this port was dropping them.
		var stage_offsets: Vector2 = marker.get_meta(&"camera_offsets", Vector2.ZERO)
		var point := Marker2D.new()
		point.name = "%sCameraPoint" % (side if not side.is_empty() else "Girlfriend")
		point.position = (character.position
			- Vector2(0.0, float(entry["height"]) * 0.5)
			+ (entry["camera_offsets"] as Vector2)
			+ stage_offsets)
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

	# The opening. The cover goes INSIDE the stage's screen-space layer rather than in the
	# level's overlays, because Funkin gives blackScreenSpr zIndex 5999 - above overlay-all
	# at 5000 and below introText at 6000. Anywhere else and the title card, which is the
	# only thing meant to read during those first five seconds, is under the black.
	_build_subtitles()
	events.clock = _root.get_node("RubiconLevelClock")
	events.cover = _build_intro_cover()
	events.intro_text = _root.find_child("IntroText", true, false)
	events.hud_root = _root.get_node("UILayer/UI")
	events.player_lanes = _root.get_node("UILayer/UI/Player")
	events.opponent_lanes = _root.get_node("UILayer/UI/Opponent")
	events.script_bars = _root.get_node("CinematicBars/ScriptBars")
	events.player_point = _root.get_node("PlayerCameraPoint")
	events.opponent_point = _root.get_node("OpponentCameraPoint")

	# onBeatHit case 332: the bar and its icons go one way, the strumlines the other.
	var up: Array[Node] = [_root.get_node("UILayer/UI/HealthBar")]
	var down: Array[Node] = [
		_root.get_node("UILayer/UI/Opponent"), _root.get_node("UILayer/UI/Player")]
	events.hud_up = up
	events.hud_down = down


## The subtitle display, on its own layer ABOVE the HUD - and that is forced, not a
## preference. camHUD's alpha is 0 until beat 31 and the first three cues are at 8.7s, under
## the black cover; anything parented to the HUD would never show them. The title card is
## moved to camOther for exactly the same reason, and camOther draws over both.
func _build_subtitles() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Subtitles"
	layer.layer = 3
	_root.add_child(layer)

	var label := RichTextLabel.new()
	label.name = "Line"
	label.set_script(load("res://animania_mod/scripts/song_subtitles.gd"))
	label.bbcode_enabled = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 0.0
	# TOP, not bottom, and this is measured rather than chosen: a capture of the mod running
	# shows the line just under the upper letterbox bar. The first version of this port put
	# it at the bottom, reasoning that a subtitle usually goes there - but the bottom of
	# this screen is where the receptors are, which is presumably why the mod does not.
	#
	# Where exactly comes off the same capture: the mod's line sits with its box between
	# y=135 and y=167 of a 1280x720 frame, which is 202 project pixels down, not 120.
	label.offset_top = 202.0
	label.offset_bottom = 322.0
	label.add_theme_font_size_override("normal_font_size", 39)
	label.add_theme_constant_override("outline_size", 12)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	layer.add_child(label)
	label.owner = _root
	layer.owner = _root
	label.clock = _root.get_node("RubiconLevelClock")


## onCreatePost's blackScreenSpr: a full-screen black rect at zoomFactor 0, which is to say
## in the stage's screen-space layer, between the light overlay and the title card.
func _build_intro_cover() -> ColorRect:
	var screen_space: Node = _root.get_node("Stage/ScreenSpace")
	var cover := ColorRect.new()
	cover.name = "IntroCover"
	cover.color = Color(0.0, 0.0, 0.0, 1.0)
	cover.size = Vector2(1920.0, 1080.0)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_space.add_child(cover)
	# Ascending zIndex is tree order inside a CanvasLayer, and the stage put overlay-all
	# first and introText second.
	screen_space.move_child(cover, 1)
	cover.owner = _root
	return cover


func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		if child != owner and child.owner == null:
			child.owner = owner
		_own(child, owner)
