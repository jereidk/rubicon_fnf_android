extends SceneTree

## El gameover de Chimera existe y esta cableado de punta a punta.
##
## Lo que habia: ChimeraGameoverModule con sus cinco rutas escritas en la
## escena de la cancion...
##
##     paths = {
##       &"step_0": "uid://1f1eqjg3yuyi", ... &"step_4": "uid://b34e6rl7fyiwr"
##     }
##
## ...y ninguna de las cinco escenas en el arbol. Los uid no resolvian contra
## nada, asi que morir en Chimera no llevaba a ningun sitio: te quedabas sin
## vida y la cancion seguia sonando hasta el final, sin gameover y sin
## reintento. El modulo estaba bien; lo que faltaba era el contenido, que se
## quedo en el pck de PC (res://songs/chimera/scenes/step_0..4.tscn) junto con
## sus imagenes, sus sfx y el video de step_4.
##
## Ese fallo era MUDO por partida doble - leer una clave ausente de un
## Dictionary tipado aborta la funcion, y change_scene_to_file() con un uid
## muerto tampoco lanza nada visible jugando - asi que esta guarda comprueba la
## cadena entera en vez de fiarse de que "la escena esta ahi":
##
##   las cinco claves que el modulo puede pedir estan en la tabla;
##   cada una apunta a un fichero que existe;
##   el uid de cada escena es EXACTAMENTE el que la tabla tiene escrito, que es
##     lo unico que hace que change_scene_to_file() encuentre algo;
##   y cada ext_resource de esas cinco escenas apunta a un fichero que existe,
##     que es donde se rompe un port hecho a base de copiar rutas.
##
## Lo de las rutas no es hipotetico: estas escenas salieron del pck, donde la
## raiz del mod es res:// y aqui es res://lullaby_mod/, asi que TODAS sus
## referencias hubo que reescribirlas. Una que se escape no da error al
## arrancar, solo un gameover sin imagen o sin sonido.
##
## Run with:
##   godot --headless --path . --script tools/test_chimera_gameover_wired.gd

const SONG := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
const MODULE := "res://lullaby_mod/scripts/lullaby/gameover/chimera_gameover_module.gd"

## Las claves que switch_to_gameover() puede construir: step_0 cuando no se
## cuentan muertes, y step_1..4 por clampi(deaths, 1, 4).
const KEYS := ["step_0", "step_1", "step_2", "step_3", "step_4"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var song: String = _read(SONG)
	var table: Dictionary = _paths_table(song)

	_check(table.size() == KEYS.size(),
		"la tabla del modulo trae %d rutas" % table.size())

	for key: String in KEYS:
		_check(table.has(key), "%s esta en la tabla" % key)
		if not table.has(key):
			continue

		var want_uid: String = table[key]
		var scene: String = "res://lullaby_mod/songs/chimera/scenes/%s.tscn" % key
		var text: String = FileAccess.get_file_as_string(scene)

		if not _check(not text.is_empty(), "%s: la escena existe" % key):
			continue

		# El uid del fichero contra el que la tabla pide. Es el eslabon que
		# faltaba, y no hay forma de que "casi" funcione: o coincide o
		# change_scene_to_file() no encuentra nada.
		var m: RegExMatch = RegEx.create_from_string(
			'^\\[gd_scene[^\\]]*uid="([^"]+)"').search(text)
		var got_uid: String = m.get_string(1) if m != null else "(sin uid)"
		_check(got_uid == want_uid,
			"%s: uid %s coincide con el que pide la tabla" % [key, got_uid])

		# Y todo lo que cuelga de ella, RECURSIVAMENTE. Sobre el texto y no con
		# load(), porque un guion --script no importa nada y los .import de
		# estas texturas apuntan a ficheros que solo existen tras un import.
		#
		# Que baje a los .tres no es celo de mas: la primera version de esto se
		# quedaba en el primer nivel y daba verde sobre un port roto. Las cinco
		# escenas apuntaban bien a sus death_N.tres, y esos .tres seguian
		# apuntando a res://assets/... - la raiz del pck - porque el extractor
		# solo habia traducido las escenas. Todo cargaba y no habia ni una hoja
		# de sprites en su sitio.
		var seen: Dictionary = {}
		var missing: PackedStringArray = []
		var total: int = _refs(scene, seen, missing)
		_check(missing.is_empty(),
			"%s: sus %d referencias existen, en todo el arbol%s" % [key, total,
				"" if missing.is_empty() else " - FALTAN " + ", ".join(missing)])

	_video_checks()

	# Y que el modulo se queje en vez de callarse, que es lo que dejo pasar esto
	# durante todo el port.
	var mod: String = _read(MODULE)
	_check(mod.contains("push_error") and mod.contains("ResourceLoader.exists("),
		"el modulo avisa si una ruta no resuelve, en vez de no hacer nada")

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## Los steps 1-3 dibujan su muerte con un vídeo, y hay un orden que respetar.
##
## Sus 13 fotogramas vivian en tres hojas de 4096x4096 por step - 75 MB de PNG,
## 27 MB de ASTC, y una recompresion ASTC que por si sola costo 12m29s de
## import - por dos segundos y medio de animacion fija. Ahora son tres .ogv de
## medio mega.
##
## Lo que se comprueba aqui es lo que NO se ve fallar hasta que alguien juega:
##
##   el VideoPlayer va ANTES que StepImage entre los hijos. Los hermanos 2D se
##     dibujan en orden, asi que la tarjeta de texto tiene que seguir tapando el
##     vídeo igual que tapaba al sprite. Invertidos, la tarjeta desaparece
##     detras de la animacion de muerte y el jugador ve el final antes que el
##     principio;
##
##   no queda ninguna pista apuntando al AnimatedSprite2D que ya no existe;
##
##   y el script arranca el vídeo en la misma llamada que la animacion, que es
##     la unica sincronizacion que hay entre los dos. Si alguien lo mueve a un
##     _ready() o le mete un await, el vídeo se adelanta un segundo entero: el
##     Timer de estas escenas no fija wait_time, asi que usa el defecto de Godot
##     y la animacion arranca un segundo despues de cargar la escena.
func _video_checks() -> void:
	for step: int in [1, 2, 3]:
		var scene: String = "res://lullaby_mod/songs/chimera/scenes/step_%d.tscn" % step
		var text: String = FileAccess.get_file_as_string(scene)
		if text.is_empty():
			continue

		var video_at: int = text.find('[node name="VideoPlayer"')
		var still_at: int = text.find('[node name="StepImage"')
		_check(video_at >= 0, "step_%d: la muerte la dibuja un VideoPlayer" % step)
		_check(video_at >= 0 and still_at > video_at,
			"step_%d: ...y va ANTES que StepImage, o la tarjeta queda tapada" % step)

		_check(not text.contains("AnimatedSprite2D"),
			"step_%d: no queda ninguna pista apuntando al sprite que se fue" % step)

	var script: String = FileAccess.get_file_as_string(
		"res://lullaby_mod/scripts/lullaby/gameover/chimera_gameover.gd")
	# Sobre el CÓDIGO y no sobre el texto: la primera version de esto se puso
	# roja contra una funcion correcta, porque el comentario que explica que no
	# debe haber ningun await contiene la palabra "await".
	var body: String = _code_only(_func_body(script, "_on_timer_timeout"))
	var video_at: int = body.find("video_player.play()")
	var anim_at: int = body.find('anim_player.play(')
	_check(video_at >= 0 and anim_at > video_at,
		"el vídeo arranca en la misma llamada que la animacion, y antes que ella")
	_check(not body.contains("await"),
		"...sin await por medio, o los dos dejan de salir en el mismo fotograma")


## Cuenta las referencias de `path` y de todo lo que estas alcanzan, anotando
## en `missing` las que no estan en disco. Solo baja por los ficheros de texto
## -.tscn y .tres- porque son los unicos cuyas referencias se pueden leer sin
## importar el proyecto; un .png o un .ogv son hojas por definicion.
func _refs(path: String, seen: Dictionary, missing: PackedStringArray) -> int:
	if seen.has(path):
		return 0
	seen[path] = true

	var ext: String = path.get_extension().to_lower()
	if ext != "tscn" and ext != "tres":
		return 0

	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return 0

	var total: int = 0
	for dep: RegExMatch in RegEx.create_from_string(
			'\\[ext_resource[^\\]]*path="([^"]+)"').search_all(text):
		var p: String = dep.get_string(1)
		total += 1
		if not FileAccess.file_exists(p):
			missing.append(p)
			continue
		total += _refs(p, seen, missing)
	return total


## La tabla `paths` tal como esta autorada en la escena de la cancion.
func _paths_table(song: String) -> Dictionary:
	var out: Dictionary = {}
	var at: int = song.find("[node name=\"ChimeraGameoverModule\"")
	if at < 0:
		_check(false, "la escena de la cancion trae el nodo ChimeraGameoverModule")
		return out

	var block: String = song.substr(at, 600)
	for m: RegExMatch in RegEx.create_from_string(
			'&"(step_\\d)":\\s*"([^"]+)"').search_all(block):
		out[m.get_string(1)] = m.get_string(2)
	return out


## `body` sin lineas de comentario, para preguntas sobre lo que el codigo HACE.
func _code_only(body: String) -> String:
	var out: PackedStringArray = []
	for line: String in body.split("\n"):
		var code: String = line
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		out.append(code)
	return "\n".join(out)


func _func_body(text: String, name: String) -> String:
	var head: int = text.find("func %s(" % name)
	if head < 0:
		_check(false, "%s() existe" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "%s se lee" % path.get_file())
	return text
