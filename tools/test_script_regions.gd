extends SceneTree

## Una sonda colgada como ultimo hijo corre DESPUES del subarbol que la precede.
##
## Que esto sea cierto es lo unico que sostiene el reparto por regiones de
## `rest=` en el log de diagnostico. Si Godot llamase `_process` en otro orden
## -por prioridad antes que por arbol, o los hijos antes que los hermanos- el
## reparto no seria impreciso, seria falso: le imputaria a un subarbol el coste
## de otro, y las decisiones de optimizacion se tomarian sobre eso.
##
## Y no es una suposicion gratuita de la que fiarse: `rest=` ya fue durante dias
## el numero mas grande de este log y la respuesta resulto ser que la mayor
## parte era el propio medidor. De ahi que exista `self=`. Un instrumento nuevo
## sin comprobar es esa misma historia otra vez.
##
## No se monta el logger entero a proposito. Instanciarlo fuera de su autoload
## arrastra su fichero, sus estaticos y medio proyecto, y colgo el primer
## intento de esta prueba. Lo que se prueba aqui es la clase `_ScriptProbe` real
## sacada del script, con un receptor de pega: el orden es cosa del motor, no
## del logger.
##
## Run with:
##   godot --headless --path . --script tools/test_script_regions.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

var _failures: int = 0
var _checks: int = 0

## Quien recibe las marcas, en el orden en que llegan.
class _Sink extends Node:
	var order: PackedStringArray = []
	var stamps: Dictionary = {}

	func _stamp_probe(slot: int, now_usec: int) -> void:
		order.append(str(slot))
		stamps[slot] = now_usec


## Gasta un tiempo conocido en su _process, como haria el juego.
class _Burner extends Node:
	var usec: int = 0
	var ran: int = 0

	func _process(_delta: float) -> void:
		ran += 1
		var until: int = Time.get_ticks_usec() + usec
		while Time.get_ticks_usec() < until:
			pass


func _initialize() -> void:
	_tail_checks()
	var script: GDScript = load(LOG)
	if not _check(script != null, "el script de diagnostico carga"):
		_finish()
		return

	var probe_class: Variant = script.get_script_constant_map().get("_ScriptProbe")
	if not _check(probe_class != null, "expone la clase _ScriptProbe"):
		_finish()
		return

	var sink := _Sink.new()
	root.add_child(sink)

	# Tres ramas. La primera quema mucho, la segunda nada, la tercera algo.
	var scene := Node.new()
	scene.name = "Escena"
	root.add_child(scene)

	var burners: Array[Node] = []
	var quemas: Array[int] = [6000, 0, 2000]
	for i: int in 3:
		var rama := Node.new()
		rama.name = "Rama%d" % i
		scene.add_child(rama)
		if quemas[i] > 0:
			var b := _Burner.new()
			b.usec = quemas[i]
			rama.add_child(b)
			burners.append(b)
		# La sonda, ULTIMO hijo de la rama, que es como las cuelga el logger.
		var probe: Node = probe_class.new()
		probe.name = "DiagProbe_Rama%d" % i
		probe.set("log_node", sink)
		probe.set("slot", i)
		rama.add_child(probe)

	# Dos fotogramas: el primero despues de add_child no es representativo.
	await process_frame
	sink.order.clear()
	sink.stamps.clear()
	var inicio: int = Time.get_ticks_usec()
	await process_frame

	_check(sink.stamps.size() == 3,
		"las tres sondas estampan en un fotograma (%d)" % sink.stamps.size())
	if sink.stamps.size() < 3:
		_finish()
		return

	_check(Array(sink.order) == ["0", "1", "2"],
		"y en orden de arbol: %s" % ", ".join(sink.order))

	var t0: int = sink.stamps[0]
	var t1: int = sink.stamps[1]
	var t2: int = sink.stamps[2]
	_check(inicio <= t0 and t0 <= t1 and t1 <= t2,
		"las marcas crecen, o el reparto saldria negativo")

	var r0: int = t0 - inicio
	var r1: int = t1 - t0
	var r2: int = t2 - t1
	print("  regiones (us): Rama0=%d Rama1=%d Rama2=%d" % [r0, r1, r2])

	# Lo que se afirma es la ATRIBUCION, no la precision del reloj, asi que los
	# margenes son anchos: la rama que quema seis milisegundos tiene que salir
	# muy por encima de la que no quema nada.
	_check(r0 >= 3000, "Rama0 carga con sus 6ms (%d us)" % r0)
	_check(r1 <= 1000, "Rama1, que no quema, sale barata (%d us)" % r1)
	_check(r2 >= 1000, "Rama2 carga con sus 2ms (%d us)" % r2)
	_check(r0 > r2, "y Rama0 sale por encima de Rama2, que es lo que quemaron")

	# Un subarbol con el proceso apagado NO estampa. Es el caso real de
	# LullabyCutsceneVideo, que apaga su cutscene mientras el video la tapa: sin
	# esto, el hueco se le imputaria por error a la region siguiente.
	scene.get_node(^"Rama0").process_mode = Node.PROCESS_MODE_DISABLED
	sink.order.clear()
	sink.stamps.clear()
	await process_frame
	_check(not sink.stamps.has(0),
		"un subarbol con el proceso apagado no estampa")
	_check(sink.stamps.has(2),
		"y los de al lado siguen midiendo")

	_hidden_checks(script)

	scene.free()
	sink.free()
	_finish()


## El recuento de nodos ocultos que procesan, que es la cifra accionable.
##
## Se comprueba porque es la unica de la linea que ya viene con una accion
## implicita -"esto corre sin dibujarse, quitalo"- y un recuento equivocado
## mandaria a perseguir fantasmas. Peepers fueron 256 callbacks ocultos y nadie
## los vio hasta que un contador de shaders lo delato.
##
## El logger se instancia SIN meterlo en el arbol: asi no corre su `_ready` ni
## su `_process`, que es lo que colgo la primera version de esta prueba.
func _hidden_checks(script: GDScript) -> void:
	var log_node: Node = script.new()

	var raiz := Node2D.new()
	root.add_child(raiz)

	# Dos visibles que procesan, uno oculto que procesa, y uno oculto que no.
	for i: int in 2:
		var v := Node2D.new()
		v.set_process(true)
		raiz.add_child(v)

	var escondido := Node2D.new()
	escondido.visible = false
	raiz.add_child(escondido)
	var dentro := Node2D.new()
	dentro.set_process(true)
	escondido.add_child(dentro)

	var quieto := Node2D.new()
	quieto.visible = false
	quieto.set_process(false)
	raiz.add_child(quieto)

	var counts: Array = log_node.call("_count_processing", raiz)
	_check(int(counts[0]) == 3,
		"cuenta los 3 nodos que procesan, no los 5 que hay (%d)" % counts[0])
	# El hijo de un padre invisible cuenta como oculto aunque su propio
	# `visible` sea true: lo que decide es is_visible_in_tree().
	_check(int(counts[1]) == 1,
		"y 1 de ellos esta oculto, por el padre y no por si mismo (%d)" % counts[1])

	raiz.free()
	log_node.free()


## El tramo de despues de la ultima sonda se acumula y se reporta.
##
## Era el punto ciego: el bucle camina de sonda en sonda, asi que lo que va de la
## ultima al cierre del corchete no se le imputaba a nadie y caia entero en
## `rest=`. El log 10226-4fe0a6db lo enseño sin poder nombrarlo:
##
##     REGIONS n=1696 script_max=19.06ms rest=17.64ms | (todo <0.1ms)
##
## Todas las regiones bajo 0.1ms y 17.64ms sin dueño. Ahi vive todo lo que se
## cuelgue de la escena DESPUES de `_install_probes()` - que corre una sola vez,
## al cargar - y ordene por detras del ultimo hijo con sonda. El CanvasLayer que
## `LullabyCutsceneVideo` crea en caliente es justo eso.
func _tail_checks() -> void:
	var f := FileAccess.open(LOG, FileAccess.READ)
	var code: String = "" if f == null else f.get_as_text()

	_check(code.contains("_probe_tail_acc += maxi(0, now_usec - walk)"),
		"el tramo final se acumula, en vez de caer en rest")
	_check(code.contains("_peak_tail = maxi(0"),
		"y tambien se reparte en el fotograma del record")

	# Sin umbral y siempre presente: esconderla tras un `<0.1ms` seria repetir el
	# error que hizo falta un log entero para leer.
	var at: int = code.find("func _regions_text(")
	var next: int = code.find("\nfunc ", at + 1)
	var body: String = "" if at < 0 else code.substr(at, -1 if next < 0 else next - at)
	_check(body.contains("(cola)="),
		"la cola se escribe con nombre propio en la linea")
	_check(not body.contains('"(todo <0.1ms)"'),
		"y ya no existe el `(todo <0.1ms)` que ocultaba justo esto")
	_check(body.contains("tail_text if rest_text.is_empty()"),
		"se escribe aunque no haya ninguna otra region que superara el umbral")

	# Y que se reinicie con el resto, o cada linea acumularia desde el arranque.
	_check(code.contains("_probe_tail_acc = 0"),
		"se reinicia por intervalo, como _probe_acc")


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - las regiones atribuyen a quien gasta")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
