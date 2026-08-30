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

	_check("sin cutscene viva, el preset no decide",
		code.contains("if live_cutscene == null:") and code.contains("return true"))
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

	var block: String = _block_with(scene, 'script = ExtResource("%s")' % script_id)
	_check("[%s] su nodo de video esta en la escena" % label, not block.is_empty())
	if block.is_empty():
		return

	var video_path: String = _quoted(block, "video_path = \"")
	_check("[%s] declara un video_path" % label, not video_path.is_empty())
	if not video_path.is_empty():
		_check("[%s] y el .ogv esta en el repo: %s" % [label, video_path.get_file()],
			FileAccess.file_exists(video_path))
		_check("[%s] y ese .ogv esta en la lista de congelados" % label,
			FROZEN.has(video_path), video_path)

	# El reloj, que es lo unico que queda sincronizando el video con la cancion.
	var clock: String = _quoted(block, "clock = NodePath(\"")
	_check("[%s] declara un clock" % label, not clock.is_empty())
	if not clock.is_empty():
		_check("[%s] y sube un nivel para alcanzarlo (%s)" % [label, clock],
			clock.begins_with("../"))
		_check("[%s] y ese nodo existe en la cancion" % label,
			scene.contains('[node name="%s"' % clock.substr(3).split("/")[0]))


## El bloque `[node ...]` que contiene `needle`.
func _block_with(scene: String, needle: String) -> String:
	var at: int = scene.find(needle)
	if at < 0:
		return ""
	var head: int = scene.rfind("[node ", at)
	if head < 0:
		return ""
	var tail: int = scene.find("\n[", at)
	return scene.substr(head, (tail - head) if tail > head else -1)


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
