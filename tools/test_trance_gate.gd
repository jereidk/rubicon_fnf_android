extends SceneTree

## El gate de los dos rects de Safety Lullaby no puede quitar nada que se vea.
##
## `trance_shaders.gd` esconde `%WaterEffect` y `%RadialEffect` cuando
## `_effects_strength` baja de `NEUTRAL_EPSILON`. Los dos son ColorRect a
## pantalla completa sobre `hint_screen_texture`, o sea que cada uno cuesta una
## copia de framebuffer -lo mas caro que se le puede pedir a una GPU de tiles-
## mas una mezcla a pantalla completa, y los dos shaders tienen una rama de
## identidad. Medido en aislado sobre la ruta del telefono (Vulkan, Forward
## Mobile, 1600x720, el shader real):
##
##     activo (15 muestras/pixel)   49.7ms   draws=2
##     identidad                    20.0ms   draws=2
##     oculto                        6.7ms   draws=1
##
## El `draws=2 -> 1` es lo importante: esconder el rect se lleva la copia con
## el. La copia la inserta el motor por el material, no es un nodo, asi que
## sigue la visibilidad del CanvasItem que la pide - al reves que el
## `BackBufferCopy` explicito de `intro.tscn`, que copia lo lea alguien o no.
##
## Lo que este fichero fija es el otro lado del trato: que el corte esta lo
## bastante abajo. Con `_effects_strength = e` el termino que mas pesa es la
## saturacion, `1 - 0.275 * e`, o sea una desviacion de como mucho `0.275 * e`
## sobre un canal, y medio paso de 8 bits es `0.5 / 255`. Eso da `e < 0.0071`.
##
## Comprobado ademas renderizando: una rampa de 640x360 que recorre matiz,
## saturacion y valor, pasada por los DOS shaders reales con los parametros
## que produce cada e, diffeada contra la misma rampa sin pasar por nada:
##
##     e = 0.0020   peor error 0/255   0 canales de 691200
##     e = 0.0071   peor error 0/255   0
##     e = 0.0200   peor error 0/255   0
##     e = 0.1000   peor error 1/255   1658  (0.24%)
##
## O sea 10x de margen real hasta la primera diferencia medible, y la ultima
## fila prueba que el metodo detecta un efecto de verdad en vez de pasar en
## vacio. Ese barrido necesita un framebuffer y CI no tiene display, asi que
## aqui queda la aritmetica, que es lo que puede derivar en silencio.
##
## Run with:
##   godot --headless --path . --script tools/test_trance_gate.gd

const SCRIPT_PATH := "res://lullaby_mod/songs/safety_lullaby/trance_shaders.gd"
const SCENE_PATH := "res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn"

## El coeficiente con el que `_effects_strength` entra en la saturacion, que es
## el mas grande de los cuatro terminos.
const SATURATION_COEFFICIENT := 0.275

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var source: String = _read(SCRIPT_PATH)
	if source == "":
		printerr("FALLO: no se pudo leer %s" % SCRIPT_PATH)
		quit(1)
		return

	var epsilon: float = _float_after(source, "const NEUTRAL_EPSILON := ")
	_check(epsilon > 0.0, "NEUTRAL_EPSILON existe y es positivo (leido: %s)" % epsilon)

	# La cota: por debajo de esto el efecto no llega a medio paso de 8 bits.
	var bound: float = (0.5 / 255.0) / SATURATION_COEFFICIENT
	_check(epsilon < bound,
		"NEUTRAL_EPSILON (%.4f) por debajo de medio paso de 8 bits (%.4f)" % [epsilon, bound])

	# Y no tan abajo que el gate no llegue a cerrarse nunca: `_effects_strength`
	# decae de forma exponencial hacia 0 y no lo alcanza jamas, asi que un
	# epsilon de cero -o de un float denormal- deja los dos rects encendidos
	# para siempre y el arreglo entero es inerte.
	_check(epsilon >= 1e-4,
		"NEUTRAL_EPSILON (%.4f) lo bastante alto para que el decaimiento lo cruce" % epsilon)

	# El gate tiene que correr en los dos sitios. Solo en `_process` deja un
	# frame de pase identidad antes del primero; solo en `_ready` no se entera
	# de nada despues.
	_check(source.contains("func _ready()"), "hay un _ready()")
	_check(source.count("_update_rect_visibility()") >= 3,
		"_update_rect_visibility se define y se llama desde _ready y _process")

	# Los parametros se siguen escribiendo con el rect oculto: si se saltaran,
	# al volver el material traeria el valor viejo un frame.
	var process_body: String = source.substr(source.find("func _process("))
	_check(process_body.find("set_shader_parameter")
			< process_body.find("_update_rect_visibility()"),
		"los parametros se escriben antes de decidir la visibilidad")

	# Y los dos nodos tienen que existir con ese nombre unico, o `%X` explota
	# en tiempo de ejecucion y no lo ve nadie hasta el telefono.
	var scene: String = _read(SCENE_PATH)
	for unique_name in ["WaterEffect", "RadialEffect"]:
		_check(scene.contains('name="%s"' % unique_name),
			"%s sigue en la escena" % unique_name)
		_check(source.contains("%%%s" % unique_name),
			"%s se busca por nombre unico" % unique_name)

	# Nada debe autorarlos ocultos: el gate es el unico dueño de ese `visible`,
	# y una pista de animacion sobre el mismo campo se pelearia cada frame.
	_check(not scene.contains('path=&"WaterShaderLayer/WaterEffect:visible"'),
		"ninguna pista de animacion escribe WaterEffect:visible")
	_check(not scene.contains('path=&"RadialShaderLayer/RadialEffect:visible"'),
		"ninguna pista de animacion escribe RadialEffect:visible")

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


func _float_after(text: String, needle: String) -> float:
	var at: int = text.find(needle)
	if at < 0:
		return -1.0
	var rest: String = text.substr(at + needle.length())
	var digits: String = ""
	for i in rest.length():
		var c: String = rest[i]
		if (c >= "0" and c <= "9") or c == "." or c == "e" or c == "-":
			digits += c
		else:
			break
	return float(digits) if digits != "" else -1.0
