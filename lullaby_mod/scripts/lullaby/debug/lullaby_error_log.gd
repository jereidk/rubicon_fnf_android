extends Node

## Every engine error and warning, in a file the player always has.
##
## The gap this closes: until now the diagnostics log could only record errors
## that somebody had hand-routed through `ErrorHandler.show_warning()` or
## `show_error()`, and there are exactly six such calls in the project - all of
## them catastrophic load failures that stop the game anyway. Everything else
## went to Android's logcat, which no player is ever going to send you:
##
##   * every push_error/push_warning this project writes, including the ones
##     added specifically to report a failure (console_late_resources.gd warns
##     when a deferred path does not resolve - that warning reached nobody)
##   * every red error the engine raises, e.g. "There is no animation with
##     name 'x'", which is the exact failure the console's sprite_animations
##     table exists to avoid and which nothing could have told us about
##   * every GDScript runtime error
##
## `OS.add_logger()` with a Logger subclass catches all three. Verified on
## 4.7.1 against this project before any of this was written: a push_error, a
## push_warning and an engine-side set_animation() failure all arrive, with
## the C++ file and line and an error_type that separates error from warning.
##
## SEPARATE FILE, and always on, for one reason: the diagnostics log now ships
## OFF, and the situation this is for is a player reporting a crash with
## nothing to send. A file that is only created the first time something
## actually goes wrong costs nothing on a session where nothing does. When the
## diagnostics log IS running it gets the same errors too, through `captured`,
## because only that file can say what the game was doing at the time.

## Where the file goes, mirroring the diagnostics log so both land in the same
## place and the player only has one folder to find.
const ANDROID_APP_LOG_DIR_FMT := "/storage/emulated/0/Android/data/%s/files/logs"
const FALLBACK_LOG_DIR := "user://logs"
const ANDROID_PACKAGE := "com.rubicon.fnf"

## Kept, newest first. Small - these files only exist for sessions that had
## errors, and one is usually a few lines.
const MAX_ERROR_FILES := 5

## Distinct errors recorded per session before this stops opening new ones.
##
## The cap is on DISTINCT errors, not on total: a single error firing every
## frame collapses into one line with a counter, so the runaway case costs one
## entry, not sixty a second. What the cap protects against is a hundred
## different errors, which is a broken build rather than a bug report.
const MAX_DISTINCT := 200

## Emitted on the main thread for each newly seen error, so the diagnostics log
## can put it on its own timeline. Only the first occurrence of each distinct
## error is emitted; repeats are counted in the file instead of re-announced.
signal captured(kind: String, where: String, message: String)

var _sink: _Sink
var _file: FileAccess
var _path: String = ""

## Distinct error key -> how many times it has fired.
var _seen: Dictionary[String, int] = {}

## Filled from any thread, drained on the main one. See _Sink.
var _pending: Array[Dictionary] = []
var _lock: Mutex = Mutex.new()

## True while this node is writing. A failure inside the write would come
## straight back through the logger, and recursing into a half-written file is
## a worse bug than the one being reported.
var _writing: bool = false


## The Logger itself, which is not a Node and must not touch the filesystem.
##
## _log_error is called from whatever thread raised the error, and in this
## project that very much includes the ResourceLoader's - the whole shop load
## runs there. FileAccess from two threads at once is a corrupt file, so this
## end only appends to an array under a mutex and the Node drains it in
## _process.
class _Sink extends Logger:
	var owner_log: Node

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if owner_log == null:
			return
		# `rationale` carries the human message when the engine raises it, and
		# is empty for push_error/push_warning where `code` is the message.
		var message: String = rationale if not rationale.is_empty() else code
		owner_log.queue_error(error_type, "%s:%d %s" % [file.get_file(), line, function], message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sink = _Sink.new()
	_sink.owner_log = self
	OS.add_logger(_sink)


func _exit_tree() -> void:
	if _sink != null:
		OS.remove_logger(_sink)
		_sink = null
	_close()


## Called from any thread. Cheap on purpose - a mutex and an append.
func queue_error(error_type: int, where: String, message: String) -> void:
	if _writing:
		return
	_lock.lock()
	_pending.append({"type": error_type, "where": where, "message": message})
	_lock.unlock()


## Cada cuanto se vuelcan los recuentos exactos sin esperar a _close().
##
## _close() ya escribe la seccion de repeticiones, y en Android casi nunca corre
## porque el SO se lleva el proceso - su propio comentario lo dice. El resultado
## medido: en los CATORCE .error guardados de un mes no hay un solo total, y lo
## unico que queda sobre cuantas veces fallo algo son los avisos de escalada,
## que salen en potencias de diez.
##
## Eso hizo que `VkResult -13 (x100)` se leyera como "cien pipelines fallan".
## No dice eso: dice que la cuenta llego a cien y no llego a mil, o sea algo
## entre 100 y 999. Sobre el fotograma de 22,5s de Chimera esa horquilla es un
## precio por fallo de entre 225ms y 22ms - dos diagnosticos distintos - y sin
## el numero exacto no hay forma de saber si un arreglo del -13 sirvio.
##
## EL -13 NO SE ARREGLA, y este parrafo existe para que nadie vuelva a
## intentarlo. Los totales exactos ya salen - el log del 15-09 da `52 x` - y con
## el numero en la mano la respuesta resulto estar en el fuente de Godot 4.7.1,
## no en este proyecto.
##
## `drivers/vulkan/rendering_device_driver_vulkan.cpp`, sobre la bandera que
## silencia justo este mensaje:
##
##     // Don't print pipeline compilation errors on Adreno 660, as they are
##     // expected to happen on this device with ubershaders.
##     driver_workarounds.dont_print_on_render_pipeline_creation_failure =
##             vendorID == VENDOR_QUALCOMM && deviceID == 0x6060001;
##
## O sea: que `vkCreateGraphicsPipelines` devuelva VK_ERROR_UNKNOWN (-13) es
## comportamiento CONOCIDO Y ESPERADO en Adreno con ubershaders. Godot solo se
## calla el mensaje en el 660; el moto g53 lleva un 619, que no entra en esa
## condicion, asi que los mismos fallos esperados si se imprimen. No hay ajuste
## de proyecto que desactive los ubershaders: `scene_shader_forward_mobile.cpp`
## los compila en un bucle `for (ubershader = 0; ubershader < 2; ubershader++)`
## sin condicion.
##
## Y no rompen nada visible. El mismo fichero de Godot lo dice en la linea
## siguiente - "Unhandled error cases will still pop up elsewhere in RD (eg.
## when attempting to bind an invalid pipeline)" - y en el log no aparece
## ninguno de esos.
##
## QUE ES UNA PIPELINE, porque no es lo mismo que un shader y de ahi venia mi
## confusion. Una pipeline es el shader MAS todo el estado fijo horneado a su
## alrededor: mezcla, descarte de caras, prueba de profundidad, formato de
## vertices, pase de render, y las constantes de especializacion (cuantas luces,
## si hay lightmap, si hay niebla...). El mismo shader con otra combinacion es
## OTRA pipeline que el conductor tiene que compilar aparte.
##
## Godot compila dos clases por material:
##
##   especializada  con las constantes horneadas. Rapida de ejecutar, pero hace
##                  falta una por cada combinacion exacta.
##   ubershader     sin hornear nada: todo son ramas en tiempo de ejecucion y el
##                  descarte de caras va desactivado. Mas lenta, pero UNA sirve
##                  para todas las combinaciones, asi que se puede usar YA
##                  mientras la especializada se compila por detras.
##
## Lo que falla son las ubershader.
##
## LO QUE PASA ENTONCES, de `render_forward_mobile.cpp` (~2592). El orden real es:
##
##   1. especializada, SIN esperar    si ya estaba compilada, se usa
##   2. ubershader, ESPERANDO         <- la que falla en el 619
##   3. especializada, ESPERANDO      compilar ahora y congelar el fotograma
##
##     // If ubershader failed to compile, retry specialized shader and wait for
##     // it to finish compilation.
##     // This prevents pop-in at the cost of shader compilation stutters.
##
## O sea que no se ve nada mal: el paso 3 dibuja lo correcto. Lo que se paga es
## el TIRON, y lo dice el propio Godot en ese comentario. Correccion de lo que
## escribi antes en este sitio: no es que "no haya respaldo", es que el respaldo
## barato (2) no existe aqui y solo queda el caro (3).
##
## Eso encaja con todo lo medido - el fotograma de 2093ms montando la tienda, el
## de 22,5s en la precarga de Chimera - y convierte a `lullaby_preload_camera.gd`
## en el unico mecanismo disponible para pagar ese coste detras de la pantalla de
## carga, en vez de en una optimizacion mas.
##
## Y tampoco hay palanca por aqui: `disable_ubershaders` existe en el motor pero
## sale de `get_driver_workarounds()`, no de un ajuste de proyecto.
##
## NO LO CAUSA NADA DE ESTE PROYECTO, y se puede demostrar con los contadores que
## este log ya recogia. `render_forward_mobile.cpp` etiqueta la fuente de cada
## compilacion segun la variante:
##
##     pipeline_source = pipeline_key.ubershader ? PIPELINE_SOURCE_DRAW
##                                               : PIPELINE_SOURCE_SPECIALIZATION;
##
## y `_pipeline_breakdown()` los escribe como `draw+N` y `spec+N`. O sea que
## `draw+` es el numero de ubershaders que SI se compilaron. En tres sesiones
## distintas del moto g53:
##
##     15-09 07:30   draw+2    spec+336
##     15-09 01:47   draw+2    spec+239
##     13-09 13:28   draw+0    spec+150
##
## Dos, dos y cero. Con 52 fallos registrados, los intentos de ubershader son
## ~54 y fracasan ~52: casi el CIEN POR CIEN. No es un subconjunto con algo raro
## - que seria lo que cabria esperar si la causa fueran nuestros shaders - es
## practicamente todos, que es exactamente lo que dice el comentario de Godot
## sobre Adreno.
##
## (Correccion de una lectura mia: "52 fallos contra ~650 pipelines" no es la
## proporcion. Esas 650 son en su mayoria especializadas, de malla y de
## superficie. El denominador bueno son los intentos de ubershader, y ahi la
## tasa de fallo es casi total.)
const TOTALS_EVERY_SECONDS := 60.0

## Cuenta minima para salir en el volcado. Lo que paso una sola vez ya tiene su
## linea propia mas arriba en el fichero.
const TOTALS_MIN_COUNT := 2

var _next_totals_msec: int = 0


func _process(_delta: float) -> void:
	_dump_totals_if_due()

	if _pending.is_empty():
		return

	_lock.lock()
	var batch: Array[Dictionary] = _pending
	_pending = []
	_lock.unlock()

	_writing = true
	for item: Dictionary in batch:
		_record(item["type"], item["where"], item["message"])
	if _file != null:
		_file.flush()
	_writing = false


## Los recuentos exactos, cada minuto, para no depender de un cierre limpio.
##
## Solo escribe si hay algo repetido, asi que una sesion sana no paga ni una
## linea. Lleva marca de tiempo como todo lo demas para poder cruzarlo con el
## .log: la diferencia entre dos volcados dice cuantas veces fallo algo DENTRO
## de esa ventana, que es lo que hace falta para atribuirlo a una escena en vez
## de a la sesion entera.
func _dump_totals_if_due() -> void:
	var now: int = Time.get_ticks_msec()
	if _next_totals_msec == 0:
		_next_totals_msec = now + int(TOTALS_EVERY_SECONDS * 1000.0)
		return
	if now < _next_totals_msec:
		return
	_next_totals_msec = now + int(TOTALS_EVERY_SECONDS * 1000.0)

	if _file == null:
		return
	var lines: Array[String] = []
	for key: String in _seen:
		if _seen[key] >= TOTALS_MIN_COUNT:
			lines.append("%8d x  %s" % [_seen[key], key.replace("|", "  ")])
	if lines.is_empty():
		return
	lines.sort()
	# `_writing` alrededor de la escritura, como en _process: `queue_error()`
	# lo mira para no reentrar mientras este fichero esta tocando el disco, y
	# un error levantado desde aqui dentro se perderia en vez de corromper.
	_writing = true
	_file.store_line("[%8.2fs] TOTALES" % (float(now) / 1000.0))
	for line: String in lines:
		_file.store_line("          %s" % line)
	_file.flush()
	_writing = false


func _record(error_type: int, where: String, message: String) -> void:
	var kind: String = "WARNING" if error_type == 1 else "ERROR"
	var key: String = "%s|%s|%s" % [kind, where, message]

	if _seen.has(key):
		# Repeats are counted, not repeated - one dictionary bump per frame and
		# nothing else.
		#
		# But the count is also announced as it escalates, at 10, 100, 1000 and
		# so on, and that is a fix for this file's first outing rather than a
		# flourish. The totals used to be written only by _close(), and on
		# Android _close() mostly never runs: the OS kills the process. The
		# 2026-08-24 log came back with trance_shaders.gd erroring from
		# _process - potentially every frame of a whole song - and no way to
		# tell that from a single stray error, because the repeat section was
		# never reached. An error that happens ten thousand times is a
		# different bug from one that happens once, and the file has to say so
		# without depending on a clean exit.
		var count: int = _seen[key] + 1
		_seen[key] = count
		if count >= 10 and count == _next_power_of_ten(count):
			_write("%s (x%d)" % [message.replace("\n", " | "), count],
				"WARNING" if error_type == 1 else "ERROR", where)
		return

	if _seen.size() >= MAX_DISTINCT:
		return
	_seen[key] = 1

	_write(message.replace("\n", " | "), kind, where)
	captured.emit(kind, where, message)


## One entry, two lines: what happened and where it came from.
func _write(text: String, kind: String, where: String) -> void:
	if not _open():
		return
	_file.store_line("[%8.2fs] %-7s %s" % [
		float(Time.get_ticks_msec()) / 1000.0, kind, text])
	_file.store_line("          %s" % where)


## The power of ten at or below `count`, so an escalating repeat is announced
## once per decade rather than once per occurrence.
func _next_power_of_ten(count: int) -> int:
	var power: int = 10
	while power * 10 <= count:
		power *= 10
	return power


## Opened on the first error and not before, so a clean session leaves no file
## and the newest file on the device is always one that has something in it.
func _open() -> bool:
	if _file != null:
		return true

	var dir: String = _pick_dir()
	_rotate(dir)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	_path = "%s/lullaby_%s.error" % [dir, stamp]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		return false

	_file.store_line("Lullaby error log")
	_file.store_line("date    : %s" % Time.get_datetime_string_from_system())
	var version: String = ""
	if ProjectSettings.has_setting("application/config/version"):
		version = str(ProjectSettings.get_setting("application/config/version"))
	_file.store_line("version : %s" % version)
	_file.store_line("os      : %s %s" % [OS.get_name(), OS.get_version()])
	_file.store_line("model   : %s" % OS.get_model_name())
	_file.store_line("gpu     : %s" % RenderingServer.get_video_adapter_name())
	_file.store_line("")
	return true


func _close() -> void:
	if _file == null:
		return
	# The repeat counts, written once, at the end. Anything that fired more
	# than once is the interesting half of this file: an error that happens
	# forty thousand times is a different problem from one that happens once.
	var repeated: Array[String] = []
	for key: String in _seen:
		if _seen[key] > 1:
			repeated.append("%6d x  %s" % [_seen[key], key.replace("|", "  ")])
	if not repeated.is_empty():
		_file.store_line("")
		_file.store_line("--- repeticiones ---")
		repeated.sort()
		for line: String in repeated:
			_file.store_line(line)
	if _seen.size() >= MAX_DISTINCT:
		_file.store_line("")
		_file.store_line("(tope de %d errores distintos alcanzado; el resto no se anoto)" % MAX_DISTINCT)
	_file.flush()
	_file.close()
	_file = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _sink != null:
			OS.remove_logger(_sink)
			_sink = null
		_close()


func _pick_dir() -> String:
	var candidates: Array[String] = []
	if OS.get_name() == "Android":
		candidates.append(ANDROID_APP_LOG_DIR_FMT % _android_package())
	candidates.append(FALLBACK_LOG_DIR)

	for candidate: String in candidates:
		if DirAccess.make_dir_recursive_absolute(candidate) == OK \
				or DirAccess.dir_exists_absolute(candidate):
			return candidate
	return FALLBACK_LOG_DIR


func _android_package() -> String:
	var parts: PackedStringArray = OS.get_user_data_dir().split("/", false)
	var idx: int = parts.find("files")
	if idx > 0:
		return parts[idx - 1]
	return ANDROID_PACKAGE


## Keeps the newest MAX_ERROR_FILES, same as the diagnostics log does with its
## own - a phone should not accumulate one file per crashy session forever.
func _rotate(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var files: Array[String] = []
	for name: String in dir.get_files():
		if name.ends_with(".error"):
			files.append(name)
	files.sort()
	var excess: int = files.size() - (MAX_ERROR_FILES - 1)
	for i in maxi(excess, 0):
		dir.remove(files[i])
