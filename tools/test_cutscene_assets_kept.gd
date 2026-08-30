extends SceneTree

## The pre-rendered cutscene videos are now the ONLY copy. Guard them as such.
##
## This file used to assert the opposite, and the reversal was deliberate, so
## the old reasoning is kept here rather than deleted - it is still correct, it
## just lost.
##
## What it used to say: the art a video replaces must stay, because the .ogv is
## output and the sprites are the negative. render_cutscene.gd films the live
## scene by switching prefer_cutscene_video off, so with no live scene there is
## nothing to film, and the cutscene is frozen forever at whatever was last
## encoded - no resolution change, no fix to a frame, no re-cut. That argument
## caught a deletion in run #215 and was right to.
##
## What changed: it was put to the owner with that cost stated plainly, and the
## answer was to freeze them and take the space. So the art is gone on purpose,
## and these cutscenes CANNOT be re-rendered any more. Four others were already
## in that state without anyone deciding it - Chimera's deaths 1-3, step_4,
## MonoCloseup and Monochrome's intro all lost their sprites when they were
## baked - which is part of why keeping two policies at once stopped making
## sense.
##
## So the risk inverted. It is no longer "someone deletes the master"; it is
## "someone deletes, moves or breaks the wiring to the only copy that exists".
## An .ogv is one file with no .import sidecar and nothing else referencing it,
## which makes it exactly the kind of thing a cleanup pass eats. What this file
## checks now:
##
##   * every song that hands a cutscene to a video still HAS its video node.
##     Listed, not discovered, so a scene losing one is red here instead of a
##     silently shorter run;
##   * the .ogv it names is on disk;
##   * and the component still plays it when there is no live scene to fall back
##     to. That last one is the whole arrangement: with the art gone, a preset
##     saying "no video" would not give the prettier version, it would give
##     thirty seconds of nothing.
##
## What is NOT frozen, and must not be quietly swept later:
##
##   * Chimera's `Intro`, eighteen nodes. `intro` and `taking_a_looksie` drive
##     it and whether the second falls inside the video's 34.708s window could
##     not be established without running the game. Unverified is not safe.
##   * `Prelude/Black`. It looks like prelude scenery and is not: `113_reaching`
##     fades its modulate through eight keys, far past the video window. It
##     survives only because the sprites beside it were removed one by one
##     instead of by deleting their parent.
##
## Run with:
##   godot --headless --path . --script tools/test_cutscene_assets_kept.gd

const VIDEO_SCRIPT := "res://lullaby_mod/scripts/lullaby/cutscene/lullaby_cutscene_video.gd"

## Songs known to hand a cutscene over to a video.
const WIRED := {
	"safety lullaby": "res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn",
	"chimera": "res://lullaby_mod/songs/chimera/sng_chimera.tscn",
}

## Los .ogv que ya no tienen de donde volver a salir. Cada uno es la unica copia
## de su cutscene, asi que se comprueban por ruta ademas de por la escena que los
## nombra: si alguien renombra la carpeta, la escena y el fichero se mueven
## juntos y la comprobacion de arriba seguiria en verde.
const FROZEN := [
	"res://lullaby_mod/songs/safety_lullaby/video/intro.ogv",
	"res://lullaby_mod/songs/chimera/video/prelude.ogv",
	"res://lullaby_mod/songs/monochrome/video/intro.ogv",
	"res://lullaby_mod/songs/monochrome/video/closeup.ogv",
	"res://lullaby_mod/assets/funkin/chimera/gameover/step_1/death_1.ogv",
	"res://lullaby_mod/assets/funkin/chimera/gameover/step_2/death_2.ogv",
	"res://lullaby_mod/assets/funkin/chimera/gameover/step_3/death_3.ogv",
	"res://lullaby_mod/assets/funkin/chimera/gameover/step_4/death_4.ogv",
	"res://lullaby_mod/assets/funkin/chimera/gameover/step_4/serena_skullface.ogv",
	"res://lullaby_mod/assets/funkin/chimera/gameover/step_4/step_4.ogv",
]

## Los que SI se pueden volver a renderizar, y por que.
##
## Un video cableado no es automaticamente irrecuperable. La sesion de fotos de
## Chimera no borro nada: sus catorce clips -`103_stroll` a `116_hexstare`- y los
## seis nodos de `Sequences` que mueven siguen enteros en la escena, asi que
## render_cutscene.gd puede volver a filmarla cuando haga falta. Por eso no entra
## en FROZEN: meterla ahi diria que el arte se fue, que es justo lo que hace que
## una poda posterior parezca segura.
##
## Se lista igualmente para que un video nuevo no pueda entrar sin que alguien
## decida en cual de las dos listas va.
const RERENDERABLE := {
	"res://lullaby_mod/songs/chimera/video/photoshoot.ogv":
		"la sesion de fotos: los clips 103-116 siguen vivos en la escena",
}

## Ventanas declaradas mas largas que su propio .ogv, y cuanto se les tolera.
##
## NO es un ajuste para que la comprobacion pase. Es una discrepancia que esta
## comprobacion encontro el dia que se escribio y que no se puede resolver:
##
##   safety lullaby/IntroVideo  ends_at = 31.5  pero el .ogv dura 31.37s
##
## Funcionalmente da igual - el componente suelta el mando cuando el video se
## acaba, asi que el 31.5 no se alcanza nunca y el numero solo miente. Lo que no
## se puede descartar es lo otro: que al .ogv le falten los ultimos 0.13s -ocho
## fotogramas- del intro. Para saberlo haria falta el master, y ese esta en
## FROZEN: se borro. Asi que se anota en vez de taparse, y cualquier video nuevo
## que llegue corto sigue fallando.
const SHORT_WINDOW_OK := {
	"res://lullaby_mod/songs/safety_lullaby/video/intro.ogv": 0.15,
}

## Lo que se retiro a proposito y no debe volver: si reaparece, vuelven con el
## los megabytes que se decidio no pagar, y nadie lo notaria mirando el juego.
const RETIRED := {
	"res://lullaby_mod/songs/safety_lullaby/scenes/intro.tscn":
		"la intro viva de Safety Lullaby",
	"res://lullaby_mod/assets/funkin/chimera/textures/house_outside/intro/1.png":
		"las tarjetas de foto del preludio de Chimera",
}

## Y lo que sobrevive dentro de Chimera aunque parezca del preludio.
const CHIMERA_KEEPS := ["Prelude", "Black", "Intro"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	for label: String in WIRED:
		_song_checks(label, WIRED[label])

	_frozen_checks()
	_retired_checks()
	_component_checks()

	print("")
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - los videos congelados siguen enteros y cableados")
	quit(1 if _failures > 0 else 0)


## Cada .ogv sigue en disco. Es la comprobacion barata que atrapa el borrado
## accidental, que es ahora el unico fallo irreversible que queda.
func _frozen_checks() -> void:
	for path: String in FROZEN:
		_check("existe %s" % path.get_file(),
			FileAccess.file_exists(path) or ResourceLoader.exists(path),
			path)


func _retired_checks() -> void:
	for path: String in RETIRED:
		_check("sigue retirado: %s" % RETIRED[path],
			not FileAccess.file_exists(path), path.get_file())

	# Y los nodos de Chimera que NO se fueron, que es lo que separa esta poda de
	# haber borrado el nodo Prelude entero.
	var chimera: String = FileAccess.get_file_as_string(WIRED["chimera"])
	for node: String in CHIMERA_KEEPS:
		_check("[chimera] el nodo %s sigue en la escena" % node,
			chimera.contains('[node name="%s"' % node))
	_check("[chimera] y 113_reaching sigue pudiendo fundir con Black",
		chimera.contains('NodePath("../Prelude/Black:modulate")'))

	_chimera_window_checks(chimera)


## La ventana de la sesion de fotos casa con el calendario real de clips.
##
## `ends_at = 113.140144` no es un numero redondo ni elegido: es el instante
## EXACTO en que el reloj despacha `117_heartbeat`, o sea cuando el mando vuelve
## a la mecanica. Lo saque leyendo la pista de despacho, y escrito a mano en la
## escena no hay nada que lo ate: si alguien recronometra la cancion, el video
## sigue tapando la pantalla mientras la mecanica de heartbeat ya corre debajo, o
## la suelta antes y se ve un salto. Ninguna de las dos da error.
##
## Asi que se comprueba contra la fuente en vez de repetir la constante.
func _chimera_window_checks(scene: String) -> void:
	var found: Array[String] = _blocks_with(scene, 'name="PhotoshootVideo"')
	_check("[chimera] existe el nodo PhotoshootVideo", not found.is_empty())
	if found.is_empty():
		return
	var block: String = found[0]

	# El `times` que vale es el que acompaña a ESTE `clips`, no el primero del
	# fichero: la escena tiene decenas de pistas con su propio `times` y buscar a
	# secas encontraba el de otra, con un solo elemento.
	var clips_at: int = scene.find('"clips": PackedStringArray(')
	var clips: PackedStringArray = _string_array(scene, '"clips": PackedStringArray(')
	var times: PackedFloat32Array = _float_array(
		scene, '"times": PackedFloat32Array(', clips_at)
	_check("[chimera] se lee el calendario de clips (%d clips, %d tiempos)"
		% [clips.size(), times.size()],
		clips.size() > 0 and clips.size() == times.size())
	if clips.size() == 0 or clips.size() != times.size():
		return

	var at: Dictionary = {}
	for i: int in clips.size():
		at[clips[i]] = times[i]

	var starts: float = _number(block, "starts_at = ")
	var ends: float = _number(block, "ends_at = ")

	_check("[chimera] el video suelta el mando justo cuando arranca 117_heartbeat"
		+ " (%.6f)" % float(at.get("117_heartbeat", -1.0)),
		at.has("117_heartbeat")
			and absf(ends - float(at["117_heartbeat"])) < 0.001)

	_check("[chimera] y ya esta puesto antes de que empiece 104_photographysesh"
		+ " (%.6f)" % float(at.get("104_photographysesh", -1.0)),
		at.has("104_photographysesh") and starts <= float(at["104_photographysesh"]))

	# Y que no se quede ningun clip de la tanda fuera por el otro lado.
	var last_covered: String = ""
	for name: String in ["104_photographysesh", "105_headingout", "106_cameracheck",
			"107_turnaround", "108_headphones", "109_backingupback",
			"110_backingupfront", "111_disorient", "112_disorientidle",
			"113_reaching", "114_hexapproach", "115_runningaway", "116_hexstare"]:
		if not at.has(name):
			_check("[chimera] el clip %s sigue existiendo" % name, false)
			continue
		if float(at[name]) >= ends:
			last_covered = name
	_check("[chimera] y los trece clips 104-116 caen dentro de la ventana%s"
		% ("" if last_covered.is_empty() else " - NO: %s empieza en %.3f, fuera"
			% [last_covered, float(at.get(last_covered, 0.0))]),
		last_covered.is_empty())


## `PackedStringArray("a", "b")` -> los elementos.
func _string_array(text: String, prefix: String) -> PackedStringArray:
	var at: int = text.find(prefix)
	if at < 0:
		return PackedStringArray()
	var start: int = at + prefix.length()
	var end: int = text.find(")", start)
	if end <= start:
		return PackedStringArray()
	var out: PackedStringArray = []
	for piece: String in text.substr(start, end - start).split(","):
		out.append(piece.strip_edges().trim_prefix("\"").trim_suffix("\""))
	return out


## `PackedFloat32Array(0, 3, 19.9)` -> los numeros, buscando desde `from`.
func _float_array(text: String, prefix: String, from: int = 0) -> PackedFloat32Array:
	var at: int = text.find(prefix, from)
	if at < 0:
		return PackedFloat32Array()
	var start: int = at + prefix.length()
	var end: int = text.find(")", start)
	if end <= start:
		return PackedFloat32Array()
	var out: PackedFloat32Array = []
	for piece: String in text.substr(start, end - start).split(","):
		out.append(piece.strip_edges().to_float())
	return out


## El componente, sin escena viva detras.
##
## Con el arte fuera, `live_cutscene` llega vacio y el preset deja de tener voto:
## no hay version bonita a la que caer. Se comprueba sobre el codigo porque este
## guion no monta el arbol; test_cutscene_video.gd lo prueba corriendolo.
func _component_checks() -> void:
	var code: String = FileAccess.get_file_as_string(VIDEO_SCRIPT)
	_check("el componente se lee", not code.is_empty())
	if code.is_empty():
		return

	# Vacio ya no quiere decir una sola cosa: `live_fallback_exists` separa "la
	# cutscene viva se retiro" de "sigue ahi pero repartida y no hay un solo nodo
	# que apagar". Solo el primero le quita el voto al preset.
	_check("sin cutscene viva NI respaldo, el preset no decide",
		code.contains("if live_cutscene == null and not live_fallback_exists:")
			and code.contains("return true"))

	# La ventana se abre por reloj, no en _ready(). Un video con starts_at=53.7
	# arrancado en _ready() dibuja sobre el preludio y el intro cincuenta y tres
	# segundos antes de que le toque, y no da error de ninguna clase: se ve como
	# "el preludio dejo de salir".
	_check("abre la ventana cuando el reloj llega a starts_at",
		code.contains("if here < starts_at:") and code.contains("_open(here)"))

	# Y el pase 3D vuelve. Si esto se pierde, la cancion sigue con disable_3d
	# puesto y el resto del nivel es una pantalla vacia - sin un solo error.
	_check("devuelve el pase 3D al soltar el mando",
		code.contains("vp.disable_3d = _was_3d_disabled"))

	_check("y no exige una companera para montarse",
		not code.contains("clock == null or live_cutscene == null"))
	_check("sigue retirandose si falta el .ogv",
		code.contains("ResourceLoader.exists(video_path)"))


func _song_checks(label: String, path: String) -> void:
	var scene: String = FileAccess.get_file_as_string(path)
	_check("[%s] la escena se lee" % label, not scene.is_empty())
	if scene.is_empty():
		return

	var script_id: String = ""
	var re := RegEx.create_from_string(
		'\\[ext_resource type="Script"[^\\]]*path="%s"[^\\]]*id="([^"]+)"'
			% VIDEO_SCRIPT.replace("/", "\\/").replace(".", "\\."))
	var found: RegExMatch = re.search(scene)
	if found != null:
		script_id = found.get_string(1)
	_check("[%s] la escena usa LullabyCutsceneVideo" % label, not script_id.is_empty())
	if script_id.is_empty():
		return

	# TODOS los nodos de video, no solo el primero. Chimera tiene dos -el
	# preludio y la sesion de fotos- y buscar con find() dejaba al segundo sin
	# comprobar, en verde, que es la peor forma de no comprobar algo.
	var blocks: Array[String] = _blocks_with(scene, 'script = ExtResource("%s")' % script_id)
	_check("[%s] tiene al menos un nodo de video" % label, not blocks.is_empty())

	for block: String in blocks:
		var who: String = _quoted(block, '[node name="')
		var tag: String = "%s/%s" % [label, who if not who.is_empty() else "?"]

		var video_path: String = _quoted(block, "video_path = \"")
		_check("[%s] declara un video_path" % tag, not video_path.is_empty())
		if video_path.is_empty():
			continue

		_check("[%s] y el .ogv esta en el repo: %s" % [tag, video_path.get_file()],
			FileAccess.file_exists(video_path))
		_check("[%s] y esta clasificado (congelado o re-renderizable)" % tag,
			FROZEN.has(video_path) or RERENDERABLE.has(video_path), video_path)

		_window_checks(tag, block)

		# El reloj, que es lo unico que queda sincronizando el video con la
		# cancion.
		var clock: String = _quoted(block, "clock = NodePath(\"")
		_check("[%s] declara un clock" % tag, not clock.is_empty())
		if not clock.is_empty():
			_check("[%s] y sube un nivel para alcanzarlo (%s)" % [tag, clock],
				clock.begins_with("../"))
			_check("[%s] y ese nodo existe en la cancion" % tag,
				scene.contains('[node name="%s"' % clock.substr(3).split("/")[0]))


## La ventana declarada tiene sentido y el .ogv la cubre.
##
## Nace de dos errores de un dedo que no dan error de ejecucion: un `ends_at`
## anterior a `starts_at` deja el video sin abrirse nunca, y un `.ogv` mas corto
## que su ventana suelta el mando antes de tiempo y ensena la escena viva a
## medias. Los dos se ven jugando y ninguno en un log.
func _window_checks(tag: String, block: String) -> void:
	var starts: float = _number(block, "starts_at = ")
	var ends: float = _number(block, "ends_at = ")
	if ends <= 0.0:
		# 0 significa "usar la duracion del propio video", que es legitimo.
		return

	_check("[%s] la ventana avanza (%.3f -> %.3f)" % [tag, starts, ends], ends > starts)

	var video_path: String = _quoted(block, "video_path = \"")
	if not ResourceLoader.exists(video_path):
		return
	var stream: VideoStream = load(video_path) as VideoStream
	if stream == null:
		return
	var player := VideoStreamPlayer.new()
	player.stream = stream
	var have: float = player.get_stream_length()
	player.free()
	if have <= 0.0:
		# Un servidor de video que no decodifica no sabe la duracion. No es un
		# fallo del cableado y no se puede afirmar nada desde aqui.
		return
	var slack: float = float(SHORT_WINDOW_OK.get(video_path, 0.05))
	_check("[%s] el .ogv cubre la ventana (%.2fs de %.2fs)"
		% [tag, have, ends - starts], have >= (ends - starts) - slack)


## Todos los bloques `[node ...]` que contienen `needle`.
func _blocks_with(scene: String, needle: String) -> Array[String]:
	var out: Array[String] = []
	var from: int = 0
	while true:
		var at: int = scene.find(needle, from)
		if at < 0:
			break
		from = at + needle.length()
		var head: int = scene.rfind("[node ", at)
		if head < 0:
			continue
		var tail: int = scene.find("\n[", at)
		out.append(scene.substr(head, (tail - head) if tail > head else -1))
	return out


## El numero que sigue a `prefix`, o 0.0 si no esta.
func _number(text: String, prefix: String) -> float:
	var at: int = text.find(prefix)
	if at < 0:
		return 0.0
	var start: int = at + prefix.length()
	var end: int = text.find("\n", start)
	return text.substr(start, end - start).strip_edges().to_float() if end > start else 0.0


## Lo que va entre comillas justo despues de `prefix`.
func _quoted(text: String, prefix: String) -> String:
	var at: int = text.find(prefix)
	if at < 0:
		return ""
	var start: int = at + prefix.length()
	var end: int = text.find("\"", start)
	return text.substr(start, end - start) if end > start else ""


func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-58s%s" % [what, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		printerr("  FALLO %-58s%s" % [what, "  (%s)" % detail if detail else ""])
