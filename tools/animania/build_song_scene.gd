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
const ICON_SCRIPT := "res://animania_mod/scripts/animated_health_icon.gd"
## Alto al que el mod dibuja los iconos, medido sobre una captura suya para phone-call: su
## arte ocupa y 37..129 de un fotograma de 1280x720, o sea 140 pixeles de este proyecto.
##
## `?` Se reusa aqui para los iconos de dadbattle porque son los MISMOS: los amtake
## animados que monta `AnimaniaStuff.makeAmTakeAnimatedIcon`. No esta medido sobre una
## captura de dadbattle; si aparece una, este es el numero que hay que comprobar.
const ICON_HEIGHT := 140.0
## Los 26 de Funkin, en pixeles de Funkin: `iconP1.x` los resta y el del otro lado los suma,
## y el algebra deja el mismo `-ancho/2 + 26` en los dos. Ver el comentario del offset.
const ICON_POSITION_OFFSET := 26.0 * 1920.0 / 1280.0
## `healthIcon` de cada personaje, del JSON del mod (assets/data/characters/<id>.json):
## el atlas que le toca, su escala relativa y sus offsets en pixeles de Funkin.
##
##   bf         id bf-amtake   scale 1     offsets [ 10, -10]
##   dad        id dad-amtake  scale 0.9   offsets [-10, -20]
##   dad-beast  id dad-amtake  scale 1.1   offsets [-10, -20]
##
## gf no esta: su healthIcon es `gf` a secas, un PNG de dos fotogramas sin XML, que es otro
## camino. tutorial es la unica que la pone de oponente y se queda sin iconos hasta
## entonces, que es lo que ya hacia.
const ICONS := {
	"bf": {"frames": "bf_amtake_icon", "scale": 1.0, "offsets": Vector2(10.0, -10.0)},
	"dad": {"frames": "dad_amtake_icon", "scale": 0.9, "offsets": Vector2(-10.0, -20.0)},
	"dad-beast": {"frames": "dad_amtake_icon", "scale": 1.1, "offsets": Vector2(-10.0, -20.0)},
}
const TIME_BAR_SCRIPT := "res://animania_mod/ui/song_time_bar.gd"
const NOTE_OVERRIDES := "res://animania_mod/songs/phone_call_note_overrides.tres"
## The amtake-base receptors, which is the note style every Animania song uses.
const LANE := "res://animania_mod/notestyle/Lane.tscn"
const INPUT_MAP := "res://addons/rubicon_mania/resources/default_input_map.tres"
const MOBILE_CONTROLS := "res://addons/rubicon_mobile_controls/mobile_controls.tscn"
const MOBILE_CONTROLS_OPACITY := 0.4
const PAUSE_MENU := "res://animania_mod/menus/pause/pause_menu.tscn"
const SONG_CAMERA := "res://animania_mod/scripts/song_camera.gd"

const SOURCE := "res://animania_mod/source/songs"
const STAGES := "res://animania_mod/stages"
const CHARACTERS := "res://animania_mod/characters"

## Funkin is 1280x720 and this project is 1920x1080, and that 1.5x lives on the camera -
## the stage's coordinates and the character positions stay verbatim.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCREEN := Vector2(1920.0, 1080.0)

var _root: Node2D
var _song_id: String
var _scene_animation: Animation


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
	_scene_animation = scene_animation
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

	# The letterbox the chart's CinematicBars events drive. Built always, at zero height,
	# so the baked track has something to write to - a track pointing at a node that is not
	# there is silently dropped when the scene is packed.
	var bars := CanvasLayer.new()
	bars.name = "CinematicBars"
	bars.layer = 1
	_root.add_child(bars)
	bars.owner = _root
	for edge: String in ["Top", "Bottom"]:
		var bar := ColorRect.new()
		bar.name = edge
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bars.add_child(bar)
		bar.owner = _root
		# NO anchors. A Control with anchors set refuses `size` - Godot logs "If you want
		# to set size, change the anchors" and drops the write - so the baked track would
		# do nothing at all. The guard caught this only because the error printed; the
		# check itself still said OK.
		bar.set(&"layout_mode", 0)
		bar.size = Vector2(SCREEN.x, 0.0)
		if edge == "Top":
			bar.position = Vector2.ZERO
		else:
			# Flipped and pinned to the bottom edge, so ONE size track grows it upward.
			bar.position = Vector2(0.0, SCREEN.y)
			bar.scale = Vector2(1.0, -1.0)

	var ui: Dictionary = _build_ui(difficulty)
	var where: Dictionary = stage.get_meta(&"characters", {})
	_place_cast(stage, cast_names, where, ui)
	var camera_zoom: float = float(stage.get_meta(&"camera_zoom", 1.0)) * FUNKIN_TO_RUBICON
	_build_camera(where, cast_names, float(stage.get_meta(&"camera_zoom", 1.0)))

	# The camera work a chart does not ask for: follow whoever sings, bump on the beat.
	# phone-call does not use this - it has 97 baked FocusCamera events of its own.
	var song_camera: Node = _add(Node.new(), "SongCamera", SONG_CAMERA)
	song_camera.camera = _root.get_node("RubiconInterpolatedCamera2D")
	song_camera.clock = _root.get_node("RubiconLevelClock")
	song_camera.player_point = _root.get_node_or_null("PlayerCameraPoint")
	song_camera.opponent_point = _root.get_node_or_null("OpponentCameraPoint")
	song_camera.player = _root.get_node_or_null(
		"Stage/%s" % String(cast_names.get("player", "")).to_pascal_case().replace("-", ""))
	song_camera.opponent = _root.get_node_or_null(
		"Stage/%s" % String(cast_names.get("opponent", "")).to_pascal_case().replace("-", ""))
	# The tempo map's first entry, which is the song's own bpm.
	var changes: Array = meta.get("timeChanges", [])
	var song_bpm: float = float((changes[0] as Dictionary).get("bpm", 100.0)) \
		if not changes.is_empty() else 100.0
	song_camera.bpm = song_bpm
	print("OUT camara: bpm=%.1f sigue a %s y %s" % [song_camera.bpm,
		song_camera.player, song_camera.opponent])

	var health: Node = _add(Node.new(), "RubiconHealthModule", HEALTH_SCRIPT)
	health.note_controller = ui["Player"]
	health.starting_health = 50.0
	ui["HealthBar"].health_module = health

	_dress_icons(ui, health, cast_names)

	# La barra de tiempo necesita dos cosas: el reloj, para saber por donde va, y el
	# instrumental, para saber cuanto dura. Se cablean aqui y no en _build_ui porque
	# entonces todavia no existen.
	var time_bar: Node = ui.get("TimeBar")
	if time_bar != null:
		time_bar.clock = _root.get_node("RubiconLevelClock")
		var inst: Node = _root.find_child("Instrumental", true, false)
		if inst != null:
			time_bar.instrumental = inst
		print("OUT barra de tiempo: reloj=%s instrumental=%s" % [
			str(time_bar.clock != null), str(time_bar.instrumental != null)])

	# The chart's camera performance. dadbattle authors 98 events - 42 focus moves, 40
	# zooms, angles, shakes and bars - and a level that ignores them sits still through the
	# whole song. phone-call has its own baker; this is the general one.
	var chart_path: String = "%s/%s/%s-chart.json" % [SOURCE, _song_id, _song_id]
	var chart: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(chart_path))
	var events: Array = chart.get("events", [])
	if not events.is_empty():
		var focus_points: Dictionary = {}
		for entry: Array in [[0, "Player"], [1, "Opponent"], [2, "Girlfriend"]]:
			var point: Node2D = _root.get_node_or_null("%sCameraPoint" % entry[1])
			if point != null:
				focus_points[entry[0]] = point.position
		var baker: RefCounted = load(
			"res://tools/animania/song_camera_events.gd").new(
				focus_points, camera_zoom, song_bpm)
		baker.build(events, instrumental.get_length(), _scene_animation)
		# The chart owns the camera now; the fallback would write the same two properties
		# every frame and the two would fight.
		song_camera.follows_singer = false
		print("OUT la camara la manda el chart, no el seguidor")

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


## Los dos iconos de la barra de vida. Hasta ahora solo los tenia phone-call, porque su
## builder es otro: las canciones que salen de AQUI llevaban la barra sin una sola cara.
##
## Cual va en cada lado: IconL el OPONENTE, IconR el JUGADOR, y el del oponente lee la vida
## al reves -en Funkin la cara de perder del oponente sale cuando la barra esta llena-.
## Es el mismo reparto que phone-call, que ademas voltea la barra; aqui no se voltea nada.
##
## Sin `set_editable_instance` las sobrescrituras sobre los hijos de una instancia NO se
## guardan, y la barra seguiria saliendo con lo que trae de fabrica.
func _dress_icons(ui: Dictionary, health: Node, cast_names: Dictionary) -> void:
	var bar: Control = ui.get("HealthBar")
	if bar == null:
		return
	# `inverted` es como LEE la vida y `mirrored` es en que LADO se pone; son cosas
	# distintas y juntarlas puso a bf a la izquierda. En Funkin la barra se llena hacia el
	# jugador: su icono va a la DERECHA del divisor y el del oponente a la izquierda. Y en
	# Rubicon el lado sale del signo de scale.x, donde el negativo es la derecha -medido:
	# con el oponente en negativo salio el jugador a la izquierda-.
	#
	#                          nodo     ranura      lee al reves  a la derecha
	for entry: Array in [["IconL", "opponent", true, false],
			["IconR", "player", false, true]]:
		var who: String = String(cast_names.get(entry[1], ""))
		var spec: Dictionary = ICONS.get(who, {})
		if spec.is_empty():
			print("OUT icono: %s no tiene uno declarado, se queda sin cara" % who)
			continue
		var icon: AnimatedSprite2D = bar.find_child(entry[0] as String, true, false)
		if icon == null:
			print("OUT FALLO: la barra de vida no tiene %s" % entry[0])
			continue
		icon.set_script(load(ICON_SCRIPT))
		icon.sprite_frames = load("%s/%s.tres" % [CHARACTERS, spec["frames"]])
		icon.animation = &"idle"
		icon.health_module = health
		icon.note_controller = ui[_controller_for(entry[1] as String)]
		icon.clock = _root.get_node("RubiconLevelClock")
		icon.inverted = entry[2] as bool
		# Ni inclinacion ni balanceo: los dos salen del onStartSong de phone-call.
		icon.song_bob_and_tilt = false
		icon.tilt_degrees = 0.0
		# Estos iconos no tienen poses de canto -su atlas son estados, no notas-.
		icon.has_alt_poses = false
		var frame: Texture2D = icon.sprite_frames.get_frame_texture(&"idle", 0)
		var fit: float = ICON_HEIGHT * float(spec["scale"]) / float(frame.get_height())
		# El SIGNO de scale.x es lo que pone a cada icono en su lado: Rubicon coloca los dos
		# sobre el mismo punto de la barra y los separa por ahi. Con los dos en positivo
		# salian montados uno encima del otro en mitad de la barra, que es como se vio.
		var mirrored: bool = entry[3] as bool
		icon.scale = Vector2(-fit if mirrored else fit, fit)
		# Y el dibujo se vuelve a voltear, porque el signo de arriba lo ha espejado de paso
		# y estos personajes traen `flipX: false` en su JSON.
		icon.flip_h = mirrored
		# El offset del personaje -healthIcon.offsets, en pixeles de Funkin- mas el medio
		# ancho que centra el dibujo sobre el punto, mas los 26 de Funkin: la formula de
		# `iconP1.x` lleva un `- 26` y la del otro lado su simetrico, y el algebra deja el
		# mismo `-ancho/2 + 26` para los dos. Es el mismo numero que phone-call.
		icon.offset = Vector2(-frame.get_width() * 0.5 + ICON_POSITION_OFFSET, 0.0) \
			+ (spec["offsets"] as Vector2) * FUNKIN_TO_RUBICON / fit
		print("OUT icono %-5s %-14s escala %.3f  alto %.0f" % [entry[0], who, fit,
			frame.get_height() * fit])
	_root.set_editable_instance(bar, true)


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

	# La barra de progreso de la cancion: initTimeBar / updateTimeBar de PlayState. Va en su
	# PROPIA capa, por encima del HUD, y no dentro de `UI`: el mod le pone `cameras = null`
	# -la de por defecto, no camHUD- y un zIndex de 999999, asi que no se apaga cuando se
	# apaga el HUD. En phone-call eso importa: el HUD no entra hasta el beat 31.
	# Ver animania_mod/ui/song_time_bar.gd para las lineas del binario.
	var bar_layer := CanvasLayer.new()
	bar_layer.name = "TimeBarLayer"
	bar_layer.layer = layer.layer + 1
	_root.add_child(bar_layer)
	bar_layer.owner = _root

	var time_bar := ColorRect.new()
	time_bar.name = "TimeBar"
	time_bar.set_script(load(TIME_BAR_SCRIPT))
	bar_layer.add_child(time_bar)
	time_bar.owner = _root
	built["TimeBar"] = time_bar

	var judgment: Control = load(JUDGMENT).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	judgment.name = "Judgment"
	ui.add_child(judgment)
	judgment.owner = _root

	var health_bar: Control = load(HEALTH_BAR).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	health_bar.name = "HealthBar"
	ui.add_child(health_bar)
	health_bar.owner = _root
	# Las dos lineas que build_level_scene.gd ya habia tenido que aprender, y este builder
	# no. `layout_mode` NO es solo cosa del inspector: guardado a 0 en un nodo instanciado,
	# al cargar la escena pone los anclajes a cero y la barra se va a la esquina de arriba a
	# la izquierda. Y con el 1 solo no basta: Godot elige entonces el preset que casa con
	# los anclajes -el 5, centrado arriba-, lo guarda, y al cargar lo RE-APLICA tirando los
	# offsets, con lo que la barra sube 45 px (67.5 aqui) por encima de su sitio. El -1
	# guarda "a medida" y no mueve nada.
	#
	# Medido en bopeebo, reconstruyendo y comparando la posicion de la barra:
	#   comiteada    (-546.0, 67.5)  anclas 0.5   <- su sitio
	#   solo rebuild (   0.0,  0.0)  anclas 0     <- esquina
	#   con layout 1 (-546.0,  0.0)  anclas 0.5   <- centrada pero 67.5 arriba
	#   con las dos  (-546.0, 67.5)  anclas 0.5   <- su sitio
	#
	# Y de paso sale que tutorial.tscn TENIA la barra en la esquina: su escena comiteada da
	# (0,0) con anclas 0. Llevaba asi desde que se genero.
	health_bar.set(&"layout_mode", 1)
	health_bar.set(&"anchors_preset", -1)
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
func _place_cast(stage: Node2D, cast_names: Dictionary, where: Dictionary,
		ui: Dictionary) -> void:
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
		# THE wire. RubiconCharacter subscribes to note_changed and to the clock's
		# step_change through its level_note_controller, and a character without one plays
		# nothing at all - not even its idle. The first build of tutorial had both of them
		# standing frozen with an empty current_animation, and it read as "the camera does
		# not follow the singer" because the singer was never singing.
		if slot != "girlfriend" and ui.has(_controller_for(slot)):
			character.level_note_controller = ui[_controller_for(slot)]
		else:
			# Girlfriend sings nothing, but she still dances, so she takes the opponent's
			# controller purely for its clock.
			character.level_note_controller = ui.get("Opponent")
		stage.add_child(character)
		character.owner = _root
		print("OUT %-11s %-20s en (%.0f, %.0f)" % [
			slot, who, character.position.x, character.position.y])


func _controller_for(slot: String) -> String:
	return "Player" if slot == "player" else "Opponent"


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
