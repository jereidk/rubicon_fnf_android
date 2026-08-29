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

		# Y todo lo que cuelga de ella. Sobre el texto y no con load(), porque
		# un guion --script no importa nada y los .import de estas texturas
		# apuntan a ficheros que solo existen despues de un pase de import.
		var missing: PackedStringArray = []
		for dep: RegExMatch in RegEx.create_from_string(
				'\\[ext_resource[^\\]]*path="([^"]+)"').search_all(text):
			var p: String = dep.get_string(1)
			if not FileAccess.file_exists(p):
				missing.append(p)
		_check(missing.is_empty(),
			"%s: sus %d referencias existen%s" % [key,
				RegEx.create_from_string('\\[ext_resource').search_all(text).size(),
				"" if missing.is_empty() else " - FALTAN " + ", ".join(missing)])

	# Y que el modulo se queje en vez de callarse, que es lo que dejo pasar esto
	# durante todo el port.
	var mod: String = _read(MODULE)
	_check(mod.contains("push_error") and mod.contains("ResourceLoader.exists("),
		"el modulo avisa si una ruta no resuelve, en vez de no hacer nada")

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


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
