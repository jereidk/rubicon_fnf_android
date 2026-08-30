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
	var code: String = FileAccess.get_file_as_string(CHANGER)
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

	_finish()


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
