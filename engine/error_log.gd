extends Node
## Escribe cada error y warning del engine a un archivo que el usuario
## siempre tiene.
##
## Por que existe: los errores de Godot van a logcat de Android, y logcat
## necesita `adb logcat` para leerlo. Un usuario comun no tiene forma de
## reportar que fallo. Este autoload captura todo lo que Godot expone a
## traves de OS.add_logger() y lo escribe a un archivo que el gestor de
## archivos del telefono puede abrir.
##
## Que captura (verificado contra el source de 4.7.1, ErrorType enum):
##   ERR_ERROR    - push_error() y errores C++ del engine
##   ERR_WARNING  - push_warning() y warnings C++ (deprecaciones, etc)
##   ERR_SCRIPT   - errores de runtime de GDScript (null access, etc)
##   ERR_SHADER   - errores de compilacion de shaders en runtime
##
## Que NO captura (por limitaciones del motor, no de este archivo):
##   - Crashes nativos (SIGSEGV, SIGABRT): el proceso muere antes de que
##     el Logger pueda escribir. Se ven en logcat o con un crash reporter.
##   - OOM kills de Android: el kernel mata el proceso.
##   - Errores del servidor de audio o display al boot: pasan antes de
##     que este autoload se registre.
##   - Errores de JNI / Android Java: no vuelven por el Logger.
##   - printerr(): va a stderr directo, no por Logger.
##   - print(): es output normal, no error.
##
## El archivo se crea SOLO cuando hay al menos un error. Una sesion sana
## no deja basura en el telefono.

## Ruta del log en Android: app-private external, sin permisos.
## El %s se reemplaza con el package real leido en runtime.
const ANDROID_APP_LOG_DIR_FMT := "/storage/emulated/0/Android/data/%s/files/logs"
## Fallback si Android no deja escribir ahi: user:// es interno, pero al
## menos algo queda.
const FALLBACK_LOG_DIR := "user://logs"
## Package por defecto si no se puede leer el real. Coincide con el de
## export_presets.cfg.
const DEFAULT_ANDROID_PACKAGE := "com.washos.engine"

## Cuantos archivos .error se mantienen. Los mas viejos se borran al
## abrir uno nuevo. Estos archivos solo existen en sesiones con errores,
## y uno tipico es de unas pocas lineas.
const MAX_ERROR_FILES := 5

## Tope de errores DISTINTOS por sesion. Los repetidos se cuentan en vez
## de escribirse de nuevo, asi que un error por frame cuesta una linea
## con contador, no sesenta por segundo. El tope protege contra cientos
## de errores distintos, que es un build roto y no un bug reportable.
const MAX_DISTINCT := 200

## Emitido en el main thread por cada error nuevo. Solo la primera
## ocurrencia de cada error distinto; las repeticiones se cuentan en el
## archivo. Lo puede escuchar una pantalla de debug si algun dia existe.
signal captured(kind: String, where: String, message: String)

var _sink: _Sink
var _file: FileAccess
var _path: String = ""

## Clave de error distinto -> cuantas veces sono.
var _seen: Dictionary = {}

## Llenado desde cualquier thread, drenado en el main. Ver _Sink.
var _pending: Array[Dictionary] = []
var _lock: Mutex = Mutex.new()

## True mientras este nodo esta escribiendo. Un fallo dentro de la
## escritura volveria a entrar por el logger, y recursar sobre un archivo
## a medio escribir es peor bug que el que se esta reportando.
var _writing: bool = false


## El Logger en si. No es un Node, no puede tocar el filesystem.
##
## _log_error se llama desde el thread que tiro el error, y en Godot eso
## incluye los threads del ResourceLoader. FileAccess desde dos threads a
## la vez es un archivo corrupto, asi que aca solo se apila en un array
## bajo mutex y el Node lo drena en _process.
class _Sink extends Logger:
	var owner_log: Node

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array) -> void:
		if owner_log == null:
			return
		# `rationale` trae el mensaje humano cuando el engine lo levanta,
		# y viene vacio en push_error/push_warning, donde el mensaje esta
		# en `code`.
		var message: String = rationale if not rationale.is_empty() else code
		# El stack trace de GDScript llega aca. Antes se descartaba y solo
		# veiamos el archivo C++ (gdscript.cpp, etc). Con esto sabemos que
		# .gd y que linea disparo el error.
		var where: String = "%s:%d %s" % [file.get_file(), line, function]
		if not _script_backtraces.is_empty():
			var parts: PackedStringArray = PackedStringArray()
			for bt in _script_backtraces:
				parts.append(str(bt))
			where += " | " + " <- ".join(parts)
		owner_log.queue_error(error_type, where, message)


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


## Llamado desde cualquier thread. Barato a proposito: mutex y append.
func queue_error(error_type: int, where: String, message: String) -> void:
	if _writing:
		return
	_lock.lock()
	_pending.append({"type": error_type, "where": where, "message": message})
	_lock.unlock()


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	_lock.lock()
	var batch: Array = _pending
	_pending = []
	_lock.unlock()

	_writing = true
	for item in batch:
		_record(item["type"], item["where"], item["message"])
	if _file != null:
		_file.flush()
	_writing = false


func _record(error_type: int, where: String, message: String) -> void:
	# En el enum de Godot: 0=ERR_ERROR, 1=ERR_WARNING, 2=ERR_SCRIPT, 3=ERR_SHADER.
	# Los dos ultimos son errores de GDScript/shaders y los tratamos como
	# errores, no warnings.
	var kind: String = "WARNING" if error_type == 1 else "ERROR"
	var key: String = "%s|%s|%s" % [kind, where, message]

	if _seen.has(key):
		# Las repeticiones se cuentan, no se reescriben. Pero se anuncia
		# el conteo cuando escala: a 10, 100, 1000. Un error que pasa
		# diez mil veces es un bug distinto de uno que pasa una vez.
		var count: int = _seen[key] + 1
		_seen[key] = count
		if count >= 10 and count == _next_power_of_ten(count):
			_write("%s (x%d)" % [message.replace("\n", " | "), count], kind, where)
		return

	if _seen.size() >= MAX_DISTINCT:
		return
	_seen[key] = 1

	_write(message.replace("\n", " | "), kind, where)
	captured.emit(kind, where, message)


## Una entrada, dos lineas: que paso y de donde vino.
func _write(text: String, kind: String, where: String) -> void:
	if not _open():
		return
	_file.store_line("[%8.2fs] %-7s %s" % [
		float(Time.get_ticks_msec()) / 1000.0, kind, text])
	_file.store_line("          %s" % where)


## La potencia de diez igual o menor a `count`, para anunciar una
## repeticion una vez por decada y no en cada ocurrencia.
func _next_power_of_ten(count: int) -> int:
	var power: int = 10
	while power * 10 <= count:
		power *= 10
	return power


## Se abre en el primer error y no antes, para que una sesion limpia no
## deje archivo y el mas nuevo en el dispositivo siempre tenga contenido.
func _open() -> bool:
	if _file != null:
		return true

	var dir: String = _pick_dir()
	_rotate(dir)
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	_path = "%s/washos_%s.error" % [dir, stamp]
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		return false

	_file.store_line("Washos Engine error log")
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
	# Los conteos de repeticion, escritos una vez, al final. Lo que sono
	# mas de una vez es la mitad interesante del archivo: un error que
	# pasa cuarenta mil veces es distinto de uno que pasa una.
	var repeated: Array[String] = []
	for key in _seen:
		if _seen[key] > 1:
			repeated.append("%6d x  %s" % [_seen[key], key.replace("|", "  ")])
	if not repeated.is_empty():
		_file.store_line("")
		_file.store_line("--- repeticiones ---")
		repeated.sort()
		for line in repeated:
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
		# Directorio publico primero, mismo que DebugLog. Con punto
		# inicial para no colisionar con la carpeta WashosEngine/mods.
		candidates.append("/storage/emulated/0/.WashosEngine/logs")
		candidates.append(ANDROID_APP_LOG_DIR_FMT % _android_package())
	candidates.append(FALLBACK_LOG_DIR)

	for candidate in candidates:
		if DirAccess.make_dir_recursive_absolute(candidate) == OK \
				or DirAccess.dir_exists_absolute(candidate):
			return candidate
	return FALLBACK_LOG_DIR


func _android_package() -> String:
	var parts: PackedStringArray = OS.get_user_data_dir().split("/", false)
	var idx: int = parts.find("files")
	if idx > 0:
		return parts[idx - 1]
	return DEFAULT_ANDROID_PACKAGE


## Mantiene los MAX_ERROR_FILES mas nuevos. Sin esto un telefono acumula
## un archivo por sesion que falla, para siempre.
func _rotate(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var files: Array[String] = []
	for name in dir.get_files():
		if name.ends_with(".error"):
			files.append(name)
	files.sort()
	var excess: int = files.size() - (MAX_ERROR_FILES - 1)
	for i in maxi(excess, 0):
		dir.remove(files[i])
