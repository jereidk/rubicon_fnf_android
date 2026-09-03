# Guard for the Phone Call Street port: the stage, the two characters, and the leaves.
#
# Everything checked here is something that fails SILENTLY. A dropped animation track, a
# character anchored by its corner instead of its feet, a hidden prop that should be
# visible - none of them error, they just come out wrong on a device. Each check derives
# its expectation from the mod's own data (phoneCallStreet.json, komi.json, tadano.json,
# komi.xml, Animation.json) rather than from a number written down here, so re-exporting
# the mod moves the expectation with it instead of leaving this file quietly lying.
#
#   godot --headless --path . --script tools/animania/test_phone_call_port.gd
extends SceneTree

const STAGE := "res://animania_mod/stages/stg_phone_call_street.tscn"
const KOMI := "res://animania_mod/characters/chr_komi.tscn"
const TADANO := "res://animania_mod/characters/chr_tadano.tscn"
const STAGE_JSON := "res://animania_mod/source/data/phoneCallStreet.json"
const TADANO_ANIMATION := "res://animania_mod/source/images/phonecall/tadano/Animation.json"
const LEVEL := "res://songs/phone-call/phone_call.tscn"
const CHART_JSON := "res://animania_mod/source/songs/phone-call/phone-call-chart.json"
const SUBTITLES := "res://animania_mod/source/songs/phone-call/subtitles/song-lyrics.srt"

var _failures: int = 0
## How many checks actually ran. A GDScript runtime error inside a check does not stop the
## run - it prints, abandons what it was doing, and lets the caller carry on - so a section
## that names a constant somebody deleted goes quiet and the run still ends in "todo OK".
## That is exactly what happened to the whole icon section. Counting the checks and
## refusing to pass with fewer than there were is the cheapest thing that notices.
var _checks: int = 0


const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## How tall the mod draws its health icons, measured on a capture of it running.
const ICON_HEIGHT := 140.0

## phone-call.script's POSITION_OFFSET, in Funkin pixels. See build_level_scene.gd's own
## comment on icon.offset for why this is the correction on BOTH icons regardless of side
## or width - the algebra of `icon.x = C - 26` and `icon.x = C - (width - 26)` reduces to
## the same "offset.x = -width/2 + 26" either way.
const ICON_POSITION_OFFSET := 26.0
const STEP_SECONDS := 60.0 / 152.0 / 4.0

## The number of checks a complete run makes. Raise it when you add checks; it only exists
## so that a section which stops running is louder than a section which passes.
const MIN_CHECKS := 853


func _init() -> void:
	var stage_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STAGE_JSON))

	_check_stage(stage_data)
	_check_character(KOMI, "komi", 8)
	_check_character(TADANO, "tadano", 22)
	_check_tadano_symbols()
	_check_leaves()
	_check_notestyle()
	_check_level()
	await _check_camera_events()

	if _failures > 0:
		printerr("%d comprobaciones fallaron" % _failures)
		quit(1)
		return
	if _checks < MIN_CHECKS:
		printerr("solo se ejecutaron %d comprobaciones de %d: alguna seccion se abandono "
			% [_checks, MIN_CHECKS] + "a medias, mira si hay un SCRIPT ERROR mas arriba")
		quit(1)
		return
	print("todo OK: %d comprobaciones" % _checks)
	quit(0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	printerr("FALLO: %s" % message)
	_failures += 1


func _check_stage(data: Dictionary) -> void:
	var stage: Node2D = load(STAGE).instantiate()

	_check(is_equal_approx(float(stage.get_meta(&"camera_zoom")), float(data["cameraZoom"])),
		"el cameraZoom del escenario no es el del JSON")

	# Every prop in the JSON has to exist, at the position and zIndex it declares, and
	# the six "stand-" ones have to ship hidden - buildStage() hides them by name.
	for prop: Dictionary in data["props"]:
		var prop_name: String = prop["name"]
		if prop_name in ["overlay-all", "introText"]:
			continue  # zoomFactor 0: screen space, in the CanvasLayer, checked below

		var node_name: String = prop_name.replace(" ", "_").replace("-", "_")
		var node: Sprite2D = stage.find_child(node_name, true, false) as Sprite2D
		_check(node != null, "falta el prop %s" % prop_name)
		if node == null:
			continue

		_check(node.position.is_equal_approx(Vector2(
				float(prop["position"][0]), float(prop["position"][1]))),
			"%s esta en %s y el JSON dice %s" % [prop_name, node.position, prop["position"]])
		_check(node.z_index == int(prop["zIndex"]),
			"%s tiene z=%d y el JSON dice %s" % [prop_name, node.z_index, prop["zIndex"]])
		_check(not node.centered,
			"%s esta centrado: Flixel ancla por la esquina superior izquierda" % prop_name)

		var hidden: bool = prop_name.contains("stand-")
		_check(node.visible != hidden,
			"%s deberia %s" % [prop_name, "estar oculto" if hidden else "estar visible"])

		# scrollFactor lives on the Parallax2D above it, except for lightShade, where
		# buildStage() overrides the JSON's (0, 0.5) with (0, 1).
		var expected_scroll := Vector2(float(prop["scroll"][0]), float(prop["scroll"][1]))
		if prop_name == "lightShade":
			expected_scroll = Vector2(0.0, 1.0)
		var parallax: Parallax2D = node.get_parent() as Parallax2D
		_check(parallax != null, "%s no cuelga de un Parallax2D" % prop_name)
		if parallax != null:
			_check(parallax.scroll_scale.is_equal_approx(expected_scroll),
				"%s scroll=%s, esperado %s" % [prop_name, parallax.scroll_scale, expected_scroll])

	# The sky is not a prop: FlxBackdrop(sky, FlxAxes.X, ...) with velocity.x 20.
	var sky: Parallax2D = stage.find_child("Sky", true, false) as Parallax2D
	_check(sky != null, "falta el cielo")
	if sky != null:
		_check(sky.repeat_size.x > 0.0 and is_zero_approx(sky.repeat_size.y),
			"el cielo repite en Y, y FlxAxes.X solo repite en X")
		_check(is_equal_approx(sky.autoscroll.x, 20.0),
			"el cielo no va a 20 px/s: velocity.x del FlxBackdrop")

	# zoomFactor 0 means the camera zoom never reaches them, which is a CanvasLayer.
	var screen: CanvasLayer = stage.find_child("ScreenSpace", true, false) as CanvasLayer
	_check(screen != null, "falta la capa de pantalla")
	if screen != null:
		var overlay: Sprite2D = screen.find_child("OverlayAll", true, false) as Sprite2D
		var intro: Node = screen.find_child("IntroText", true, false)
		_check(overlay != null and intro != null, "faltan overlay-all o introText")
		if overlay != null and intro != null:
			# overlay-all is zIndex 5000 and introText 6000: in a CanvasLayer the order is
			# the tree order, and the JSON lists them the other way round.
			_check(overlay.get_index() < intro.get_index(),
				"overlay-all tiene que dibujarse por debajo de introText")
			_check(overlay.material is CanvasItemMaterial
					and (overlay.material as CanvasItemMaterial).blend_mode
						== CanvasItemMaterial.BLEND_MODE_ADD,
				'overlay-all lleva "blend": "add" en el JSON')

	# addCharacter() gives DAD scrollFactor (0.9, 0.95); BF and GF keep (1, 1).
	var opponent: Marker2D = stage.find_child("OpponentPoint", true, false) as Marker2D
	_check(opponent != null, "falta OpponentPoint")
	if opponent != null:
		var parallax: Parallax2D = opponent.get_parent() as Parallax2D
		_check(parallax != null and parallax.scroll_scale.is_equal_approx(Vector2(0.9, 0.95)),
			"el oponente no esta en la capa (0.9, 0.95) que le da addCharacter()")
	for slot: String in ["PlayerPoint", "GirlfriendPoint"]:
		var marker: Marker2D = stage.find_child(slot, true, false) as Marker2D
		_check(marker != null and not (marker.get_parent() is Parallax2D),
			"%s no deberia parallaxear: solo DAD lo hace" % slot)

	stage.free()


func _check_character(path: String, character_name: String, expected: int) -> void:
	var character: Node2D = load(path).instantiate()
	root.add_child(character)

	var player: AnimationPlayer = character.animation_player
	_check(player != null, "%s no tiene animation_player" % character_name)
	if player == null:
		character.queue_free()
		return

	_check(player.get_animation_list().size() == expected,
		"%s tiene %d animaciones y esperaba %d" % [
			character_name, player.get_animation_list().size(), expected])
	_check(player.autoplay == &"dance_idle", "%s no arranca en dance_idle" % character_name)

	# Every alias the note controller can ask for has to resolve to a real animation.
	for alias: StringName in character.animations:
		var target: StringName = character.animations[alias]
		_check(player.has_animation(target),
			"%s: %s apunta a %s, que no existe" % [character_name, alias, target])

	# A track whose NodePath or property does not resolve is dropped in silence.
	for anim_name: String in player.get_animation_list():
		var animation: Animation = player.get_animation(anim_name)
		for i: int in animation.get_track_count():
			var path_string: String = String(animation.track_get_path(i))
			var node: Node = character.get_node_or_null(NodePath(path_string.get_slice(":", 0)))
			_check(node != null, "%s/%s: la pista %s no resuelve" % [
				character_name, anim_name, path_string])
			if node == null:
				continue
			if animation.track_get_type(i) == Animation.TYPE_ANIMATION:
				var clip: StringName = animation.animation_track_get_key_animation(i, 0)
				_check((node as AnimationPlayer).has_animation(clip),
					"%s/%s: no existe el clip %s" % [character_name, anim_name, clip])
			elif animation.track_get_type(i) == Animation.TYPE_VALUE:
				_check(path_string.get_slice(":", 1) in node,
					"%s/%s: %s no tiene la propiedad" % [character_name, anim_name, path_string])

	# Stage.addCharacter anchors by characterOrigin - horizontal centre, vertical BOTTOM -
	# so a character node's own origin has to be that point of its FRAME. Checked as "the
	# art is drawn above the origin", which a corner-anchored character (the first version
	# of this port) fails.
	#
	# Horizontally it is only checkable for komi. Her frame is the sparrow 307x776 and her
	# art fills it, so centred art means a centred frame. tadano is an Animate atlas whose
	# frame is much bigger than his art and is not readable from Animation.json, so his
	# anchor is measured against a capture of the original instead - see
	# build_character_scenes.gd. Asserting "centred" here would only assert the guess this
	# port started with, which is exactly the guess that put him 755px off.
	var drawn: Node2D = null
	for child: Node in character.get_children():
		if child is AnimatedSprite2D or child is AnimateSymbol:
			drawn = child as Node2D
			break
	_check(drawn != null, "%s no tiene sprite" % character_name)
	if drawn != null:
		var anchor: Vector2 = drawn.position * drawn.scale
		_check(anchor.y < -100.0,
			"%s no esta anclado por los pies: el sprite sale en y=%.1f" % [
				character_name, anchor.y])
		var centred: float = 300.0 if character_name != "tadano" else 600.0
		_check(absf(anchor.x) < centred,
			"%s se dibuja en x=%.1f, fuera del marco que su origen dice tener" % [
				character_name, anchor.x])

	character.queue_free()


# The symbol each animation names has to be a real key in Animation.json's symbol
# dictionary. gdanimate falls back to the stage symbol for a name it cannot find, which
# draws SOMETHING - so a typo here is a wrong character, not a missing one.
func _check_tadano_symbols() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TADANO_ANIMATION))
	var known: Dictionary = {}
	for symbol: Dictionary in data["SD"]["S"]:
		known[String(symbol["SN"])] = true

	var library: AnimationLibrary = load("res://animania_mod/characters/tadano_library.tres")
	for anim_name: StringName in library.get_animation_list():
		var animation: Animation = library.get_animation(anim_name)
		var symbol: String = animation.track_get_key_value(0, 0)
		_check(known.has(symbol), "tadano: %s nombra el simbolo %s, que no esta en el atlas" % [
			anim_name, symbol])
		# The symbol's length is the frame count; a mismatch means the clip cuts short.
		var frames: int = animation.track_get_key_count(1)
		_check(frames > 0, "tadano: %s no tiene fotogramas" % anim_name)

	_check_tadano_sing_faces()


## The four sing directions share ONE `facessing` symbol and take a two-frame window of it
## each, declared as firstFrame/lastFrame on the instance. gdanimate used to read only
## firstFrame, so a play-once instance ran past its window: sing-left started on the left
## face and walked through the down, up and right ones while the note was still being sung,
## sing-down through up and right, sing-up into right - and sing-right, whose window ends
## where the symbol does, was the one direction that looked correct. That is what the bug
## report described. This holds every window shut.
##
## The expected frames come from Animation.json, not from a table, so re-exporting the
## atlas moves them here too.
func _check_tadano_sing_faces() -> void:
	var atlas: AdobeAtlas = load("res://animania_mod/characters/tadano_atlas.tres")
	atlas.parse()
	for direction: String in ["left", "down", "up", "right"]:
		var key: StringName = StringName("chars render/tadano 1/tadano %s" % direction)
		var symbol: AdobeSymbol = atlas.symbols.get(key)
		_check(symbol != null, "tadano: falta el simbolo de canto %s" % direction)
		if symbol == null:
			continue
		var seen: bool = false
		for layer: AdobeLayer in symbol.layers:
			for layer_frame: AdobeLayerFrame in layer.frames:
				for element in layer_frame.elements:
					if not element is AdobeSymbolInstance:
						continue
					if element.last_frame < 0:
						continue
					seen = true
					var length: int = atlas.symbols[element.key].length
					for at: int in layer_frame.duration:
						var shown: int = atlas.symbol_instance_frame(element, length, at)
						_check(shown >= element.first_frame and shown <= element.last_frame,
							("tadano %s: %s se sale de su ventana %d..%d en el fotograma "
								+ "%d (muestra %d)") % [direction, element.key,
								element.first_frame, element.last_frame, at, shown])
		_check(seen, "tadano %s: ninguna instancia declara lastFrame, "
			% direction + "el atlas se reconstruyo desde una cache vieja")


func _check_leaves() -> void:
	var stage: Node2D = load(STAGE).instantiate()
	var leaves: Node2D = stage.find_child("Leaves", true, false) as Node2D
	_check(leaves != null, "falta el sistema de hojas")
	if leaves == null:
		stage.free()
		return

	_check(leaves.z_index == 900, "las hojas van a zIndex 900 en el .hx")
	_check(leaves.get(&"leaf_frames") != null, "las hojas no tienen SpriteFrames")
	_check(leaves.has_method(&"beat_hit"),
		"las hojas no exponen beat_hit(): onBeatHit es lo que las genera")

	var script: Script = leaves.get_script()
	var constants: Dictionary = script.get_script_constant_map()
	_check(is_equal_approx(float(constants["RECYCLE_Y"]), 1550.0),
		"la Y de reciclado no es la del .hx")
	_check(int(constants["MAX_LEAVES"]) == 9 and int(constants["INITIAL_LEAVES"]) == 3,
		"el .hx arranca con 3 hojas y tapa en 9")
	_check(is_equal_approx(float(constants["SPAWN_CHANCE"]), 0.10),
		"FlxG.random.bool(10) es un 10%")

	stage.free()


# The level scene. Every one of these caught something real while it was being built, and
# each failure mode is silent: a dropped node, a reset anchor, a missing note kind.
func _check_level() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)

	# PackedScene drops a node whose parent is inside an instanced sub-scene unless the
	# instance is editable, and says nothing. Komi goes inside one of the stage's own
	# Parallax2D nodes - addCharacter gives DAD scrollFactor (0.9, 0.95) - and vanished
	# from the first build of this scene exactly that way.
	for character_name: String in ["Tadano", "Komi", "KomiGirlfriend"]:
		var character: Node = level.find_child(character_name, true, false)
		_check(character != null, "falta el personaje %s en el nivel" % character_name)
	var opponent: Node = level.find_child("Komi", true, false)
	if opponent != null:
		_check(opponent.get_parent() is Parallax2D,
			"komi no esta en la capa de parallax que le da addCharacter()")

	# The clock reads its time off this player, so the animation's length is the song's.
	var clock: Node = level.get_node("RubiconLevelClock")
	var song: Node = level.get_node("RubiconLevelSongModule")
	var timeline: float = clock.animation_player.get_animation(&"scene").length
	var instrumental: AudioStreamPlayer = song.audio_players[0]
	_check(is_equal_approx(timeline, instrumental.stream.get_length()),
		"la linea de tiempo dura %.3fs y el instrumental %.3fs" % [
			timeline, instrumental.stream.get_length()])
	_check(instrumental.name == "Instrumental" and song.sync_reference_player == instrumental,
		"el instrumental tiene que ir primero y ser la referencia de sincronia")
	_check(song.audio_players.size() == 3,
		"faltan pistas: las voces vienen partidas por personaje")

	# Each side's chart against the source JSON, where `d` is a lane AND a side - and which
	# half is whose is settled by MEASUREMENT, not by reading. This line had it backwards,
	# which is what crossed the two charts: tadano was given the notes komi sings, and komi
	# sang tadano's. Neither a render nor the data shows it; both halves look like charts.
	#
	# What settles it is the mod shipping SPLIT VOCALS. The first `d < 4` note is at 18.95s
	# and the first `d >= 4` note at 12.26s, so both tracks were measured at both moments:
	#
	#     t=12.2s   tadano -52.9 dB (silent)   komi -24.7 dB (singing)
	#     t=18.9s   tadano -23.7 dB (singing)  komi -62.2 dB (silent)
	#
	# So `d < 4` is TADANO, the player, and `d >= 4` is komi. The two chart files on disk
	# are named the other way round by the converter and were swapped to match.
	var chart_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART_JSON))
	var notes: Array = chart_data["notes"]["standart"]
	var expected: Dictionary = {"Opponent": 0, "Player": 0}
	var kinds: Dictionary = {}
	for note: Dictionary in notes:
		var side: String = "Opponent" if int(note.get("d", 0)) >= 4 else "Player"
		expected[side] = int(expected[side]) + 1
		var kind: String = str(note.get("k", ""))
		if not kind.is_empty():
			kinds[kind] = true

	for side: String in ["Opponent", "Player"]:
		var controller: Node = level.get_node("UILayer/UI/%s" % side)
		var total: int = 0
		for section: Resource in controller.chart.sections:
			for row: Resource in section.rows:
				total += row.starts.size()
		_check(total == int(expected[side]),
			"%s tiene %d notas y el JSON dice %d" % [side, total, expected[side]])
		_check(controller.get_child_count() == 4,
			"%s tiene %d carriles, esperaba 4" % [side, controller.get_child_count()])

		# A note kind with no database entry throws on every frame the note is alive, not
		# once: the full-song run produced 911 errors off two notes.
		for kind: String in kinds:
			var key: StringName = StringName("%s_mania" % kind)
			_check(controller.note_overrides != null
					and controller.note_overrides.defines.has(key),
				"no hay entrada de base de datos para %s" % key)

	_check(level.get_node("UILayer/UI/Opponent").autoplay,
		"el oponente tiene que ir en autoplay")
	_check(not level.get_node("UILayer/UI/Player").autoplay
			and level.get_node("UILayer/UI/Player").inputs != null,
		"el jugador tiene que tener mapa de entrada y no autoplay")

	# One camera marker per cast member, all direct children of the level root. The chart
	# only uses char 0 and 1, but the format allows 2, and RubiconPositionSetter - if
	# anything ever points at these - reads only target.position: its ancestor walk is
	# inert, because `node is Parallax2D or ParallaxBackground or ParallaxLayer` parses as
	# `(node is Parallax2D) or ParallaxBackground or ...` and a class used as an expression
	# is truthy. A marker under any transform loses it in silence.
	for point_name: String in ["PlayerCameraPoint", "OpponentCameraPoint",
			"GirlfriendCameraPoint"]:
		var point: Node = level.find_child(point_name, true, false)
		_check(point != null and point.get_parent() == level,
			"%s no cuelga de la raiz del nivel" % point_name)

	# TWO sets of camera offsets reach every marker, not one. Stage_obj::applyCharacterData
	# in the mod's own binary adds the STAGE's cameraOffsets on top of the ones the
	# character JSON already gave BaseCharacter_obj::resetCameraFocusPoint. Read here from
	# phoneCallStreet.json rather than from the port, so the port cannot agree with itself:
	# the marker has to sit exactly the stage's offset away from the character's midpoint.
	var stage_data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(STAGE_JSON))
	# node name, marker name, the character JSON's own cameraOffsets, and the height of
	# Funkin's frame (komi's sparrow frame; tadano's measured against the original).
	var cast_points: Array = [
		["bf", "Tadano", "PlayerCameraPoint", Vector2(-250, 100), 1133.0],
		["dad", "Komi", "OpponentCameraPoint", Vector2(-225, 50), 776.0],
		["gf", "KomiGirlfriend", "GirlfriendCameraPoint", Vector2(425, -150), 776.0],
	]
	for row: Array in cast_points:
		var character: Node2D = level.find_child(row[1], true, false)
		var offsets: Array = stage_data["characters"][row[0]]["cameraOffsets"]
		var aimed_at: Vector2 = (character.position
			- Vector2(0.0, float(row[4]) * 0.5)
			+ (row[3] as Vector2)
			+ Vector2(float(offsets[0]), float(offsets[1])))
		var point2d: Node2D = level.get_node(row[2])
		_check(point2d.position.distance_to(aimed_at) < 1.0,
			"%s esta en %s y el JSON del escenario lo pone en %s" % [
				row[2], point2d.position, aimed_at])

	# An instanced Control loses its authored layout twice over: once if layout_mode does
	# not say to keep the anchors - the bar came out 4x27 in the top-left corner before that
	# was set - and once if the saved instance carries an `anchors_preset`, which RE-APPLIES
	# that preset on load and throws the offsets away. The bar is anchored dead centre at
	# the top, which is preset 5, and it came out pinned 45px above its own mark.
	#
	# So this checks the rect it is supposed to have rather than the anchors: the mod's
	# WHITEBAR.png is 728x37 and drawn at 1.5, centred, with its top 45 Funkin pixels down.
	var health_bar: Control = level.get_node("UILayer/UI/HealthBar")
	var bar_rect: Rect2 = health_bar.get_rect()
	_check(bar_rect.size.is_equal_approx(Vector2(728.0, 37.0) * FUNKIN_TO_RUBICON),
		"la barra de vida mide %s y el arte del mod pide %s" % [
			bar_rect.size, Vector2(728.0, 37.0) * FUNKIN_TO_RUBICON])
	_check(is_equal_approx(bar_rect.position.y, 45.0 * FUNKIN_TO_RUBICON),
		"la barra de vida empieza en y=%.1f y la captura la pone en %.1f" % [
			bar_rect.position.y, 45.0 * FUNKIN_TO_RUBICON])

	_check_icons(level)

	# phone-call.script's standUP(): the two standing characters are in the scene from the
	# start, hidden, positioned by setPosition()'s CORNER semantics, and 500 above the
	# phone pair's z.
	for entry: Array in [
			["TadanoStand", Vector2(-175, 325), Vector2(290, 667), "end_animation"],
			["KomiStand", Vector2(300, 325), Vector2(269, 670), "end_conv"]]:
		var character: Node2D = level.find_child(entry[0], true, false)
		_check(character != null, "falta %s" % entry[0])
		if character == null:
			continue
		_check(not character.visible, "%s tendria que empezar oculto" % entry[0])
		_check(character.z_index == 710, "%s tendria que estar a z=710" % entry[0])
		var corner: Vector2 = entry[1]
		var frame: Vector2 = entry[2]
		_check(character.position.is_equal_approx(
				corner + Vector2(frame.x * 0.5, frame.y)),
			"%s esta en %s" % [entry[0], character.position])
		# The animation the chart asks for at 132.2s, and the reason the swap exists.
		_check(character.animation_player.has_animation(StringName(entry[3])),
			"%s no tiene %s" % [entry[0], entry[3]])

	_check(level.get_node("Overlays/White") != null, "falta el destello blanco de standUP()")
	_check(level.get_node("Overlays/Black") != null, "falta el fundido a negro del beat 348")
	# camGame.flash and camGame.fade are on the GAME camera, so they belong above the stage
	# and below the HUD - by the time the fade runs, beat 332 has taken the HUD away anyway.
	_check(level.get_node("Overlays").layer < level.get_node("UILayer").layer,
		"los fundidos tendrian que ir por debajo del HUD")

	var events_node: Node = level.get_node("PhoneCallEvents")
	var stand: Node2D = level.find_child("TadanoStand", true, false)
	_check(stand != null and (stand.get_child(0) as Node2D).scale.x > 0.0,
		"tadano de pie va SIN espejo: su arte ya mira hacia komi, que esta a su derecha")

	_check(events_node.hud_up.size() == 1 and events_node.hud_down.size() == 2,
		"el beat 332 mueve la barra hacia arriba y las dos strumlines hacia abajo")

	_check_stand_up_hands_over(level, events_node)
	_check_opening_lockout(level, events_node)

	_drop(level)


## onCreatePost's `disableKeys = true` and its own barTop/barBottom, both undone at beat 33.
##
## The letterbox is a SECOND pair, not the chart's CinematicBars: the chart animates those
## up from nothing over the first 0.69s and the script's are already there on frame one, a
## hundred Funkin pixels top and bottom. Without them the song opens on a frame the mod
## never shows.
func _check_opening_lockout(level: Node, events_node: Node) -> void:
	var player_lanes: Node = level.get_node("UILayer/UI/Player")
	_check(player_lanes.disable_inputs,
		"las teclas tendrian que estar muertas hasta el beat 33")

	var bars: Node = events_node.script_bars
	_check(bars != null, "falta el letterbox propio del script")
	if bars == null:
		return
	_check(bars.visible, "el letterbox del script tendria que estar puesto desde el frame 1")
	var height: float = 100.0 * FUNKIN_TO_RUBICON
	for bar_name: String in ["Top", "Bottom"]:
		var bar: ColorRect = bars.get_node(bar_name)
		_check(is_equal_approx(bar.size.y, height),
			"la barra %s del script mide %.1f y tendria que medir %.1f"
				% [bar_name, bar.size.y, height])
		_check(is_equal_approx(bar.size.x, 1920.0),
			"la barra %s del script no cubre el ancho" % bar_name)
	_check(is_equal_approx((bars.get_node("Top") as ColorRect).position.y, 0.0),
		"la barra de arriba no esta pegada al borde")
	_check(is_equal_approx((bars.get_node("Bottom") as ColorRect).position.y, 1080.0 - height),
		"la barra de abajo no esta pegada al borde")

	events_node.keys_on()
	_check(not player_lanes.disable_inputs,
		"el beat 33 tendria que devolver las teclas")
	_check(not bars.visible, "el beat 33 mata el letterbox del script")


## standUP() has to hand `level_note_controller` to the standing pair, because that is what
## subscribes a RubiconCharacter to note_changed and to the clock's step_change. They were
## built hidden and never given one, so after the swap neither of them sang a note or took
## another dance step: each played its autoplay `dance_idle` once at load and then stood
## there for the rest of the song.
##
## Called rather than seeked, since the swap is idempotent by design and every other
## harness that reaches this stretch freezes the clock to shoot a frame - which is exactly
## why a still could not show it.
func _check_stand_up_hands_over(level: Node, events_node: Node) -> void:
	var before: Dictionary = {}
	for slot: StringName in events_node.stand_cast:
		var phone: Node = events_node.cast.get(slot)
		_check(phone != null, "el reparto de telefono no tiene %s" % slot)
		if phone == null:
			continue
		before[slot] = phone.get(&"level_note_controller")
		_check(before[slot] != null,
			"%s del telefono no tiene controlador de notas" % slot)
		_check(events_node.stand_cast[slot].get(&"level_note_controller") == null,
			"%s de pie ya trae controlador: tiene que recibirlo en el cambio" % slot)

	events_node.stand_up()

	for slot: StringName in events_node.stand_cast:
		var standing: Node = events_node.stand_cast[slot]
		_check(standing.get(&"level_note_controller") == before.get(slot),
			"%s de pie no recibio el controlador del cambio: " % slot
				+ "no cantaria ni haria idle en toda la segunda mitad")
		_check(events_node.cast.get(slot) == standing,
			"el reparto no quedo apuntando a %s de pie" % slot)


## The chart's camera events, checked by seeking the level to the END of each tween and
## reading what the camera actually holds. Expectations come out of the chart JSON, so
## re-exporting the song moves them; nothing here is a copied number.
func _check_camera_events() -> void:
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART_JSON))
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	# Autoplay, or the player misses every note, the health empties and the DEATH SEQUENCE
	# fires in the middle of the camera walk - it pauses the clock and re-aims the camera at
	# the dying character, and every FocusCamera reading after that drifts. Found exactly
	# that way: the expectations held until 63s and then slid negative together.
	_autoplay(level)
	await process_frame

	var player: AnimationPlayer = level.get_node("RubiconLevelClock/AnimationPlayer")
	var camera: Camera2D = level.get_node("RubiconInterpolatedCamera2D")
	var bumper: Node = level.get_node("RubiconInterpolatedCamera2D/RubiconCameraBumper")
	var top: ColorRect = level.get_node("CinematicBars/Top")
	var stage: Node2D = level.get_node("Stage")
	var base_zoom: float = float(stage.get_meta(&"camera_zoom")) * FUNKIN_TO_RUBICON

	var focus_points: Dictionary = {
		0: level.get_node("PlayerCameraPoint").position,
		1: level.get_node("OpponentCameraPoint").position,
		2: level.get_node("GirlfriendCameraPoint").position,
	}

	# After standUP() the same `char` index means the standing pair, standing somewhere
	# else. Their cameraOffsets are tadano-stand [200, 50] and komi-stand [50, 50], PLUS
	# the stage's own for the slot they are put into - which is the half this check used to
	# leave out, so it agreed with the bug for two rounds instead of catching it.
	#
	# The stage's offsets are read from the JSON here rather than from the markers the
	# builder writes them onto: a check that reads the builder's own output cannot tell a
	# wrong value from a wrong idea.
	#
	# NOT scaled by FUNKIN_TO_RUBICON here either - this check carried the same 1.5 the
	# builder did, that time too. World offsets stay verbatim; the 1.5 lives on the zoom.
	const STAND_UP_TIME := 232.0 * 60.0 / 152.0
	# case 168's `FlxTween.tween(tad, {x: tad.x + 800}, 1.35)`, taken from the events script
	# so the slide and the camera cannot disagree about it.
	var slide_constants: Dictionary = load(
		"res://animania_mod/scripts/phone_call_events_refactored.gd").get_script_constant_map()
	var SLIDE_DISTANCE: float = float(slide_constants["SLIDE_DISTANCE"])
	var SLIDE_DONE_TIME: float = 168.0 * 60.0 / 152.0 \
		+ float(slide_constants["SLIDE_SECONDS"])
	_check(is_equal_approx(SLIDE_DISTANCE, 800.0),
		"el deslizamiento del beat 168 son 800px en el script")
	var stage_json: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(STAGE_JSON))
	var stage_camera_offsets: Dictionary = {}
	# phoneCallStreet.json spells the slots bf/dad/gf.
	for slot: String in ["bf", "dad"]:
		var declared: Array = (stage_json.get("characters", {}) as Dictionary) \
			.get(slot, {}).get("cameraOffsets", [0, 0])
		stage_camera_offsets[slot] = Vector2(float(declared[0]), float(declared[1]))
	_check(stage_camera_offsets["bf"].is_equal_approx(Vector2(-80.0, -150.0))
			and stage_camera_offsets["dad"].is_equal_approx(Vector2(-300.0, -150.0)),
		"phoneCallStreet.json ya no declara los cameraOffsets que este check espera")

	var stand_points: Dictionary = {}
	for entry: Array in [
			[0, "TadanoStand", Vector2(290, 667), Vector2(200, 50), "bf"],
			[1, "KomiStand", Vector2(269, 670), Vector2(50, 50), "dad"]]:
		var character: Node2D = level.find_child(entry[1], true, false)
		stand_points[entry[0]] = (character.position
			- Vector2(0.0, (entry[2] as Vector2).y * 0.5)
			+ (entry[3] as Vector2)
			+ (stage_camera_offsets[entry[4]] as Vector2))

	# The letterbox has to leave the notes alone: Rubicon anchors its strumlines to the
	# BOTTOM, unlike Funkin, and the chart asks for 120px bars while notes are arriving.
	_check(level.get_node("CinematicBars").layer < level.get_node("UILayer").layer,
		"las barras tapan el HUD")

	# The chart's two character events, checked before the seeking starts: PlayAnimation
	# names an animation on a named character, and a name that does not exist is a warning
	# at runtime and nothing on screen.
	var events: Node = level.get_node("PhoneCallEvents")
	for name: StringName in [&"boyfriend", &"bf", &"dad", &"gf"]:
		_check(events.cast.has(name) and events.cast[name] != null,
			"el reparto de eventos no tiene %s" % name)

	# endAnimation and endConv live on the tadano-stand / komi-stand characters the song
	# swaps in at 132.2s, and that swap is not ported. Every OTHER PlayAnimation has to
	# resolve.
	const UNPORTED: Array = ["endAnimation", "endConv"]
	for event: Dictionary in chart["events"]:
		if String(event["e"]) != "PlayAnimation":
			continue
		var animation: String = str(event["v"].get("anim", ""))
		if animation in UNPORTED:
			continue
		var character: Node = events.cast.get(StringName(str(event["v"].get("target", ""))))
		_check(character != null
				and character.animation_player.has_animation(StringName(animation)),
			"PlayAnimation pide %s en %s y no existe" % [animation, event["v"].get("target")])

	# SetProperty <char>.idleSuffix remaps every animation by appending the suffix, so each
	# one the rule will reach has to exist under its suffixed name.
	for event: Dictionary in chart["events"]:
		if String(event["e"]) != "SetProperty":
			continue
		var property: String = str(event["v"].get("target", ""))
		_check(property.ends_with(".idleSuffix"),
			"SetProperty sin traducir: %s" % property)
		var suffix: String = str(event["v"].get("value", "")).replace("-", "_")
		var character: Node = events.cast.get(StringName(property.get_slice(".", 0)))
		_check(character != null, "SetProperty nombra a %s" % property.get_slice(".", 0))
		if character == null:
			continue
		for alias: StringName in character.animations:
			var suffixed := StringName("%s%s" % [character.animations[alias], suffix])
			_check(character.animation_player.has_animation(suffixed),
				"a %s le falta %s" % [property.get_slice(".", 0), suffixed])
		for dancing: StringName in character.dancing_animations:
			_check(character.animation_player.has_animation(
					StringName("%s%s" % [dancing, suffix])),
				"a %s le falta %s%s" % [property.get_slice(".", 0), dancing, suffix])

	var handled: Dictionary = {
		"FocusCamera": 0, "ZoomCamera": 0, "AddCameraZoom": 0,
		"SetCameraBop": 0, "CinematicBars": 0,
	}

	# When does the next event of each kind land? Funkin cancels a running tween when a new
	# one starts on the same property, so an event whose tween is cut short never reaches
	# its target and there is nothing to assert about its end - only the ones that finish
	# are checked. `truncated` counts the rest so the totals below still add up.
	var next_of_kind: Dictionary = {}
	var last_seen: Dictionary = {}
	var chart_events: Array = chart["events"]
	for i: int in range(chart_events.size() - 1, -1, -1):
		var kind_at: String = chart_events[i]["e"]
		next_of_kind[i] = float(last_seen.get(kind_at, INF))
		last_seen[kind_at] = float(chart_events[i]["t"]) / 1000.0

	var truncated: int = 0

	# In chart order, so the method tracks fire the way they would while playing.
	for index: int in chart_events.size():
		var event: Dictionary = chart_events[index]
		var kind: String = event["e"]
		if not handled.has(kind):
			continue
		handled[kind] = int(handled[kind]) + 1

		var value: Dictionary = event["v"]
		var time: float = float(event["t"]) / 1000.0
		# Seek past the end of the tween, so what is read is the value it settles on.
		var duration: float = 0.0
		match kind:
			"FocusCamera", "ZoomCamera":
				duration = float(value.get("duration", 4)) * STEP_SECONDS
			"CinematicBars":
				duration = maxf(float(value.get("upTime", 0.5)),
					float(value.get("downTime", 0.5)))

		# Cut short by the next event of its kind, or by the end of the song.
		var cutoff: float = minf(float(next_of_kind[index]),
			player.get_animation(&"scene").length)
		if time + duration > cutoff:
			truncated += 1
			continue

		# Land inside the flat stretch between the end of this tween and the pin that holds
		# it until the next event - not past the pin, which is already the next tween.
		var settled: float = clampf(time + duration + 0.001,
			time + duration, cutoff - 0.006)
		player.seek(minf(settled, player.get_animation(&"scene").length), true)
		await process_frame

		match kind:
			"FocusCamera":
				var character: int = int(value.get("char", 0))
				var points: Dictionary = stand_points \
					if time >= STAND_UP_TIME and stand_points.has(character) \
					else focus_points
				# NOT scaled by FUNKIN_TO_RUBICON. The event's x/y are world offsets in
				# Funkin pixels and this port keeps world coordinates verbatim; the 1.5
				# lives on the camera's zoom. This check carried the same 1.5 the baker
				# did, so it agreed with the bug instead of catching it.
				var expected: Vector2 = points[character] + Vector2(
					float(value.get("x", 0)), float(value.get("y", 0)))
				# case 168 slides tadano 800px right and leaves him there until standUP.
				# Funkin never notices - its focus is the character's LIVE position plus the
				# event's offset - but a baked point is where he stood at build time. The
				# only `char=0` focus between the slide and the swap is at 83.68s with x=0,
				# and baked without this it aimed at x=-280: the empty street he used to
				# stand on, with him 800px off the right of the frame. This check had the
				# same blind spot, so it passed the whole time.
				#
				# From the moment the tween FINISHES, not from its beat: the event on the
				# slide's own beat carries x=700 and fires while he has not moved yet.
				if character == 0 and time >= SLIDE_DONE_TIME and time < STAND_UP_TIME:
					expected.x += SLIDE_DISTANCE
				_check(camera.position_interpolate_target.distance_to(expected) < 1.0,
					"FocusCamera en %.1fs apunta a %s y esperaba %s" % [
						time, camera.position_interpolate_target, expected])

			"ZoomCamera":
				var expected_zoom: float = base_zoom * float(value.get("zoom", 1.0))
				_check(absf(camera.zoom_interpolate_target.x - expected_zoom) < 0.002,
					"ZoomCamera en %.1fs deja %.4f y esperaba %.4f" % [
						time, camera.zoom_interpolate_target.x, expected_zoom])

			"SetCameraBop":
				# intensity is a multiplier on Funkin's default per-bop game zoom.
				var intensity: float = float(value.get("intensity", 1.0))
				_check(absf(bumper.bump_amount - 0.015 * intensity) < 0.0001,
					"SetCameraBop en %.1fs deja %.5f y esperaba %.5f" % [
						time, bumper.bump_amount, 0.015 * intensity])
				_check(bumper.enabled == (intensity > 0.0),
					"SetCameraBop en %.1fs no encendio/apago el bop" % time)
				_check(bumper.bump_interval == int(value.get("rate", 4)),
					"SetCameraBop en %.1fs deja rate %d" % [time, bumper.bump_interval])

			"CinematicBars":
				var expected_height: float = float(value.get("upY", 0)) * FUNKIN_TO_RUBICON
				_check(absf(top.size.y - expected_height) < 2.0,
					"CinematicBars en %.1fs deja %.0fpx y esperaba %.0fpx" % [
						time, top.size.y, expected_height])

	# Every camera event in the chart has to have been reached, not just the ones that
	# happened to be checked - a match that silently skips a kind is the failure mode.
	var totals: Dictionary = {}
	for event: Dictionary in chart["events"]:
		totals[event["e"]] = int(totals.get(event["e"], 0)) + 1
	for kind: String in handled:
		_check(int(handled[kind]) == int(totals.get(kind, 0)),
			"%s: comprobados %d de %d" % [kind, handled[kind], totals.get(kind, 0)])
	print("eventos de camara: %d recorridos, %d con el tween cortado por el siguiente"
		% [chart_events.size(), truncated])

	_drop(level)

	# The idleSuffix switch, checked where it lands rather than only that it could - on a
	# FRESH level. Method-track keys fire for the range a seek crosses going forward, and
	# the loop above has already walked to the end of the song; seeking back to 60 and
	# forward again does not re-fire what it passed on the way back.
	await _check_idle_suffix()
	await _check_stand_up()
	await _check_script_beats()
	await _check_opening()
	await _check_pulse()
	await _check_icon_bop()
	await _check_icons_follow_health()
	await _check_opponent_sustain_glow()
	await _check_subtitles()
	await _check_death()


## phone-call.script's opening: onCreatePost plus cases 0, 1, 11, 13, 31, 166 and 168.## phone-call.script's opening: onCreatePost plus cases 0, 1, 11, 13, 31, 166 and 168.
##
## All of it fails silently in the same way. The song still plays with its HUD already up,
## its title card never shown and both strumlines on the wrong sides - which is exactly what
## this port did until the script was read.
##
## Tweens run on real time, not on the clock, so each phase winds the clock to just before a
## beat and then lets frames actually pass. That also means the clock keeps playing through
## the settle, which is the point: the keys fire the way they do in a playthrough.
func _check_opening() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var clock: AnimationPlayer = level.get_node("RubiconLevelClock").animation_player
	var cover: ColorRect = level.get_node("Stage/ScreenSpace/IntroCover")
	var intro: AnimatedSprite2D = level.get_node("Stage/ScreenSpace/IntroText")
	var hud: Control = level.get_node("UILayer/UI")
	var player_lanes: Control = level.get_node("UILayer/UI/Player")
	var opponent_lanes: Control = level.get_node("UILayer/UI/Opponent")
	var tadano: Node2D = level.find_child("Tadano", true, false)
	var home_x: float = tadano.position.x

	# Where each side of the HUD was authored, read off the anchors rather than written
	# down: moving a Control's position moves its offsets, so the anchors still say where
	# it started.
	var opponent_home: float = opponent_lanes.anchor_left * 1920.0
	var player_home: float = player_lanes.anchor_left * 1920.0

	# onCreatePost, and case 0.
	_check(is_equal_approx(cover.color.a, 1.0),
		"la pantalla no empieza en negro (alpha %.2f)" % cover.color.a)
	_check(is_zero_approx(hud.modulate.a), "el HUD no empieza invisible")
	# The sides do NOT swap - an earlier version of this port read them as swapping and a
	# device run showed the player's lanes sitting on komi's side.
	# The sides DO swap: tadano's lanes on the left, komi's on the right. The first attempt
	# at this was reverted because the two charts were crossed and it read as the sides
	# being wrong; with the charts uncrossed, the swap is right.
	_check(is_equal_approx(player_lanes.position.x, opponent_home),
		"las notas del jugador tendrian que ir a la casa del oponente (%.0f, no %.0f)"
			% [opponent_home, player_lanes.position.x])
	_check(is_equal_approx(opponent_lanes.position.x, opponent_home + 1920.0),
		"las notas del oponente tendrian que empezar fuera de pantalla (%.0f)"
			% opponent_lanes.position.x)
	_check(is_zero_approx(opponent_lanes.modulate.a) and
		is_equal_approx(opponent_lanes.rotation_degrees, 360.0),
		"las notas del oponente tendrian que empezar invisibles y giradas")

	# case 1: the title card.
	await _wind_to(clock, 2.0)
	await _settle(0.4)
	_check(intro.visible and intro.modulate.a > 0.05,
		"el cartel del intro no aparece en el beat 1 (visible=%s alpha=%.2f)"
			% [intro.visible, intro.modulate.a])

	# case 13: the cover comes off and tadano walks in. Two and a half seconds of fade and
	# 1.95s of walk, so this is the phase that needs real time.
	await _wind_to(clock, 5.0)
	await _settle(2.8)
	_check(cover.color.a < 0.05,
		"el negro tendria que haberse ido en el beat 13 (alpha %.2f)" % cover.color.a)
	_check(intro.modulate.a < 0.05,
		"el cartel tendria que haberse ido en el beat 11 (alpha %.2f)" % intro.modulate.a)
	_check(absf(tadano.position.x - home_x) < 2.0,
		"tadano tendria que acabar su entrada en su sitio (%.0f, no %.0f)"
			% [home_x, tadano.position.x])

	# case 31: the HUD arrives with the player's lanes, and only theirs.
	await _wind_to(clock, 12.0)
	await _settle(0.9)
	_check(absf(hud.modulate.a - 1.0) < 0.01,
		"el HUD tendria que entrar en el beat 31 (alpha %.3f)" % hud.modulate.a)
	_check(absf(player_lanes.modulate.a - 1.0) < 0.01,
		"las notas del jugador tendrian que entrar con el HUD (alpha %.3f)"
			% player_lanes.modulate.a)
	_check(is_zero_approx(opponent_lanes.modulate.a),
		"las del oponente no, que faltan 135 beats (alpha %.2f)"
			% opponent_lanes.modulate.a)

	# cases 166 and 168: the opponent's lanes fly in - two seconds of delay and 1.35s of
	# tween - and tadano slides 800 right on the way.
	# Two seconds of delay plus 1.35s of tween, and the key itself does not fire until the
	# clock plays past 65.526 - so 3.35s of settle is a hair short and lands on a cubic
	# ease-out at 99%, which reads as 0.0 rotation in a printout and is not zero.
	await _wind_to(clock, 65.0)
	await _settle(4.6)
	_check(absf(opponent_lanes.position.x - player_home) < 2.0,
		"las notas del oponente tendrian que aterrizar en la casa del jugador (%.0f, no %.0f)"
			% [player_home, opponent_lanes.position.x])
	_check(absf(opponent_lanes.rotation_degrees) < 0.01,
		"tendrian que acabar sin girar (%.3f)" % opponent_lanes.rotation_degrees)
	_check(absf(opponent_lanes.modulate.a - 0.5) < 0.01,
		"tendrian que aterrizar a medio alpha (%.3f)" % opponent_lanes.modulate.a)
	_check(tadano.position.x - home_x > 700.0,
		"tadano tendria que deslizarse 800 en el beat 168 (%.0f)"
			% (tadano.position.x - home_x))

	# case 232 finishes them off, riding on stand_up so the two keys do not collapse.
	await _wind_to(clock, 91.0)
	await _settle(2.4)
	_check(absf(opponent_lanes.modulate.a - 1.0) < 0.01,
		"el beat 232 tendria que acabar de traer las notas del oponente (%.3f)"
			% opponent_lanes.modulate.a)

	_drop(level)
	await process_frame


## The subtitles: the parser against the file, and then the display against the parser.
##
## Nothing here writes a timing down - the expectations come out of the same .srt the game
## reads, so re-cutting the subtitles moves the guard with them.
func _check_subtitles() -> void:
	var source: String = FileAccess.get_file_as_string(SUBTITLES)
	var subtitles: GDScript = load("res://animania_mod/scripts/song_subtitles.gd")
	var cues: Array = subtitles.parse(source)

	# One cue per `-->` in the file, and not one more: a BOM or a stray blank line eating a
	# block is exactly the kind of thing that fails quietly.
	var arrows: int = 0
	for line: String in source.split("\n"):
		if line.contains("-->"):
			arrows += 1
	_check(cues.size() == arrows,
		"se parsearon %d subtitulos de %d" % [cues.size(), arrows])
	if cues.is_empty():
		return

	var ordered: bool = true
	for i: int in cues.size():
		var cue: Dictionary = cues[i]
		if float(cue["from"]) >= float(cue["to"]):
			ordered = false
		if i > 0 and float(cue["from"]) < float((cues[i - 1] as Dictionary)["from"]):
			ordered = false
		if String(cue["text"]).is_empty() or String(cue["text"]).contains("{font"):
			_check(false, "el subtitulo %d no se convirtio a BBCode" % i)
	_check(ordered, "los subtitulos no van en orden")

	# And the display, driven off the clock like the rest of the song.
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var clock: AnimationPlayer = level.get_node("RubiconLevelClock").animation_player
	var line: RichTextLabel = level.get_node("Subtitles/Line")

	_check(line.text.is_empty(), "el primer frame no tendria que tener subtitulo")

	# Halfway into the first cue, and then into the gap that follows it.
	var first: Dictionary = cues[0]
	await _wind_to(clock, (float(first["from"]) + float(first["to"])) * 0.5)
	_check(not line.text.is_empty(),
		"tendria que haber subtitulo en %.2fs" % clock.current_animation_position)

	var gap: float = float(first["to"])
	for cue: Dictionary in cues:
		if float(cue["from"]) > gap + 2.0:
			gap = (gap + float(cue["from"])) * 0.5
			break
	await _wind_to(clock, gap)
	_check(line.text.is_empty(),
		"no tendria que haber subtitulo en %.2fs: %s" % [gap, line.text])

	_drop(level)
	await process_frame


## onBeatHit's tail: every even beat after 232 both strumlines snap to 1.05 and ease back,
## the opponent's onto 1.0 and the player's onto 0.95 - MULTIPLIED by the base scale each
## strumline already carries from onCreatePost's changeMode, 1.05 for the player and 0.95
## for the opponent.
##
## Those bases are the reason the numbers here are products rather than the script's bare
## constants. `Modchart.set("scale", ...)` is a modifier stacked on the strumline, not an
## assignment to it, and changeMode's second argument is a scale: Strumline::changeMode
## (Null<Bool>, Null<Float>, Dynamic) hands the bool to set_miniMode and the float to the
## receptor group before calling refreshReceptorLayout. This port used to write the pulse
## absolutely over a base of 1.0, which made both fields the same size on the beat.
##
## Sampled over a couple of real seconds rather than caught on one frame: the snap lasts a
## single frame and the ease lasts a beat, so what is checked is the range the scale covers
## and the fact that before beat 232 it does not move off its base at all.
## komi's receptors have to stay lit for as long as a sustain lasts, not just on the tap.
##
## The clear that resets an autoplayed lane reads the note BEHIND note_hit_index, and that
## index does not advance while a hold is live - so mid-hold it read the note before the
## sustain, saw a completed hit, and cleared. Her lane went dark one frame after the hold
## began. The window here contains a 592ms sustain on her `right` lane at 28.03s.
##
## Measured over real seconds: lane_state is a value that lives for a frame at a time, and
## nothing about a still says how long it held.
func _check_opponent_sustain_glow() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var clock: AnimationPlayer = level.get_node("RubiconLevelClock").animation_player
	await _wind_to(clock, 27.6)

	var lanes: Array[Node] = []
	for lane: Node in level.get_node("UILayer/UI/Opponent").get_children():
		if lane.has_method(&"get_mode_id"):
			lanes.append(lane)
	_check(lanes.size() == 4, "el oponente no tiene cuatro carriles")

	var longest: float = 0.0
	var current: float = 0.0
	var elapsed: float = 0.0
	while elapsed < 1.6:
		var lit: bool = false
		for lane: Node in lanes:
			# LANE_STATE_HIT is 2; PUSH is 1 and NEUTRAL is 0.
			lit = lit or int(lane.lane_state) == 2
		current = current + root.get_process_delta_time() if lit else 0.0
		longest = maxf(longest, current)
		elapsed += root.get_process_delta_time()
		await process_frame

	# A tap's linger is one frame. Anything past a fifth of a second is a hold being held.
	_check(longest > 0.25,
		"los carriles de komi solo se encienden %.0fms seguidos: no aguantan el sostenido"
			% (longest * 1000.0))

	_drop(level)
	await process_frame


## The icons ride the fill's SEAM, which is what `healthBar.centerPoint` is - FlxBar's
## centre point is where the boundary currently sits, not the bar's geometric middle.
##
## A round of this port read it as a fixed middle and parked both icons on a follow point at
## progress_ratio 0.5, which is not even the middle of this curve: they ended up bunched at
## the left END of the arc and stopped answering the health at all. The guard had nothing to
## say about it, which is why it shipped. This is that check.
func _check_icons_follow_health() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	await process_frame

	var health: Node = level.get_node("RubiconHealthModule")
	var bar: Control = level.get_node("UILayer/UI/HealthBar")
	var seen: Dictionary[String, Array] = {"IconL": [], "IconR": []}
	for value: float in [15.0, 50.0, 85.0]:
		health.health = value
		await process_frame
		await process_frame
		for icon_name: String in seen:
			(seen[icon_name] as Array).append(
				(bar.find_child(icon_name, true, false) as Node2D).global_position.x)

	for icon_name: String in seen:
		var xs: Array = seen[icon_name]
		_check(float(xs[0]) < float(xs[1]) and float(xs[1]) < float(xs[2]),
			"%s no sigue la vida: x = %.0f, %.0f, %.0f al 15, 50 y 85%%"
				% [icon_name, xs[0], xs[1], xs[2]])
		# A bar 728 Funkin pixels wide travels 1092 of this project's, so a seventy percent
		# swing is most of it. Catches an icon that merely wobbles.
		_check(float(xs[2]) - float(xs[0]) > 500.0,
			"%s se mueve solo %.0fpx entre el 15%% y el 85%%"
				% [icon_name, float(xs[2]) - float(xs[0])])

	# And the seam has to be under them: the player's half grows RIGHTWARD with his health,
	# so a bar that shrank it would put the icons on the wrong colour.
	var widths: Array[float] = []
	for value: float in [15.0, 85.0]:
		health.health = value
		await process_frame
		await process_frame
		widths.append((bar.get_node("Art/PlayerFill") as Sprite2D).region_rect.size.x)
	_check(widths[1] > widths[0],
		"la mitad del jugador tendria que crecer con su vida (%.0f -> %.0f)"
			% [widths[0], widths[1]])

	_drop(level)
	await process_frame


## onCreatePost's `for (c in [iconP1, iconP2]) c.bopEvery = 4 * 4;`.
##
## bopEvery counts STEPS - the method it feeds is HealthIcon.onStepHit(Int) - so sixteen of
## them is one bar at 4/4, a pulse once a measure rather than the every-beat one stock
## Funkin does. BOP_SCALE is 0.2, read out of HealthIcon's __boot.
##
## Watched over real seconds rather than asserted on a still: a frozen icon and a bopping
## one are the same picture on any single frame, which is how the health bar shipped stuck
## at 50% for a whole song.
func _check_icon_bop() -> void:
	var constants: Dictionary = load(
		"res://animania_mod/scripts/animated_health_icon.gd").get_script_constant_map()
	_check(int(constants["BOP_EVERY_STEPS"]) == 16,
		"bopEvery es 4 * 4 PASOS, un compas")
	_check(is_equal_approx(float(constants["BOP_SCALE"]), 0.2),
		"BOP_SCALE es 0.2 en el __boot de HealthIcon")

	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var bar: Node = level.get_node("UILayer/UI/HealthBar")
	for icon_name: String in ["IconL", "IconR"]:
		var icon: Node2D = bar.find_child(icon_name, true, false)
		_check(icon != null and icon.get(&"clock") != null,
			"%s no tiene reloj: no puede latir" % icon_name)

	# A bar at 152bpm is 1.58s, so two and a half seconds always contain one bop.
	var seen: Dictionary[String, float] = {}
	for icon_name: String in ["IconL", "IconR"]:
		seen[icon_name] = 0.0
	var elapsed: float = 0.0
	while elapsed < 2.5:
		for icon_name: String in ["IconL", "IconR"]:
			var icon: Node2D = bar.find_child(icon_name, true, false)
			seen[icon_name] = maxf(seen[icon_name], absf(icon.scale.y))
		elapsed += root.get_process_delta_time()
		await process_frame

	for icon_name: String in ["IconL", "IconR"]:
		var icon: Node2D = bar.find_child(icon_name, true, false)
		var rest: float = ICON_HEIGHT / float(
			(icon.sprite_frames as SpriteFrames).get_frame_texture(&"idle", 0).get_height())
		_check(seen[icon_name] > rest * 1.1,
			"%s no late: su escala nunca pasa de %.3f y el bop la lleva a %.3f"
				% [icon_name, seen[icon_name], rest * (1.0 + 0.2)])

	_drop(level)
	await process_frame


func _check_pulse() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var clock: AnimationPlayer = level.get_node("RubiconLevelClock").animation_player
	var lanes: Dictionary[String, Control] = {
		"jugador": level.get_node("UILayer/UI/Player"),
		"oponente": level.get_node("UILayer/UI/Opponent"),
	}

	var bases: Dictionary[String, float] = {"jugador": 1.05, "oponente": 0.95}

	# Beat 232 is 91.6s. Well before it, nothing moves off the base.
	await _wind_to(clock, 78.0)
	for side: String in lanes:
		var base: float = bases[side]
		var quiet: Vector2 = await _scale_range(lanes[side], 1.2)
		_check(absf(quiet.x - base) < 0.001 and absf(quiet.y - base) < 0.001,
			"las notas del %s no tendrian que latir antes del beat 232, y su base es %.2f (%.3f..%.3f)"
				% [side, base, quiet.x, quiet.y])

	# Two even beats fit in 1.6s at 152bpm, so this catches the snap and both landings.
	await _wind_to(clock, 93.0)
	var beaten: Dictionary[String, Vector2] = {}
	for side: String in lanes:
		beaten[side] = await _scale_range(lanes[side], 1.6)

	for side: String in lanes:
		var top: float = bases[side] * 1.05
		_check((beaten[side] as Vector2).y > top - 0.01,
			"las notas del %s tendrian que saltar a %.4f (maximo %.3f)"
				% [side, top, (beaten[side] as Vector2).y])
	# The player lands on 0.95 of its 1.05 base, the opponent on 1.0 of its 0.95 one - so
	# the player's field breathes and the opponent's punches down onto its own rest.
	_check((beaten["jugador"] as Vector2).x < 1.05 * 0.95 + 0.01,
		"las del jugador tendrian que caer a %.4f (minimo %.3f)"
			% [1.05 * 0.95, (beaten["jugador"] as Vector2).x])
	_check((beaten["oponente"] as Vector2).x > 0.95 - 0.01,
		"las del oponente tendrian que quedarse en %.2f (minimo %.3f)"
			% [0.95, (beaten["oponente"] as Vector2).x])

	_drop(level)
	await process_frame


## The smallest and largest x scale a node takes over a stretch of real time.
func _scale_range(node: Control, seconds: float) -> Vector2:
	var range_seen := Vector2(INF, -INF)
	var elapsed: float = 0.0
	while elapsed < seconds:
		range_seen.x = minf(range_seen.x, node.scale.x)
		range_seen.y = maxf(range_seen.y, node.scale.x)
		elapsed += root.get_process_delta_time()
		await process_frame
	return range_seen


## Lets real time pass, which is what every tween in the opening and the death runs on.
func _settle(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		elapsed += root.get_process_delta_time()
		await process_frame


## Tadano's death sequence. Rubicon emits health_depleted and nothing in the engine listens,
## so every piece of this is new - and it cannot be reached by seeking, only by dropping the
## health and letting the tweens run.
func _check_death() -> void:
	# The standing form settles inside a couple of seconds. The phone one cannot: its retry
	# text and its camera slide both hang off deathLoop, which Funkin only plays when
	# firstDeath ends - four seconds of dying later, plus the quarter second `start` runs.
	const DEATH_SETTLE := 2.5
	const PHONE_DEATH_SETTLE := 5.0
	## Comfortably inside firstDeath, so deathLoop demonstrably has not happened yet.
	const MID_DEATH := 1.5

	for standing: bool in [false, true]:
		var level: Node = load(LEVEL).instantiate()
		root.add_child(level)
		await process_frame

		var sequence: Node = level.get_node("DeathSequence")
		var clock: Node = level.get_node("RubiconLevelClock")
		var camera: Camera2D = level.get_node("RubiconInterpolatedCamera2D")
		var form: String = "de pie" if standing else "por telefono"

		if standing:
			level.get_node("PhoneCallEvents").stand_up()
		level.get_node("RubiconHealthModule").health = 0.0

		# health_depleted is emitted from the setter, so the camera is aimed and the wash is
		# at its opening value by the time the assignment returns. Anything that moves after
		# this is deathLoop's, not the aim's.
		var aimed_x: float = camera.position_interpolate_target.x
		var dark: ColorRect = level.get_node("Death/Dark")
		var retry_text: Node2D = level.find_child("RetryText", true, false)
		# setupDeath opens dark and lightens; createDeathSprites fades one up from nothing.
		_check(dark.color.a > 0.8 if not standing else dark.color.a < 0.1,
			"%s: el oscurecido empieza en %.2f" % [form, dark.color.a])

		var elapsed: float = 0.0
		while elapsed < MID_DEATH:
			elapsed += root.get_process_delta_time()
			await process_frame

		# Mid-firstDeath: the phone form's text is still unread and its camera has not
		# moved off the aim. This is the whole difference between the two forms.
		if not standing:
			_check(is_zero_approx(retry_text.modulate.a),
				"por telefono: el cartel no tendria que verse antes de deathLoop")
			_check(is_equal_approx(camera.position_interpolate_target.x, aimed_x),
				"por telefono: la camara no tendria que deslizarse antes de deathLoop")

		var settle: float = DEATH_SETTLE if standing else PHONE_DEATH_SETTLE
		while elapsed < settle:
			elapsed += root.get_process_delta_time()
			await process_frame

		# deathLoop slides the camera 450 left, and only in the phone form - tadano-stand.hx
		# returns on that animation without touching the camera.
		if standing:
			_check(is_equal_approx(camera.position_interpolate_target.x, aimed_x),
				"de pie: la camara no tendria que deslizarse")
		else:
			_check(aimed_x - camera.position_interpolate_target.x > 100.0,
				"por telefono: la camara no se deslizo (%.1f -> %.1f)" % [
					aimed_x, camera.position_interpolate_target.x])

		# The clock has to stop, and not as a nicety: its baked animation writes
		# position_interpolate_target every frame, so a death camera aimed at the dying
		# character is overwritten by the song's next FocusCamera key before it is drawn.
		_check(not clock.animation_player.is_playing(),
			"%s: el reloj tendria que pararse al morir" % form)

		_check(is_equal_approx(dark.color.a, 0.75),
			"%s: el oscurecido acabo en %.2f" % [form, dark.color.a])

		# start hands over to loop, and loop is where it waits for a retry.
		var retry: AnimationPlayer = level.find_child("RetryText", true, false).get_node(
			"AnimationPlayer")
		_check(retry.current_animation == &"loop",
			"%s: el cartel de reintento esta en %s" % [form, retry.current_animation])

		# The panels are createDeathSprites', which only the standing form runs.
		_check(level.get_node("Death/LeftPanel").visible == standing,
			"%s: los paneles negros" % form)

		# GameOverSubState re-aims at the dying character; it does not inherit wherever the
		# song left the camera.
		var player: Node2D = level.find_child(
			"TadanoStand" if standing else "Tadano", true, false)
		_check(player.animation_player.current_animation in [&"first_death", &"death_loop"],
			"%s: tadano esta en %s" % [form, player.animation_player.current_animation])
		_check(absf(camera.position_interpolate_target.y - (player.position.y
				- _death_height(standing) * 0.5)) < 200.0,
			"%s: la camara no apunta al que muere: %s" % [
				form, camera.position_interpolate_target])

		if standing:
			var opponent: Node2D = level.find_child("KomiStand", true, false)
			_check(opponent.animation_player.current_animation == &"game_over",
				"de pie: komi tendria que estar en game_over")
			# komi-stand.json declares gameOver-loop as frames 6..10 of the same prefix,
			# looped, and Funkin hands over to it when gameOver ends. Without it built she
			# froze on her last frame.
			_check(opponent.animation_player.has_animation(&"game_over_loop"),
				"de pie: a komi le falta game_over_loop")
			var komi_loop: Animation = opponent.animation_player.get_animation(
				&"game_over_loop")
			_check(komi_loop.loop_mode == Animation.LOOP_LINEAR,
				"de pie: game_over_loop de komi no hace bucle")
			# Five ATLAS frames at 24fps. The importer dedups komigameover from 100 frames
			# to 50 held for two each, so taking 6..10 against the imported list gives the
			# wrong pictures AND twice the length - which is what it did at first.
			_check(is_equal_approx(komi_loop.length, 5.0 / 24.0),
				"de pie: game_over_loop de komi dura %.3fs y son 5 cuadros a 24fps"
					% komi_loop.length)

		# The lane hitboxes are not part of the HUD the death sends away, and while they
		# are up they eat the tap that retries - so the death hides them.
		_check(not level.get_node("MobileControls").visible,
			"%s: los hitboxes tendrian que esconderse al morir" % form)

		# deathConfirm is NOT the same in the two forms, and this port ran the standing
		# one's numbers for both. Only tadano-stand.hx slides the panels and drops the
		# black curtain; tadano.hx just raises the camera, on its own delay and ease.
		var gradient: Control = level.get_node("Death/Gradient")
		var panel_at: float = level.get_node("Death/LeftPanel").position.x
		_check(not gradient.visible, "%s: la cortina no tendria que verse aun" % form)
		sequence.confirm()
		await process_frame
		_check(gradient.visible == standing,
			"%s: la cortina se ve %s" % [form, gradient.visible])
		if standing:
			_check(is_equal_approx(gradient.position.y, -2160.0),
				"de pie: la cortina empieza en %.0f" % gradient.position.y)
			_check(is_equal_approx(gradient.size.y, 1080.0 * 2.25),
				"de pie: la cortina mide %.0f de alto" % gradient.size.y)
		else:
			_check(is_equal_approx(
					level.get_node("Death/LeftPanel").position.x, panel_at),
				"al telefono los paneles no tendrian que moverse")

		# Retrying is the port's own: the mod goes back through a StickerSubState and there
		# is none here. What is the mod's is the wait - each form's confirm delay plus the
		# 3.5s its tweens run.
		_check(is_equal_approx(sequence.retry_seconds(standing),
				(0.2 if standing else 0.8) + 3.5),
			"%s: el reintento espera %.2fs" % [form, sequence.retry_seconds(standing)])

		_drop(level)
		await process_frame

	# The retry text is driven by FRAME LABELS on the main timeline, not by symbols -
	# gdanimate plays symbols and a label is invisible to it, so these are built by keying
	# `frame` over each label's range.
	for basename: String in ["tadano_death_text", "tadano_stand_death_text"]:
		var library: AnimationLibrary = load(
			"res://animania_mod/characters/%s_library.tres" % basename)
		for label: String in ["start", "loop", "confirm"]:
			_check(library.has_animation(label), "a %s le falta %s" % [basename, label])
		_check(library.get_animation(&"loop").loop_mode == Animation.LOOP_LINEAR,
			"%s: loop tendria que hacer bucle" % basename)

	var death_constants: Dictionary = load(
		"res://animania_mod/scripts/death_sequence.gd").get_script_constant_map()
	_check(is_equal_approx(float(death_constants["DARK_ALPHA"]), 0.75),
		"el alpha del oscurecido no es el del .hx")
	_check(is_equal_approx(float(death_constants["DEATH_BPM"]), 112.0),
		"Conductor.forceBPM(112)")


## What each form is measured at - see tools/animania/harness/measure_character.gd for the
## phone form and tadano-stand.xml's idle frame for the standing one.
func _death_height(standing: bool) -> float:
	return 667.0 if standing else 833.0


## phone-call.script's onBeatHit, the three moments that are not the character swap. Walked
## to and then PLAYED through, because all three are tweens that need real time.
func _check_script_beats() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var player: AnimationPlayer = level.get_node("RubiconLevelClock/AnimationPlayer")
	var camera: Camera2D = level.get_node("RubiconInterpolatedCamera2D")
	var bar: Control = level.get_node("UILayer/UI/HealthBar")
	var strumline: Control = level.get_node("UILayer/UI/Player")
	var black: ColorRect = level.get_node("Overlays/Black")

	var bar_start: float = bar.position.y
	var strumline_start: float = strumline.position.y

	# beat 16 = 6.32s: camGame.shake(.0005, .8). Flixel's intensity is a fraction of the
	# camera's size, so this is under a pixel at 1920 wide - a rumble, not a jolt.
	await _wind_to(player, 6.0)
	var shaken: float = 0.0
	while player.current_animation_position < 6.9:
		shaken = maxf(shaken, camera.position_interpolate_offset.length())
		await process_frame
	_check(shaken > 0.0 and shaken < 3.0,
		"la sacudida del beat 16 fue de %.2f px" % shaken)

	# And it has to stop: the shake rides on position_interpolate_offset so it does not
	# fight the baked FocusCamera track, which means a leak would drag the camera forever.
	#
	# Waited out in REAL frames, not by winding. The shake decays in wall time the way
	# Flixel's does, and winding moves the song clock without moving the wall clock - so
	# winding past the last shake re-triggers it and then asks why it has not finished.
	await _wind_to(player, 11.0)
	var settled: bool = false
	for _frame: int in 240:
		await process_frame
		if camera.position_interpolate_offset.length() < 0.001:
			settled = true
			break
	_check(settled, "la sacudida no se limpio: %s" % camera.position_interpolate_offset)

	# beat 332 = 131.05s: the HUD leaves, and beat 348 = 137.37s takes the screen with it.
	await _wind_to(player, 130.5)
	while player.current_animation_position < 141.0:
		await process_frame

	_check(is_zero_approx(bar.modulate.a) and is_zero_approx(strumline.modulate.a),
		"el HUD tendria que haberse desvanecido")
	# Downscroll: the bar goes up, the strumlines go down, both by 250 scaled 1.5x.
	_check(is_equal_approx(bar.position.y, bar_start - 375.0),
		"la barra acabo en y=%.0f y esperaba %.0f" % [bar.position.y, bar_start - 375.0])
	_check(is_equal_approx(strumline.position.y, strumline_start + 375.0),
		"la strumline acabo en y=%.0f y esperaba %.0f" % [
			strumline.position.y, strumline_start + 375.0])
	_check(is_equal_approx(black.color.a, 1.0),
		"el fundido a negro acabo en alpha %.2f" % black.color.a)

	_drop(level)


## The swap itself, walked to rather than seeked to.
func _check_stand_up() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var player: AnimationPlayer = level.get_node("RubiconLevelClock/AnimationPlayer")
	var stage: Node2D = level.get_node("Stage")

	_check(_visible_props(stage, false) > 0 and _visible_props(stage, true) == 0,
		"antes del cambio no tendria que verse ningun prop stand-")

	# Beat 232 at 152bpm.
	await _wind_to(player, 232.0 * 60.0 / 152.0 + 0.5)

	for name: String in ["TadanoStand", "KomiStand"]:
		var character: Node2D = level.find_child(name, true, false)
		_check(character.visible, "%s tendria que verse tras el cambio" % name)
	for name: String in ["Tadano", "Komi", "KomiGirlfriend"]:
		var character: Node2D = level.find_child(name, true, false)
		_check(not character.visible, "%s tendria que ocultarse tras el cambio" % name)

	# standUP(): prop.visible = prop.name.indexOf("stand-") != -1 - every prop inverts.
	var visible_total: int = _visible_props(stage, false)
	var visible_stand: int = _visible_props(stage, true)
	_check(visible_total > 0 and visible_total == visible_stand,
		"tras el cambio solo tendrian que verse props stand-: %d de %d" % [
			visible_stand, visible_total])

	# The cast rebinds, or the chart's endAnimation/endConv at 132.2s reach the characters
	# that no longer have them.
	var events: Node = level.get_node("PhoneCallEvents")
	_check(events.cast[&"boyfriend"] == level.find_child("TadanoStand", true, false),
		"el reparto no se reasigno a la pareja de pie")
	_check(events.cast[&"dad"] == level.find_child("KomiStand", true, false),
		"el reparto no se reasigno a la pareja de pie")

	# Idempotent: the rebind means a second call would hide what the first revealed, and a
	# method key fires again whenever something re-seeks across it.
	events.stand_up()
	_check(level.find_child("TadanoStand", true, false).visible,
		"una segunda llamada a stand_up() oculto a la pareja de pie")

	_drop(level)


func _visible_props(node: Node, only_stand: bool) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child is Sprite2D and (child as Sprite2D).visible:
			if not only_stand or String(child.name).contains("stand_"):
				count += 1
		count += _visible_props(child, only_stand)
	return count


## Winds an AnimationPlayer forward in small hops instead of one seek.
##
## Method-track keys are NOT reliably fired by seeking: a seek only runs a key if it lands
## close after it. Measured on this scene, with the SetProperty key at 65.477s and the seek
## starting at 65.0 - a 1.0s jump fires it, a 2.0s jump does not, and neither does 4, 5, 6,
## 8 or 10. So anything that jumps around the song and expects the events to have happened
## has to walk there. Gameplay never does this (a song plays start to finish and a retry
## rebuilds the scene), but every harness here does.
const WIND_STEP := 0.5


## Both strumlines on autoplay. A guard that walks the song without it has the player miss
## every note, and a missed song ends in the death sequence rather than at the last bar.
func _autoplay(level: Node) -> void:
	for side: String in ["Opponent", "Player"]:
		level.get_node("UILayer/UI/%s" % side).autoplay = true


## Frees a level NOW rather than at the end of the frame. queue_free plus a single awaited
## frame leaves the old level alive alongside the new one, and this guard builds six of
## them - each with a stage, four characters, eight lanes of AnimationTree and three audio
## streams, all still running _process.
func _drop(level: Node) -> void:
	root.remove_child(level)
	level.free()


func _wind_to(player: AnimationPlayer, target: float) -> void:
	var at: float = player.current_animation_position
	while at < target:
		at = minf(at + WIND_STEP, target)
		player.seek(at, true)
		await process_frame


func _check_idle_suffix() -> void:
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
	_autoplay(level)
	await process_frame

	var player: AnimationPlayer = level.get_node("RubiconLevelClock/AnimationPlayer")
	var tadano: Node = level.find_child("Tadano", true, false)

	await _wind_to(player, 60.0)
	_check(tadano.animations[&"sing_left"] == &"sing_left",
		"tadano ya esta en alt antes del SetProperty")

	await _wind_to(player, 70.0)
	_check(tadano.animations[&"sing_left"] == &"sing_left_alt",
		"el SetProperty no cambio a tadano al set alt")
	_check(tadano.dancing_animations == ([&"dance_idle_alt"] as Array[StringName]),
		"el baile de tadano no cambio al alt: %s" % [tadano.dancing_animations])

	_drop(level)


# The amtake-base note style. Names are checked, but so are COLOURS: a lane-to-colour
# mapping is the one thing here that can be wrong while every name is right, and the JSON
# is explicit about it (left purple, down blue, up green, right red).
func _check_notestyle() -> void:
	const EXPECTED_COLOURS := {
		"left": Color8(159, 76, 141), "down": Color8(26, 199, 233),
		"up": Color8(34, 196, 44), "right": Color8(206, 60, 76),
	}
	const DIRECTIONS := ["left", "down", "up", "right"]

	var lanes: SpriteFrames = load("res://animania_mod/notestyle/amtake_lanes_frames.tres")
	var notes: SpriteFrames = load("res://animania_mod/notestyle/amtake_notes_frames.tres")

	for direction: String in DIRECTIONS:
		for state: String in ["neutral", "press", "confirm"]:
			_check(lanes.has_animation("%s_lane_%s" % [direction, state]),
				"falta %s_lane_%s" % [direction, state])
		for part: String in ["neutral", "hold", "tail"]:
			_check(notes.has_animation("%s_note_%s" % [direction, part]),
				"falta %s_note_%s" % [direction, part])

	_check(lanes.get_animation_names().size() == 12,
		"amtake_lanes tiene %d animaciones, esperaba 12" % lanes.get_animation_names().size())
	_check(notes.get_animation_names().size() == 12,
		"amtake_notes tiene %d animaciones, esperaba 12" % notes.get_animation_names().size())

	for frames: SpriteFrames in [lanes, notes]:
		for anim: String in frames.get_animation_names():
			for i: int in frames.get_frame_count(anim):
				var texture: Texture2D = frames.get_frame_texture(anim, i)
				_check(texture is AtlasTexture and (texture as AtlasTexture).atlas != null,
					"%s fotograma %d no tiene textura" % [anim, i])

	# The note and the hold body of a lane have to be the SAME colour. The hold strip ships
	# with no XML at all - it is eight cells read off the image - so nothing but the pixels
	# can say whether the slicing lines up with the note colours.
	for direction: String in DIRECTIONS:
		var expected: Color = EXPECTED_COLOURS[direction]
		for part: String in ["neutral", "hold", "tail"]:
			var average: Color = _average_colour(
				notes.get_frame_texture("%s_note_%s" % [direction, part], 0))
			var distance: float = (Vector3(average.r, average.g, average.b)
				- Vector3(expected.r, expected.g, expected.b)).length()
			_check(distance < 0.25, "%s_note_%s es %s y esperaba ~%s" % [
				direction, part, average, expected])

	# The hit splash and the hold cover. amtake-base.json turns both on; Rubicon has no slot
	# for either, so lane_effects.gd is new behaviour and this pins its numbers to the JSON.
	var effects: SpriteFrames = load("res://animania_mod/notestyle/amtake_effects_frames.tres")
	for direction: String in DIRECTIONS:
		for variant: int in [1, 2]:
			_check(effects.has_animation("splash_%s_%d" % [direction, variant]),
				"falta splash_%s_%d" % [direction, variant])
		_check(effects.has_animation("cover_%s" % direction), "falta cover_%s" % direction)
		_check(effects.has_animation("cover_%s_end" % direction),
			"falta cover_%s_end" % direction)
		# The body loops - holdNoteCover's <dir>Continue is <dir>Start's clip looped - and
		# the end does not, or the cover would never go away.
		_check(effects.get_animation_loop("cover_%s" % direction),
			"cover_%s tendria que hacer bucle" % direction)
		_check(not effects.get_animation_loop("cover_%s_end" % direction),
			"cover_%s_end no tendria que hacer bucle" % direction)

	# The importer strips a frame index with \d+$, and these subtextures are spelled
	# "note splash purple 10000": the variant digit sits right before the index, so both get
	# eaten and the two variants merge into one animation. They are split by halving that
	# merged animation, which only holds if the halves come out the authored length.
	_check(effects.get_frame_count("splash_left_1") == 4
			and effects.get_frame_count("splash_left_2") == 4,
		"los splashes tendrian que tener 4 fotogramas cada variante")
	_check(effects.get_frame_count("cover_left") == 5,
		"la cubierta de hold tendria que tener 5 fotogramas")
	_check(effects.get_frame_count("cover_left_end") == 3,
		"el final de la cubierta tendria que tener 3 fotogramas")

	var lane_scene: String = FileAccess.get_file_as_string(
		"res://animania_mod/notestyle/Lane.tscn")
	_check(lane_scene.contains("lane_effects.gd") and lane_scene.contains("amtake_effects"),
		"Lane.tscn no lleva el nodo de efectos")

	var effect_constants: Dictionary = load(
		"res://animania_mod/scripts/lane_effects.gd").get_script_constant_map()
	_check(is_equal_approx(float(effect_constants["SPLASH_SCALE"]), 0.9),
		"la escala del splash no es la del JSON")
	_check(is_equal_approx(float(effect_constants["COVER_SCALE"]), 0.7),
		"la escala de la cubierta no es la del JSON")
	_check(is_equal_approx(float(effect_constants["ROTATION_VARIANCE"]), 180.0),
		"rotationVariance no es la del JSON")

	# note-holds.png ships with no XML at all: it is eight 64x87 cells that were read off
	# the image. So the slicing is pinned by where each region SITS - eight distinct cells
	# at the known x offsets, body then tail within each colour - and by the colour check
	# above, which is what would catch a pair swapped between two directions.
	const CELLS := [1, 67, 133, 199, 265, 331, 397, 463]
	var seen: Dictionary = {}
	for i: int in DIRECTIONS.size():
		var direction: String = DIRECTIONS[i]
		for pair: int in 2:
			var part: String = "hold" if pair == 0 else "tail"
			var region: AtlasTexture = notes.get_frame_texture(
				"%s_note_%s" % [direction, part], 0)
			var expected := Rect2(float(CELLS[i * 2 + pair]), 0.0, 64.0, 87.0)
			_check(region.region.is_equal_approx(expected),
				"%s_note_%s recorta %s y esperaba %s" % [
					direction, part, region.region, expected])
			_check(not seen.has(region.region),
				"%s_note_%s repite el recorte %s" % [direction, part, region.region])
			seen[region.region] = true
			_check(region.atlas.resource_path.get_file() == "note-holds.png",
				"%s_note_%s no sale de note-holds.png" % [direction, part])

	# The rewritten scenes. A swapped path that keeps its old uid loads the OLD resource -
	# note-holds.png did exactly that until the stripping rule was widened.
	for scene_path: String in ["res://animania_mod/notestyle/Lane.tscn",
			"res://animania_mod/notestyle/Note.tscn"]:
		var text: String = FileAccess.get_file_as_string(scene_path)
		_check(not text.contains("funkin"),
			"%s todavia menciona funkin" % scene_path)
		for line: String in text.split("\n"):
			if line.begins_with("[ext_resource") and line.contains("res://animania_mod"):
				_check(not line.contains("uid="),
					"uid obsoleto en %s: %s" % [scene_path, line])

	# A TextureRect with no expand_mode takes its texture's size as its MINIMUM, and a
	# Control's rect is the larger of its anchored size and its minimum. funkin's tail
	# graphic is 64x50 and the trail is 50 thick, so they agree by accident; amtake's is
	# 64x87 and the cap came out 87 thick against a 50-thick trail, sticking out past both
	# edges. All four Tails need IGNORE_SIZE for the anchors to win.
	var note_text: String = FileAccess.get_file_as_string(
		"res://animania_mod/notestyle/Note.tscn")
	var tails: int = 0
	var lines: PackedStringArray = note_text.split("\n")
	for i: int in lines.size():
		if not lines[i].begins_with("[node name=\"Tail\""):
			continue
		tails += 1
		var found: bool = false
		for j: int in range(i + 1, mini(i + 14, lines.size())):
			if lines[j].begins_with("[node"):
				break
			if lines[j].strip_edges() == "expand_mode = 1":
				found = true
		_check(found, "a la cola de la linea %d le falta expand_mode = 1" % i)
	_check(tails == 4, "esperaba 4 colas en Note.tscn y hay %d" % tails)


func _average_colour(texture: Texture2D) -> Color:
	var image: Image = (texture as AtlasTexture).get_image()
	var total := Vector3.ZERO
	var count: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a < 0.8:
				continue
			total += Vector3(pixel.r, pixel.g, pixel.b)
			count += 1
	if count == 0:
		return Color.BLACK
	total /= float(count)
	return Color(total.x, total.y, total.z)



# The animated health icons. Rubicon ships a two-frame icon and no code that switches it,
# so all of this is new behaviour rather than a rename, and every number comes from
# komi.hx's initHealthIcon.
func _check_icons(level: Node) -> void:
	# phone-call.script's onStartSong gives playerId 1 `updateHealthIcon(2 - health)` and
	# playerId 0 `updateHealthIcon(health)`, labelled `// Boyfriend` and `// Dad`. THE
	# COMMENTS ARE BACKWARDS, and this check had them copied in, so it agreed with the bug
	# for two rounds: on a device tadano wore the losing face at full health and the winning
	# one as he died.
	#
	# AnimaniaStuff.makeAmTakeAnimatedIcon settles it in the mod's own code -
	# `isPlayer = (icon.playerId == 0)` - so playerId 0 is the player and it is the OPPONENT
	# that reads the inverse, as in stock Funkin. The two tilts agree: playerId 0 tilts below
	# healthLerp .25 and playerId 1 above 1.75, each reacting to its own side losing.
	var expected: Dictionary = {
		"IconL": {"frames": "komi_icon", "inverted": true, "alt": true, "flip": true,
			"tilt": 50.0},
		"IconR": {"frames": "tadano_icon", "inverted": false, "alt": false, "flip": false,
			"tilt": -30.0},
	}

	for icon_name: String in expected:
		var entry: Dictionary = expected[icon_name]
		var icon: AnimatedSprite2D = level.find_child(icon_name, true, false)
		_check(icon != null, "falta %s" % icon_name)
		if icon == null:
			continue

		_check(icon.get_script() != null
				and icon.get_script().resource_path.get_file() == "animated_health_icon.gd",
			"%s no lleva el script de icono animado" % icon_name)
		_check(icon.sprite_frames.resource_path.get_file() == "%s.tres" % entry["frames"],
			"%s usa %s" % [icon_name, icon.sprite_frames.resource_path.get_file()])
		_check(icon.inverted == entry["inverted"],
			"%s: invertido tendria que ser %s" % [icon_name, entry["inverted"]])
		# One tilt rule per icon, on its own side losing, with the mod's own degrees.
		_check(is_equal_approx(icon.tilt_degrees, float(entry["tilt"])),
			"%s se inclina %.0f grados y el script dice %.0f" % [
				icon_name, icon.tilt_degrees, float(entry["tilt"])])
		_check(icon.has_alt_poses == entry["alt"],
			"%s: poses alt tendrian que ser %s" % [icon_name, entry["alt"]])
		_check((icon.scale.x < 0.0) == entry["flip"],
			"%s: el volteo tendria que ser %s" % [icon_name, entry["flip"]])

		for state: String in ["idle", "losing", "to_losing", "from_losing"]:
			_check(icon.sprite_frames.has_animation(state),
				"%s no tiene %s" % [icon_name, state])
		if entry["alt"]:
			for direction: String in ["left", "down", "up", "right"]:
				for suffix: String in ["", "_alt"]:
					_check(icon.sprite_frames.has_animation("sing_%s%s" % [direction, suffix]),
						"%s no tiene sing_%s%s" % [icon_name, direction, suffix])

		# Both icons are fitted to the height the MOD draws them at, measured off a capture
		# of it running: 93 pixels of a 1280x720 frame, so 140 of this project's. Their own
		# frames differ - tadano's is 146 tall and komi's 158 - so neither is left native.
		var frame: Texture2D = icon.sprite_frames.get_frame_texture(&"idle", 0)
		_check(is_equal_approx(absf(icon.scale.y) * frame.get_height(), ICON_HEIGHT),
			"%s mide %.0fpx de alto y la barra espera %.0f" % [
				icon_name, absf(icon.scale.y) * frame.get_height(), ICON_HEIGHT])
		var expected_offset_x: float = (-frame.get_width() * 0.5
			+ ICON_POSITION_OFFSET * FUNKIN_TO_RUBICON)
		_check(is_equal_approx(icon.offset.x, expected_offset_x),
			"%s tiene offset.x %.1f y esperaba %.1f" % [
				icon_name, icon.offset.x, expected_offset_x])

	# tadano's icon is a four-rung ladder, and every adjacent pair needs its transition or a
	# state change plays nothing. Non-adjacent pairs deliberately have none: the walk goes
	# one rung at a time.
	var tadano_icon: SpriteFrames = load("res://animania_mod/characters/tadano_icon.tres")
	for state: String in ["predeath", "losing", "idle", "winning"]:
		_check(tadano_icon.has_animation(state), "al icono de tadano le falta %s" % state)
	for transition: String in ["to_losing", "from_losing", "to_winning", "from_winning",
			"to_predeath", "from_predeath"]:
		_check(tadano_icon.has_animation(transition),
			"al icono de tadano le falta %s" % transition)

	# komi.hx: LOSING_THRESHOLD = 0.25 * 2 on a 0..2 bar, and iconTimer runs to 4 at 6x.
	# The other two come from phone-call.script's tilt thresholds - healthLerp 1.75 and 0.25
	# on the same 0..2 bar - which are the only marks in this slice for "winning hard" and
	# "about to die". AnimaniaStuff.makeAmTakeAnimatedIcon, which actually drives tadano's
	# four states, is not in this slice.
	var constants: Dictionary = load(
		"res://animania_mod/scripts/animated_health_icon.gd").get_script_constant_map()
	_check(is_equal_approx(float(constants["LOSING_THRESHOLD"]), 0.25),
		"el umbral de derrota no es el de komi.hx")
	_check(is_equal_approx(float(constants["SING_HOLD"]), 4.0 / 6.0),
		"el aguante de la pose de canto no es el de komi.hx")
	# From AnimaniaStuff.makeAmTakeAnimatedIcon, declared against a 0..2 bar, so half of
	# what it writes. These are the FACE's thresholds.
	_check(is_equal_approx(float(constants["WINNING_THRESHOLD"]), 0.8),
		"el umbral de victoria no es el WINING_THRESHOLD del modulo")
	_check(is_equal_approx(float(constants["PREDEATH_THRESHOLD"]), 0.125),
		"el umbral de premuerte no es el DEATH_THRESHOLD del modulo")
	# And this is the ANGLE's, from phone-call.script. Conflating the two is what shipped a
	# winning face that waited until 0.875. There is no WINNING_TILT_AT to check any more:
	# each icon tilts only when ITS OWN side is losing, so after the inversion both use the
	# low threshold and differ only in `tilt_degrees` - and this check went on naming the
	# constant after it was removed, which raised inside _check_icons and took the whole
	# icon section with it while the run still printed "todo OK".
	_check(not constants.has("WINNING_TILT_AT"),
		"WINNING_TILT_AT volvio: el icono debe inclinarse con una sola regla")
	_check(is_equal_approx(float(constants["PREDEATH_TILT_AT"]), 0.125),
		"el umbral de inclinacion baja no es el 0.25 del script")
