extends SceneTree

## Errors actually reach a file the player can send.
##
## The gap: until now the only errors anything recorded were the six that go
## through ErrorHandler.show_warning()/show_error() by hand, all of them fatal
## load failures. Every push_error, every push_warning and every red engine
## error went to Android's logcat and nowhere else - including
## console_late_resources.gd's warning for a deferred path that does not
## resolve, which is a warning written specifically to report a failure and
## which reached nobody. Asked directly: "por que el log realmente no dice los
## errores? nunca he visto que escriba errores". It never did.
##
## This drives the real Logger rather than reading the source, because every
## claim here is about runtime behaviour that text cannot show: whether
## OS.add_logger() delivers, whether an engine-side error arrives and not only
## our own push_error, whether repeats collapse, whether the cap holds.
##
## It drives the whole thing, file included: _pick_dir() lands on user://logs
## off Android, so the file it writes is outside the checkout and rotates
## itself to five. That matters here, because one of the claims below is about
## what actually reaches the file rather than what reaches the signal.
##
## Run with:
##   godot --headless --path . --script tools/test_error_log.gd

const SCRIPT := "res://lullaby_mod/scripts/lullaby/debug/lullaby_error_log.gd"
const DIAG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame

	_autoload_checks()
	await _capture_checks()
	_wiring_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _autoload_checks() -> void:
	var project: String = FileAccess.get_file_as_string("res://project.godot")
	_check(project.contains('ErrorLog="*res://lullaby_mod/scripts/lullaby/debug/lullaby_error_log.gd"'),
		"ErrorLog esta declarado como autoload")

	# Primero de la lista: un autoload solo puede capturar lo que pase despues
	# de que exista, y los errores de arranque de los demas autoloads son
	# exactamente los que nadie ve nunca.
	#
	# Contra la PRIMERA linea de autoload de verdad. La primera version de esta
	# comprobacion buscaba el siguiente autoload *despues* de ErrorLog, que
	# siempre existe, asi que era cierta estuviera donde estuviera - moverlo al
	# medio de la lista pasaba en verde.
	var block: String = project.substr(project.find("[autoload]"))
	var first: int = block.find("=\"*res://")
	var line_start: int = block.rfind("\n", first) + 1
	var first_name: String = block.substr(line_start, first - line_start)
	_check(first_name == "ErrorLog",
		"y es el PRIMERO de la lista, o no ve el arranque de los demas (es '%s')" % first_name)


## The part no amount of reading can establish: that it catches anything.
func _capture_checks() -> void:
	var script: GDScript = load(SCRIPT)
	_check(script != null, "lullaby_error_log.gd carga")
	if script == null:
		return

	var log_node: Node = script.new()
	root.add_child(log_node)
	await process_frame

	# Sin errores no hay fichero: una sesion limpia no deja rastro, que es lo
	# que permite tenerlo siempre encendido.
	_check(log_node.get("_file") == null, "sin errores no se abre ningun fichero")

	var heard: Array[String] = []
	log_node.captured.connect(func(kind: String, _where: String, message: String) -> void:
		heard.append("%s %s" % [kind, message]))

	# Los tres caminos, por el Logger de verdad.
	push_error("prueba error de guarda")
	push_warning("prueba warning de guarda")
	var sprite := AnimatedSprite2D.new()
	sprite.animation = &"animacion_que_no_existe"   # error del motor, no nuestro
	sprite.free()
	await process_frame

	var joined: String = " || ".join(heard)
	_check(joined.contains("prueba error de guarda"), "captura push_error")
	_check(joined.contains("prueba warning de guarda"), "captura push_warning")
	_check(joined.contains("animacion_que_no_existe"),
		"y captura un error del MOTOR, que es el que nadie veia%s"
			% ["" if joined.contains("animacion_que_no_existe") else " (oido: %s)" % joined])

	# Error y warning se distinguen, o el fichero no sirve para triar.
	var kinds: String = ""
	for line: String in heard:
		kinds += line.get_slice(" ", 0) + " "
	_check(kinds.contains("ERROR") and kinds.contains("WARNING"),
		"separa ERROR de WARNING (%s)" % kinds.strip_edges())

	# Repetir no repite: una sola entrada y un contador.
	var before: int = heard.size()
	for i in 20:
		push_error("prueba error de guarda")
	await process_frame
	_check(heard.size() == before,
		"veinte repeticiones no emiten veinte veces (emitidas: %d)" % (heard.size() - before))
	var seen: Dictionary = log_node.get("_seen")
	var repeated: int = 0
	for key: String in seen:
		if String(key).contains("prueba error de guarda"):
			repeated = seen[key]
	_check(repeated == 21, "pero se cuentan (%d)" % repeated)

	# Y el conteo se ANUNCIA segun escala, sin esperar al cierre.
	#
	# Los totales se escribian solo en _close(), y en Android _close() casi
	# nunca corre - el sistema mata el proceso. El log del 2026-08-24 volvio con
	# trance_shaders.gd fallando desde _process, potencialmente en cada frame de
	# una cancion entera, y no habia forma de distinguirlo de un error suelto.
	var written: String = FileAccess.get_file_as_string(log_node.get("_path"))
	_check(written.contains("(x10)"),
		"el fichero anuncia la repeticion al llegar a 10, sin depender de un cierre limpio")
	_check(not written.contains("(x11)") and not written.contains("(x12)"),
		"...una vez por decada, no una por repeticion")

	# Y el tope existe, contra un build roto que escupa cien errores distintos.
	_check(int(script.get("MAX_DISTINCT")) > 0
			and int(script.get("MAX_DISTINCT")) <= 1000,
		"hay tope de errores distintos (%s)" % script.get("MAX_DISTINCT"))

	log_node.queue_free()
	await process_frame


func _wiring_checks() -> void:
	var code: String = FileAccess.get_file_as_string(SCRIPT)

	# El sumidero corre en el hilo que lanzo el error - el del ResourceLoader,
	# entre otros - asi que no puede tocar el disco.
	var sink: int = code.find("class _Sink extends Logger:")
	_check(sink >= 0, "el sumidero es un Logger de verdad")
	var sink_body: String = code.substr(sink, code.find("\nfunc _ready", sink) - sink)
	_check(not sink_body.contains("FileAccess"),
		"...y no toca FileAccess: llega desde cualquier hilo, incluido el del ResourceLoader")
	_check(sink_body.contains("queue_error("),
		"...solo encola, y el Node vuelca en _process")
	_check(code.contains("_lock.lock()") and code.contains("_lock.unlock()"),
		"la cola va bajo mutex")

	# Y la reentrada: un fallo escribiendo volveria por el mismo Logger.
	_check(code.contains("if _writing:"),
		"un error durante la escritura no recursiona")

	_check(code.contains("OS.add_logger(") and code.contains("OS.remove_logger("),
		"se registra y se da de baja")

	# El segundo destino: el log de diagnostico, para tener la correlacion.
	var diag: String = FileAccess.get_file_as_string(DIAG)
	_check(diag.contains("ErrorLog.captured.connect(_on_error_captured)"),
		"el log de diagnostico tambien los recibe, para situarlos en su linea de tiempo")
	_check(diag.contains("func _on_error_captured"),
		"...y tiene con que escribirlos")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
