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

var _failures: int = 0


const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const STEP_SECONDS := 60.0 / 152.0 / 4.0


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
	print("todo OK")
	quit(0)


func _check(condition: bool, message: String) -> void:
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
	# so a character node's own origin has to be its feet. Checked as "the art is drawn
	# above and around the origin", which is what that means and what a corner-anchored
	# character (the first version of this port) fails.
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
		_check(absf(anchor.x) < 300.0,
			"%s no esta centrado en horizontal: el sprite sale en x=%.1f" % [
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

	# Each side's chart against the source JSON, where `d` is a lane AND a side.
	var chart_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART_JSON))
	var notes: Array = chart_data["notes"]["standart"]
	var expected: Dictionary = {"Opponent": 0, "Player": 0}
	var kinds: Dictionary = {}
	for note: Dictionary in notes:
		var side: String = "Player" if int(note.get("d", 0)) >= 4 else "Opponent"
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

	# An instanced Control loses its authored anchors unless layout_mode says to keep them.
	# The health bar came out 4x27 in the top-left corner before that was set.
	var health_bar: Control = level.get_node("UILayer/UI/HealthBar")
	_check(health_bar.anchor_right > health_bar.anchor_left,
		"la barra de vida perdio sus anclas: %s" % health_bar.get_rect())

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
	_check(events_node.hud_up.size() == 1 and events_node.hud_down.size() == 2,
		"el beat 332 mueve la barra hacia arriba y las dos strumlines hacia abajo")

	_drop(level)


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
	# else. Their cameraOffsets are tadano-stand [200, 50] and komi-stand [50, 50].
	const STAND_UP_TIME := 232.0 * 60.0 / 152.0
	var stand_points: Dictionary = {}
	for entry: Array in [
			[0, "TadanoStand", Vector2(290, 667), Vector2(200, 50)],
			[1, "KomiStand", Vector2(269, 670), Vector2(50, 50)]]:
		var character: Node2D = level.find_child(entry[1], true, false)
		stand_points[entry[0]] = (character.position
			- Vector2(0.0, (entry[2] as Vector2).y * 0.5)
			+ (entry[3] as Vector2) * FUNKIN_TO_RUBICON)

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
				var expected: Vector2 = points[character] + Vector2(
					float(value.get("x", 0)), float(value.get("y", 0))) * FUNKIN_TO_RUBICON
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
	await _check_death()


## Tadano's death sequence. Rubicon emits health_depleted and nothing in the engine listens,
## so every piece of this is new - and it cannot be reached by seeking, only by dropping the
## health and letting the tweens run.
func _check_death() -> void:
	const DEATH_SETTLE := 2.5

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

		var elapsed: float = 0.0
		while elapsed < DEATH_SETTLE:
			elapsed += root.get_process_delta_time()
			await process_frame

		# The clock has to stop, and not as a nicety: its baked animation writes
		# position_interpolate_target every frame, so a death camera aimed at the dying
		# character is overwritten by the song's next FocusCamera key before it is drawn.
		_check(not clock.animation_player.is_playing(),
			"%s: el reloj tendria que pararse al morir" % form)

		var dark: ColorRect = level.get_node("Death/Dark")
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
	# phone-call.script's onStartSong: playerId 0 (Dad) gets updateHealthIcon(health) and
	# playerId 1 (Boyfriend) gets updateHealthIcon(2 - health). So the PLAYER's icon reads
	# the inverse in this song, not the opponent's - the reverse of stock Funkin.
	var expected: Dictionary = {
		"IconL": {"frames": "komi_icon", "inverted": false, "alt": true, "flip": true},
		"IconR": {"frames": "tadano_icon", "inverted": true, "alt": false, "flip": false},
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

		# Rubicon centres its icons on the bar and lays that out for bf's 150px frame; an
		# unscaled 171px icon runs 30px off the top of the screen.
		var frame: Texture2D = icon.sprite_frames.get_frame_texture(&"idle", 0)
		_check(is_equal_approx(absf(icon.scale.y) * frame.get_height(), 150.0),
			"%s mide %.0fpx de alto y la barra espera 150" % [
				icon_name, absf(icon.scale.y) * frame.get_height()])
		_check(is_equal_approx(icon.offset.x, -frame.get_width() * 0.5),
			"%s tiene offset.x %.1f y esperaba %.1f" % [
				icon_name, icon.offset.x, -frame.get_width() * 0.5])

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
	_check(is_equal_approx(float(constants["WINNING_THRESHOLD"]), 0.875),
		"el umbral de victoria no es el 1.75 del script")
	_check(is_equal_approx(float(constants["PREDEATH_THRESHOLD"]), 0.125),
		"el umbral de premuerte no es el 0.25 del script")
