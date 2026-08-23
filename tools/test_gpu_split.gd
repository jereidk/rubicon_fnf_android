extends SceneTree

## GPUSPLIT parte el frame de la GPU en luz, relleno y resto - la medida que
## este proyecto lleva toda la vida necesitando y no tenia.
##
## `gpu=` es un solo numero para el frame entero, asi que "Chimera es
## iluminacion por fragmento" y "Chimera es sobredibujado 3D" encajan los dos
## y ninguno se puede descartar. El dispositivo lo puede contestar solo:
## `Viewport.debug_draw` redibuja la misma escena sin luz (UNSHADED) o con cada
## fragmento reducido a una mezcla aditiva trivial (OVERDRAW), y
## `viewport_get_measured_render_time_gpu()` no cuesta nada de leer.
##
##     base - sin_luz   = lo que cuesta la matematica de luz por fragmento
##     overdraw         = lo que cuesta rasterizar esa complejidad de
##                        profundidad, sin sombrear
##
## Sin ninguna lectura GPU->CPU, que es lo que hizo caro al viejo `sonda=`
## hasta borrarlo.
##
## Lo que este guard fija, por orden de lo que se rompe primero:
##
## 1. **El desfase de un frame.** `viewport_get_measured_render_time_gpu()` va
##    una atras, asi que cada paso lee el frame que preparo el paso anterior.
##    Leer y escribir en el mismo paso mediria el frame equivocado y saldrian
##    tres numeros creibles y falsos.
## 2. **`debug_draw` siempre se restaura**, y antes de cualquier `return`
##    temprano - dejarlo puesto deja el juego en blanco.
## 3. **Es opt-in.** Dos frames por muestra salen mal a proposito.
## 4. **El reloj es el de pared**, no `delta`. La regla de este fichero.
##
##   godot --headless --path . --script tools/test_gpu_split.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"
const SETTINGS := "res://menus/settings.gd"
const HACKS := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/hacks_tab.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var src: String = _read(LOG)
	_check(src != "", "el log se lee")

	var body: String = _func_body(src, "_step_gpu_split")
	_check(body != "", "_step_gpu_split existe")

	# 1. El desfase de un frame: en cada paso se LEE antes de escribir el modo
	#    siguiente. Si alguien invierte el orden, los tres numeros siguen
	#    saliendo y ninguno mide lo que dice.
	var read_base: int = body.find("_gpu_split_base = _viewport_gpu_ms()")
	var set_unshaded: int = body.find("Viewport.DEBUG_DRAW_UNSHADED")
	var read_unshaded: int = body.find("_gpu_split_unshaded = _viewport_gpu_ms()")
	var set_overdraw: int = body.find("Viewport.DEBUG_DRAW_OVERDRAW")
	var read_overdraw: int = body.find("var overdraw: float = _viewport_gpu_ms()")
	var restore: int = body.find("Viewport.DEBUG_DRAW_DISABLED")
	for pair: Array in [[read_base, set_unshaded, "base se lee antes de pedir UNSHADED"],
			[set_unshaded, read_unshaded, "UNSHADED se pide antes de leerlo"],
			[read_unshaded, set_overdraw, "sin_luz se lee antes de pedir OVERDRAW"],
			[set_overdraw, read_overdraw, "OVERDRAW se pide antes de leerlo"],
			[read_overdraw, restore, "overdraw se lee antes de restaurar"]]:
		_check(pair[0] >= 0 and pair[1] >= 0 and pair[0] < pair[1], pair[2])

	# 2. Restaurar pase lo que pase. La unica salida despues del ultimo paso es
	#    la de "el driver no contesta", y tiene que ir DESPUES del restore.
	var early_out: int = body.find("if _gpu_split_base <= 0.0:")
	_check(early_out >= 0 and restore < early_out,
		"debug_draw se restaura antes de la salida por driver mudo")
	_check(body.find("_gpu_split_state = 0", restore) >= 0,
		"y el ciclo se cierra ahi mismo")

	# Y el ciclo en vuelo no se puede abortar a media: el ajuste solo se mira
	# en el paso 0, asi que apagarlo mientras corre no deja el viewport en
	# modo depuracion.
	var gate: int = body.find("lullaby_diagnostics_gpu_split")
	_check(gate >= 0 and gate < set_unshaded,
		"el ajuste solo se consulta al empezar un ciclo, nunca a mitad")

	# 3. Opt-in, y apagado de fabrica.
	var settings: String = _read(SETTINGS)
	_check(settings.contains("var lullaby_diagnostics_gpu_split: bool = false"),
		"el ajuste existe y sale apagado")
	_check(_read(HACKS).contains('const GPU_SPLIT_CODE := "GPUSPLIT"'),
		"y se enciende con un codigo, no con una fila de preferencias")

	# 4. El reloj de pared, no delta - la regla de este fichero, que ya dejo
	#    mudos a cuatro temporizadores en los frames que existian para medir.
	_check(_has_statement(body, "_time_since_gpu_split += _last_frame_wall_ms"),
		"el temporizador se alimenta del reloj de pared")
	_check(not _has_statement(body, "_time_since_gpu_split += delta"),
		"y no de delta")

	# 5. Solo donde significa algo: sin camara 3D o sin nada visible, las tres
	#    lecturas serian el canvas 2D tres veces.
	_check(_has_statement(body, "get_viewport().get_camera_3d()"),
		"solo corre con una camara 3D activa")
	_check(_has_statement(body, "_visual3d_load() <= 0"),
		"y con algo 3D visible")

	# 6. Y tres ceros no son una medida.
	_check(_has_statement(body, "if _gpu_split_base <= 0.0:"),
		"un driver que no contesta no produce una linea")

	# 7. Las superficies no opacas se cuentan POR SUPERFICIE: lo que anula el
	#    rechazo temprano por profundidad es cuanta pantalla descarta, y un
	#    material compartido puede estar en veinte paredes.
	_check(src.contains("base_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED"),
		"no_opacas cuenta cualquier modo que no sea OPAQUE")
	_check(src.contains("no_opacas=%d"), "y sale en BLACKWATCH")

	_finish()


func _func_body(src: String, name: String) -> String:
	var start: int = src.find("func %s(" % name)
	if start < 0:
		return ""
	var rest: String = src.substr(start)
	var next: int = rest.find("\nfunc ", 1)
	return rest.substr(0, next) if next > 0 else rest


func _has_statement(src: String, needle: String) -> bool:
	for line: String in src.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
