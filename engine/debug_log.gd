extends Node

## Logger de debug general para diagnostico en dispositivo.
##
## Uso:
##     DebugLog.log("mensaje")
##     DebugLog.log("[ModLoader] autoloads: %s" % str(autoloads))
##
## Por que existe: en Android release sin logcat, print() no se ve desde
## fuera de la app. push_error() tampoco sirve, porque dispara el toast
## rojo en pantalla y ensucia el .error con cosas que no son errores.
## Este es el punto medio: escribe al archivo y nada mas.
##
## Path: el mismo directorio que ErrorLog, con nombre debug.log.
##
## Truncado al arrancar: una sesion, un archivo. Sin rotacion - si hay un
## bug que estas cazando, la sesion actual es lo que importa. El .error
## rota porque acumula historia; este no.
##
## A diferencia de ErrorLog, no depende de OS.add_logger(): escribe
## directo. Un DebugLog.log() del primer frame de cualquier _ready()
## sale, porque el archivo se abre en el _ready() de este autoload, que
## corre antes que cualquier escena.

const APP_LOG_DIR_FMT := "/storage/emulated/0/Android/data/%s/files/logs"
## Directorio publico primario. Mismo que ErrorLog para que todos los
## logs del engine queden juntos en /storage/emulated/0/.WashosEngine/logs/
## (con punto, consistente con la carpeta de mods legacy).
const PUBLIC_DIR := "/storage/emulated/0/.WashosEngine/logs"
const FALLBACK_LOG_DIR := "user://logs"
const DEFAULT_ANDROID_PACKAGE := "com.washos.engine"
const FILENAME := "debug.log"


## Emitido por cada llamada a log(). Simetrico con ErrorLog.captured.
## Permite que otros autoloads/escenas escuchen los debug sin acoplarse
## al archivo. Mismo patron que ErrorLog usa para errores.
signal captured(text: String)

var _file: FileAccess = null
var _path: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open()


func _exit_tree() -> void:
	if _file != null:
		_file.close()
		_file = null


## Escribe una linea al archivo. No-op si el archivo no se pudo abrir.
## Flush inmediato: el proximo bug puede ser un crash, y una linea en
## buffer es exactamente la que se pierde.
func log(msg: String) -> void:
	captured.emit(msg)
	if _file == null:
		return
	_file.store_line("[%8.2fs] %s" % [float(Time.get_ticks_msec()) / 1000.0, msg])
	_file.flush()


## Ruta del archivo abierto. NO se llama get_path() porque Node ya tiene
## uno (-> NodePath) y sobreescribirlo con otra firma rompe el parser.
func get_log_path() -> String:
	return _path


func _open() -> void:
	var dir := _pick_dir()
	if dir.is_empty():
		push_warning("[DebugLog] no hay directorio escribible")
		return
	_path = dir.path_join(FILENAME)
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_warning("[DebugLog] no puedo abrir %s" % _path)
		return
	_file.store_line("Washos Engine debug log")
	_file.store_line("date    : %s" % Time.get_datetime_string_from_system())
	_file.store_line("version : %s" % _version())
	_file.store_line("os      : %s %s" % [OS.get_name(), OS.get_version()])
	_file.store_line("model   : %s" % OS.get_model_name())
	_file.store_line("gpu     : %s" % RenderingServer.get_video_adapter_name())
	_file.store_line("")
	_file.flush()


func _pick_dir() -> String:
	var candidates: Array[String] = []
	if OS.get_name() == "Android":
		# Publico primero: accesible desde Termux y cualquier gestor de
		# archivos, sin run-as ni root. Requiere MANAGE_EXTERNAL_STORAGE,
		# que la app ya pide al arrancar.
		candidates.append(PUBLIC_DIR)
		candidates.append(APP_LOG_DIR_FMT % _android_package())
	candidates.append(FALLBACK_LOG_DIR)

	for candidate in candidates:
		if _is_writable(candidate):
			return candidate
	return ""


## Verifica creando un archivo real. make_dir_recursive_absolute() puede
## devolver OK y el path rechazar escrituras igual - un intento de write
## es la unica prueba que vale. Mismo criterio que _can_read_from() del
## ModLoader para las raices de mods.
func _is_writable(dir_path: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK \
			and not DirAccess.dir_exists_absolute(dir_path):
		return false
	var probe: String = dir_path.path_join(".debug_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _android_package() -> String:
	var parts: PackedStringArray = OS.get_user_data_dir().split("/", false)
	var idx: int = parts.find("files")
	if idx > 0:
		return parts[idx - 1]
	return DEFAULT_ANDROID_PACKAGE


func _version() -> String:
	if ProjectSettings.has_setting("application/config/version"):
		return str(ProjectSettings.get_setting("application/config/version"))
	return "?"
