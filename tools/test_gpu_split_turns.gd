extends SceneTree

## Cada turno de GPUSPLIT esta cableado entero: sonda, salida y restauracion.
##
## GPUSPLIT mide el fotograma apagando una cosa cada vez y restando. Anadir un
## turno son tres sitios - la `match` que aplica la sonda, la rama que escribe
## la linea, y el restaurador que lo deshace - y olvidarse del tercero deja el
## viewport del jugador sin 3D, sin sombras o sin Environment PARA SIEMPRE,
## porque el estado se aplica en un fotograma y se deshace en el siguiente.
## Nada da un error: la escena simplemente se queda mal.
##
## Por eso esto lee el fuente en vez de ejecutar. Ejecutarlo de verdad pide un
## dispositivo: `_step_gpu_split()` sale antes si no hay camara 3D o si
## `_visual3d_load()` es cero, y esa lista solo la rellena `SceneChanger` (o
## `rescan_scene()` a mano). Y aunque arrancara, medir aqui no valdria: bajo
## xvfb el adaptador es llvmpipe y la tienda corre a unos 2 fps con
## `gpu=561ms`, asi que cualquier reparto seria ruido. Lo que un guard SI puede
## garantizar es que las tres piezas existen para cada turno.
##
## Run with:
##   godot --headless --path . --script tools/test_gpu_split_turns.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

## Lo que cada turno apaga y lo que su linea tiene que nombrar. El indice es el
## valor de `_gpu_split_turn`.
const TURNS: Array = [
	["debug_draw = Viewport.DEBUG_DRAW_UNSHADED", "sin_luz="],
	["debug_draw = Viewport.DEBUG_DRAW_OVERDRAW", "overdraw="],
	["disable_3d = true", "sin_3d="],
	["_gpu_split_shadows_off()", "sin_sombras="],
	["_gpu_split_env_off()", "sin_post="],
]

## Lo que el restaurador tiene que deshacer, pase el turno que pase.
const RESTORES: Array[String] = [
	"debug_draw = Viewport.DEBUG_DRAW_DISABLED",
	"disable_3d = false",
	"shadow_enabled = true",
	"world.environment = _gpu_split_env",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var src: String = FileAccess.get_file_as_string(LOG)
	if not _check(not src.is_empty(), "el log de diagnostico se lee"):
		_finish()
		return

	# La constante y la lista de aqui tienen que decir lo mismo. Si alguien sube
	# GPU_SPLIT_TURNS y no toca este fichero, el turno nuevo rota sin sonda: se
	# gasta un fotograma raro y no escribe nada.
	var declared: int = _int_after(src, "const GPU_SPLIT_TURNS := ")
	_check(declared == TURNS.size(),
		"GPU_SPLIT_TURNS (%d) coincide con los turnos cableados aqui (%d)"
			% [declared, TURNS.size()])

	for i: int in range(TURNS.size()):
		var probe: String = TURNS[i][0]
		var field: String = TURNS[i][1]
		_check(src.contains("%d: " % i) and src.contains(probe),
			"turno %d aplica su sonda (%s)" % [i, probe])
		_check(src.contains(field),
			"turno %d escribe su campo (%s)" % [i, field])

	# El restaurador, que es la parte cuyo olvido no se nota hasta que un
	# jugador se queda sin sombras el resto de la partida.
	var at: int = src.find("func _gpu_split_restore")
	if _check(at > 0, "existe _gpu_split_restore()"):
		var body: String = src.substr(at, 1400)
		for what: String in RESTORES:
			_check(body.contains(what), "y deshace `%s`" % what)

	# Y que se llame SIEMPRE, no dentro de una rama por turno.
	_check(src.contains("var probed: float = _viewport_gpu_ms()\n\t_gpu_split_restore()"),
		"la restauracion va justo tras la lectura, sin condicion de por medio")

	# Las sombras se guardan para devolver EXACTAMENTE las que estaban puestas.
	# Encenderlas todas dejaria encendidas las que el autor apago a mano.
	_check(src.contains("if light != null and light.shadow_enabled and light.is_visible_in_tree()"),
		"solo se apagan las luces que tenian sombra y estan visibles")

	# `null` es un Environment valido, asi que la bandera no puede ser `!= null`.
	_check(src.contains("if _gpu_split_had_env:"),
		"el Environment se restaura por bandera y no por != null")

	# --- Que no se mida durante la tormenta de montaje ----------------------
	#
	# Sin esto la primera muestra de cada escena cae dentro del montaje y el
	# reparto que escribe es falso: en el log del 14-09, `base=64.70ms` contra
	# los 13.62ms que la misma escena cuesta nueve segundos despues.
	_check(src.contains("const GPU_SPLIT_SETTLE_SECONDS := "),
		"hay una espera de asentamiento declarada")
	_check(src.contains("if _gpu_split_pipe_still_ms < GPU_SPLIT_SETTLE_SECONDS * 1000.0:"),
		"y la sonda no se aplica hasta que el contador de pipelines lleva quieto")

	# El turno no se pierde por esperar: si esta rama reiniciara el reloj de los
	# veinte segundos, una escena que compila a rachas no mediria nunca.
	var gate: int = src.find("if _gpu_split_pipe_still_ms <")
	var reset: int = src.find("_time_since_gpu_split = 0.0", gate)
	var probe: int = src.find("match _gpu_split_turn:", gate)
	_check(gate > 0 and reset > 0 and probe > 0 and reset < probe,
		"esperar no gasta el turno: el reloj solo se reinicia al sondear")

	# El reloj de pipelines corre TAMBIEN durante los veinte segundos de espera.
	# Si solo corriera despues, cada muestra pagaria cuatro segundos extra.
	var still: int = src.find("_gpu_split_pipe_still_ms += _last_frame_wall_ms")
	var wait: int = src.find("if _time_since_gpu_split < GPU_SPLIT_SECONDS")
	_check(still > 0 and wait > 0 and still < wait,
		"y el reloj de pipelines corre antes de la espera de los 20s")

	# --- Que la sonda declare lo que ella misma costo -----------------------
	#
	# Los turnos 0 y 1 escriben `debug_draw`, que en el renderizador movil es
	# otra version de shader: cada material a la vista compila una pipeline en
	# ese fotograma. El log del 14-09 midio +16 pipelines y 161ms de tiron.
	_check(src.contains("_pipeline_compilations() - _gpu_split_pipe_at_probe"),
		"la sonda mide las pipelines que creo")
	_check(src.contains('" sonda_pipe=+%d" % probe_pipe'),
		"y el campo se construye")
	# Las cinco lineas, no solo la del turno caro: un cero tambien es dato.
	#
	# Dos sangrados porque el turno 0 es el unico que no vive dentro de un `if`
	# - es el caso por defecto al final de la funcion - asi que su `])` cierra
	# con una tabulacion menos. Contar solo la forma de dentro del `if` daba
	# 4 de 5 y habria dejado esa linea sin el campo.
	var written: int = src.count(", cost,\n\t\t])") + src.count(", cost,\n\t])")
	_check(written == TURNS.size(),
		"las cinco lineas lo escriben (%d de %d)" % [written, TURNS.size()])

	_finish()


func _int_after(src: String, key: String) -> int:
	var at: int = src.find(key)
	if at < 0:
		return -1
	var rest: String = src.substr(at + key.length(), 8)
	var digits: String = ""
	for c: String in rest:
		if c.is_valid_int():
			digits += c
		else:
			break
	return int(digits) if not digits.is_empty() else -1


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - los cinco turnos aplican, escriben y se deshacen")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
