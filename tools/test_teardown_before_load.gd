extends SceneTree

## La escena vieja termina de morir ANTES de que empiece a cargar la nueva.
##
## `unload_current_scene()` hace `queue_free`, que difiere la destruccion al
## final del fotograma. Pedir `load_threaded_request()` en la linea siguiente
## pone las dos cosas a la vez, peleandose por la cola del servidor de render, y
## eso es lo que el log del dispositivo mide como diez segundos de carga
## clavados en un numero fijo de dependencias:
##
##   saliendo de intro.tscn   (189/849 retenidos)   ->  5.3s, sin paron
##   saliendo de la tienda    (459/1722 retenidos)  -> 18.4s, 11s clavado
##   saliendo de sng_chimera  (459/1722 retenidos)  -> 19.0s,  9s clavado
##
## Esto se comprueba sobre el ORDEN y no sobre un tiempo, porque el orden es lo
## unico que se puede afirmar sin un telefono delante: que el `await` este entre
## el desmontaje y la peticion. Un refactor que mueva la peticion arriba o quite
## el await no daria ningun error - volveria a costar diez segundos y nadie
## sabria por que.
##
## Run with:
##   godot --headless --path . --script tools/test_teardown_before_load.gd

const CHANGER := "res://lullaby_mod/scripts/lullaby/loading/lullaby_scene_changer.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	# Sin comentarios: la busqueda es textual, y el fichero MENCIONA
	# `load_threaded_request()` en la documentacion de USE_SUB_THREADS, muy por
	# encima de donde lo llama. Buscando sobre el fichero crudo, `request_at`
	# caia en esa mencion y esta prueba se declaraba rota por una linea de prosa.
	var code: String = _strip_comments(FileAccess.get_file_as_string(CHANGER))
	if not _check(not code.is_empty(), "el scene changer se lee"):
		_finish()
		return

	var unload_at: int = code.find("unload_current_scene()")
	var request_at: int = code.find("load_threaded_request(")
	_check(unload_at >= 0, "sigue desmontando la escena saliente")
	_check(request_at >= 0, "y pidiendo la entrante")
	if unload_at < 0 or request_at < 0:
		_finish()
		return

	_check(unload_at < request_at,
		"el desmontaje va antes que la peticion")

	# Lo que importa: que haya espera EN MEDIO, no en cualquier sitio.
	var between: String = code.substr(unload_at, request_at - unload_at)
	var waits: int = between.count("await get_tree().process_frame")
	_check(waits >= 2,
		"y hay al menos dos fotogramas de espera entre los dos (%d)" % waits)

	# El await tiene que estar DESPUES del desmontaje, no antes: esperar y luego
	# desmontar y pedir en el mismo fotograma seria el mismo fallo con un
	# fotograma perdido de propina.
	var first_wait: int = code.find("await get_tree().process_frame", unload_at)
	_check(first_wait > unload_at and first_wait < request_at,
		"la espera esta entre medias y no antes del desmontaje")

	# Y la funcion sigue pudiendo esperar.
	var func_at: int = code.rfind("func ", unload_at)
	var header: String = code.substr(func_at, 120)
	_check(header.contains("func ") and not header.contains("-> void :\n\tpass"),
		"la funcion que lo hace sigue existiendo")

	_gameover_returns_through_changer()
	_finish()


## Los caminos que VUELVEN a una cancion pasan por SceneChanger.
##
## Todo el orden que fija esta prueba vive dentro de SceneChanger.change_to().
## Una llamada cruda a change_scene_to_file() no lo tiene: destruye la escena
## vieja y carga la nueva a la vez, que es el solape que esto existe para evitar.
##
## Chimera era la ultima que quedaba en la ruta cruda, y el log del dispositivo
## (10229-33620adb) mide la asimetria: entrar al gameover 371ms, volver de el
## 11.843ms clavados, con 123 pipelines creadas y CIEN fallando con
## VkResult -13. Monochrome y Safety Lullaby ya iban por SceneChanger, las dos
## con un comentario explicando por que - o sea que esto es alinear Chimera con
## lo que el resto del codigo ya hacia, no un patron nuevo.
##
## El tercer parametro se comprueba aparte y no es cosmetico: con
## `end_manually` en false, lullaby_preload_camera.gd se salta el precache
## ENTERO en su primera linea, asi que la vuelta entraba a Chimera sin
## precalentar una sola pipeline. Esa es la otra mitad de por que fallaban cien.
func _gameover_returns_through_changer() -> void:
	var path := "res://lullaby_mod/scripts/lullaby/gameover/chimera_gameover.gd"
	var code: String = _strip_comments(FileAccess.get_file_as_string(path))
	if not _check(not code.is_empty(), "chimera_gameover.gd se lee"):
		return

	var fn_at: int = code.find("func _on_gameover_finished(")
	if not _check(fn_at >= 0, "sigue existiendo _on_gameover_finished"):
		return
	var body: String = code.substr(fn_at)
	var next: int = body.find("\nfunc ")
	if next > 0:
		body = body.substr(0, next)

	_check(not body.contains("change_scene_to_file("),
		"la vuelta a Chimera ya no usa change_scene_to_file")
	_check(body.contains("SceneChanger.change_to("),
		"la vuelta a Chimera pasa por SceneChanger")
	# `true` explicito: sin el, el precache no corre y no se precalienta nada.
	_check(body.contains(", true)"),
		"y pide end_manually, sin el cual la precarga se salta entera")


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - se desmonta, se espera, y luego se carga")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok


## Fuera las lineas de comentario, para que una mencion en prosa no se confunda
## con una llamada.
func _strip_comments(code: String) -> String:
	var out: PackedStringArray = []
	for line: String in code.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)
