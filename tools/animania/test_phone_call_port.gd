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

	level.queue_free()


## The chart's camera events, checked by seeking the level to the END of each tween and
## reading what the camera actually holds. Expectations come out of the chart JSON, so
## re-exporting the song moves them; nothing here is a copied number.
func _check_camera_events() -> void:
	var chart: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CHART_JSON))
	var level: Node = load(LEVEL).instantiate()
	root.add_child(level)
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

	# The letterbox has to leave the notes alone: Rubicon anchors its strumlines to the
	# BOTTOM, unlike Funkin, and the chart asks for 120px bars while notes are arriving.
	_check(level.get_node("CinematicBars").layer < level.get_node("UILayer").layer,
		"las barras tapan el HUD")

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
				var expected: Vector2 = focus_points[int(value.get("char", 0))] + Vector2(
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

	level.queue_free()
