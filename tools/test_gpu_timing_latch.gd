extends SceneTree

## `gpu=0.00ms` no siempre significa que la GPU no hizo nada.
##
## Hay drivers que no contestan a `viewport_get_measured_render_time_gpu`. El
## moto g(60)s (Mali-G76 MC4, driver 1.1.131) devuelve 0.00 en las **492**
## entradas de `dcb37c09`, con `cpu_render` variando normalmente al lado - o
## sea que la CPU de render se mide bien y la GPU no se mide en absoluto. Un
## cero se lee como un frame gratis, que es lo contrario de la verdad, y toda
## comparacion entre dispositivos de este proyecto se apoya en `gpu=`.
##
## El discriminador es la pareja, no el cero suelto: si de verdad no se
## dibujara nada, `cpu_render` estaria tambien a cero. Contado sobre los 33
## logs que tiene el proyecto, la racha maxima de entradas con `gpu == 0` y
## `cpu_render > 0`:
##
##     moto g(60)s (Mali-G76)      492 de 492 entradas
##     los otros cinco modelos       0
##
## Cero en todos los que contestan, incluidas las dos entradas sueltas con
## `gpu=0.00` que aparecen en dos logs del g53 - ahi `cpu_render` tambien
## esta a cero, o sea que la pareja ya las excluye. El umbral de 12 tiene
## todo el margen del mundo por los dos lados.
##
## Este fichero no se puede cargar en un proyecto de usar y tirar (sus
## dependencias de `class_name` lo cuelgan), asi que la comprobacion es
## estructural sobre el texto - la misma forma que usan los otros chequeos
## de este log. Lo que fija son las cuatro propiedades que, si se rompen,
## devuelven el `0.00` mentiroso sin que nada avise.
##
## Run with:
##   godot --headless --path . --script tools/test_gpu_timing_latch.gd

const LOG_PATH := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null:
		printerr("FALLO: no se pudo abrir %s" % LOG_PATH)
		quit(1)
		return
	var source: String = file.get_as_text()
	file.close()

	# Sin los comentarios: este fichero se explica a si mismo y varias de las
	# cadenas que se buscan aqui aparecen tambien en su prosa.
	var code: String = _strip_comments(source)

	# 1. El campo tiene que ser %s. Con %.2f el pestillo no puede llegar a la
	#    linea por mucho que se eche - la deteccion sale gratis y no sirve.
	_check(code.contains("gpu=%sms"), "gpu= se escribe con %s")
	_check(not code.contains("gpu=%.2fms"), "no queda ningun gpu= con %.2f")
	_check(code.contains("sub_gpu=%sms"), "sub_gpu= se escribe con %s")

	# 2. Y los dos argumentos tienen que pasar por el ayudante.
	_check(code.contains("_gpu_field(gpu_ms)"), "gpu_ms va por _gpu_field()")
	_check(code.contains("_gpu_field(sub_gpu_ms)"), "sub_gpu_ms va por _gpu_field()")
	_check(code.contains("func _gpu_field("), "_gpu_field existe")

	# 3. La condicion exige cpu_render por encima de cero. Sin esa mitad, cada
	#    pantalla de carga y cada arranque -donde no se dibuja nada y los dos
	#    contadores estan a cero- echaria el pestillo, y el dispositivo
	#    perderia su medida de GPU para el resto de la sesion por no dibujar
	#    durante doce entradas seguidas.
	_check(code.contains("gpu_ms <= 0.0 and cpu_render_ms > 0.0"),
		"el pestillo exige cpu_render > 0, no solo gpu == 0")

	# 4. Y se suelta en cuanto llega una medida buena, o una racha repartida
	#    por toda la sesion acabaria echandolo igual.
	_check(code.contains("_gpu_zero_entries = 0"), "la racha se reinicia al medir algo")

	# 5. Una vez echado no se suelta: el driver no cambia dentro de una
	#    sesion, y soltarlo devolveria el 0.00 mentiroso a mitad de log.
	_check(code.count("_gpu_timing_unsupported = true") == 1,
		"el pestillo se echa en un solo sitio")
	_check(not code.contains("_gpu_timing_unsupported = false"),
		"el pestillo nunca se suelta")

	# 6. El umbral tiene que dejar margen sobre lo unico que se ha visto en un
	#    dispositivo sano: cero. Doce entradas son unos segundos.
	var threshold: int = _int_after(code, "const GPU_TIMING_UNSUPPORTED_ENTRIES := ")
	_check(threshold >= 8, "el umbral (%d) no dispara con un puñado de entradas" % threshold)
	_check(threshold <= 60, "el umbral (%d) no tarda media sesion en decidirse" % threshold)

	# 7. Y cuando se echa, lo dice. Un log que empieza a escribir n/d sin
	#    explicar por que es peor que uno que escribe ceros.
	_check(code.contains("\"GPUTIMING\""), "se emite una entrada al echar el pestillo")

	print("%d comprobaciones, %d fallos%s" % [_checks, _failures,
		"" if _failures == 0 else ""])
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


func _int_after(code: String, needle: String) -> int:
	var at: int = code.find(needle)
	if at < 0:
		return -1
	var rest: String = code.substr(at + needle.length())
	var digits: String = ""
	for i in rest.length():
		var c: String = rest[i]
		if c >= "0" and c <= "9":
			digits += c
		else:
			break
	return int(digits) if digits != "" else -1


## Fuera los comentarios, respetando las comillas: `#` dentro de una cadena no
## abre comentario, y varias de las cadenas de formato de este log llevan uno.
func _strip_comments(text: String) -> String:
	var out: String = ""
	for line in text.split("\n"):
		var quote: String = ""
		var cut: int = -1
		for i in line.length():
			var c: String = line[i]
			if quote != "":
				if c == quote:
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
		out += (line if cut < 0 else line.substr(0, cut)) + "\n"
	return out
