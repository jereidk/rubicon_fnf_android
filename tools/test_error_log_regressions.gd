extends SceneTree

## Tres errores del .error del dispositivo que llevaban todo el port sin tocar.
##
## Ninguno se ve jugando, y por eso siguen ahi. Los tres salen del mismo log,
## 10226-4fe0a6db, y los tres son de la misma familia: trabajo que llega en el
## momento equivocado del ciclo de vida.
##
## 1. RETIRAR UN CollisionObject DENTRO DE UN CALLBACK DE FISICA
##
##        ERROR Removing a CollisionObject node during a physics callback is not
##              allowed and will cause undesired behavior. Remove with
##              call_deferred() instead.        collision_object_3d.cpp:119
##
##    `mch_crawling._on_player_body_entered()` llega desde `body_entered`, o sea
##    desde dentro del paso de fisica, y acaba en `switch_to_gameover()`, que
##    cambia de escena - destruye el nivel entero y todos sus CollisionObject
##    mientras el servidor de fisica los esta recorriendo.
##
## 2. UN TWEEN VACIO CREADO EN UN INICIALIZADOR DE MIEMBRO
##
##        ERROR Tween (bound to .../Heart/HeartbeatController): started with no
##              Tweeners.                        tween.cpp:366
##
##    `var vignette_tween = create_tween()` a nivel de clase: nace al construirse
##    el nodo, sin Tweeners, Godot lo arranca solo y se queja. Ademas sobraba -
##    se reasigna con uno de verdad al primer latido.
##
## 3. REPRODUCIR AUDIO CON EL NODO YA FUERA DEL ARBOL
##
##        ERROR Playback can only happen when a node is inside the scene tree
##              audio_stream_player_internal.cpp:145
##
##    El `timeout` del gameover llega despues del `change_scene_to_file()` de al
##    lado, con la escena ya retirada. En el log cae a los 311.76s, cuatro
##    decimas antes del desmontaje que se mide como `vram_delta=-168.0MB`.
##
## Run with:
##   godot --headless --path . --script tools/test_error_log_regressions.gd

const CRAWL := "res://lullaby_mod/resources/funkin/songs/chimera/mch_crawling.gd"
const HEART := "res://lullaby_mod/scripts/lullaby/mechanics/chimera/heartbeat_controller.gd"
const OVER := "res://lullaby_mod/scripts/lullaby/gameover/chimera_gameover.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	# 1
	var crawl: String = _strip_comments(_read(CRAWL))
	var body: String = _func_body(crawl, "_on_player_body_entered")
	_check(not body.is_empty(), "sigue existiendo _on_player_body_entered")
	_check(body.contains("check_completion.call_deferred()"),
		"el gameover se difiere al final del fotograma")
	_check(not body.contains("\tcheck_completion()"),
		"y ya no se llama en plena señal de fisica")

	# 2
	# Sin comentarios: la cabecera de este mismo fichero CITA la linea que
	# prohibe, y buscarla sobre el texto crudo se encuentra a si misma. Es la
	# tercera vez en esta sesion que un guard textual se cree roto por una linea
	# de prosa, asi que aqui se corta de raiz.
	var heart: String = _strip_comments(_read(HEART))
	_check(not heart.contains("var vignette_tween = create_tween()"),
		"el tween del viñeteado ya no se crea en el inicializador")
	_check(heart.contains("var vignette_tween: Tween = null"),
		"se declara vacio, tipado")
	_check(heart.contains("if vignette_tween != null and vignette_tween.is_running()"),
		"y el primer latido comprueba null antes de usarlo - sin esto seria un crash")

	# 3
	var over: String = _strip_comments(_read(OVER))
	var timeout: String = _func_body(over, "_on_timer_timeout")
	_check(not timeout.is_empty(), "sigue existiendo _on_timer_timeout")
	var guard_at: int = timeout.find("is_inside_tree()")
	var play_at: int = timeout.find(".play()")
	_check(guard_at >= 0, "comprueba estar en el arbol")
	_check(guard_at >= 0 and play_at >= 0 and guard_at < play_at,
		"y lo comprueba ANTES de reproducir, que es lo unico que sirve")

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - los tres errores del ciclo de vida estan cerrados")
	quit(1 if _failures > 0 else 0)


## Fuera las lineas de comentario, para que una cita no cuente como codigo.
func _strip_comments(code: String) -> String:
	var out: PackedStringArray = []
	for line: String in code.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


func _func_body(code: String, name: String) -> String:
	var at: int = code.find("func %s(" % name)
	if at < 0:
		return ""
	var next: int = code.find("\nfunc ", at + 1)
	return code.substr(at, -1 if next < 0 else next - at)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
