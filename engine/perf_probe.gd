extends Node
## PerfProbe — autoload del engine que registra performance a disco.
##
## Escribe un log continuo a un archivo para poder leer despues que paso en
## un device real, en vez de tener que reproducir el problema. Inspirado
## en lullaby_diagnostics_log.gd del branch add-lullaby-mod, con lo
## especifico de Lullaby recortado y una API publica para que los mods
## registren sus propios eventos.
##
## Que loguea:
##   - HEARTBEAT cada 5s: linea base continua con contadores completos
##   - SPIKE cuando un frame tarda SPIKE_FACTOR x la mediana reciente
##   - SPIKE_ALWAYS cuando un frame tarda >= 250ms (bypass del ratio)
##   - MEMLEAP cuando la memoria sube MEMORY_JUMP_MB de golpe
##   - SCENE_IN / SCENE_OUT con memoria antes/despues y duracion
##   - SUSPEND cuando la app vuelve de background
##   - MARK eventos que el engine o los mods disparan manualmente
##   - ERROR / WARN via OS.add_logger() (captura de push_error/push_warning)
##
## Formato de cada linea:
##   [  42.31s] KIND    detail key=value key=value ...
##
## API publica para mods (llamar desde cualquier autoload o script):
##   PerfProbe.mark("signin", "user=jereidk result=ok")
##   PerfProbe.begin("load_scene")
##   PerfProbe.end("load_scene")  -> loguea elapsed ms
##   PerfProbe.snapshot("manual")  -> log completo bajo demanda
##
## Notas sobre los contadores (heredadas del original):
##   proc= es Performance.TIME_PROCESS, Godot lo resetea 1/s. Es el PEOR
##         frame de ese segundo, no un promedio.
##   draw= es contador de draw calls, no duracion. gpu= es la duracion.
##   script= bracket del pase de process completo (todos los _process +
##           AnimationPlayer/AnimationTree). Separa "CPU ocupado" (script
##           alto) de "CPU esperando" (script bajo, tiempo en render/present).

# ============================================================================
# Configuracion
# ============================================================================

## Path Android app-private. Sobrevive sin permisos y aparece en cualquier
## file manager. El package real se lee de user:// en _android_package().
const ANDROID_APP_LOG_DIR_FMT := "/storage/emulated/0/Android/data/%s/files/logs"
const FALLBACK_LOG_DIR := "user://logs"
const LOG_FILE_PREFIX := "washos_perf"
const LOG_FILE_EXT := ".log"

## Cuantos logs mantener en la carpeta. Los viejos se borran.
const MAX_LOG_FILES := 5

## Un frame SPIKE_FACTOR veces la mediana reciente Y >= SPIKE_MIN_MS cuenta
## como spike. 2.5x filtra jitter normal, 24ms es un hitch que se siente.
const SPIKE_FACTOR := 2.5
const SPIKE_MIN_MS := 24.0

## Un frame >= esto se loguea SIEMPRE, sin importar la mediana. Protege
## contra el caso "despues de un load la mediana esta vieja y no dispara".
const SPIKE_ALWAYS_MS := 250.0

## Rate limit de spikes. Un solo stutter puede gatillar varios frames
## seguidos; 0.5s de cooldown convierte eso en 2-3 lineas en vez de 300.
const SPIKE_COOLDOWN_SEC := 0.5

## Salto de memoria que vale un log.
const MEMORY_JUMP_MB := 24.0

## Cada cuanto escribir un heartbeat.
const HEARTBEAT_SEC := 5.0

## Tamaño del ring buffer de frame times. 120 frames a 60fps = 2s.
const WINDOW_SIZE := 120

## Cuantos frames de "warmup" ignorar despues de un scene change, antes de
## armar la mediana. Durante un load los frames son muy largos y
## envenenarian la mediana del scene nuevo.
const WARMUP_FRAMES := 30

## Ids de los custom monitors que _counters_str() incluye en cada linea
## del log. Orden estable para diffear entre corridas.
const PERFORMANCE_EXTRA_IDS := [
	"Washos/perf/median_ms",
	"Washos/perf/script_ms",
	"Washos/mem/static_mb",
	"Washos/mem/peak_mb",
]

# ============================================================================
# Estado
# ============================================================================

var log_path: String = ""
var _log_dir: String = ""
var _file: FileAccess = null
var _running: bool = false
var _session_start_ms: int = 0

## Ring buffer de los ultimos WINDOW_SIZE frame times.
var _frame_times: PackedFloat32Array
var _frame_index: int = 0
var _frames_seen: int = 0

## Timers de rate limit.
var _time_since_heartbeat: float = 0.0
var _time_since_spike: float = 999.0

## Wall clock del frame anterior. Usamos Time.get_ticks_usec() en vez de
## delta porque Godot clampa delta ~50ms y cualquier stall grande se
## reporta como ~50ms en vez de su duracion real (medido en el original:
## un frame de 5000ms llegaba como 66.7ms).
var _last_frame_usec: int = 0

## Frame time del frame anterior en ms. Expuesto como custom monitor.
var _last_frame_ms: float = 0.0

## Contadores acumulados para los custom monitors de tipo QUANTITY.
var _spikes_total: int = 0
var _mem_leaps_total: int = 0

## Delta de PIPELINE_COMPILATIONS_* desde el ultimo _entry con contadores
## completos. Un pico en cualquiera de los 3 durante un SPIKE dice que el
## frame se explica por compilacion de shader en runtime, no por logica.
var _last_pipe_canvas: int = 0
var _last_pipe_mesh: int = 0
var _last_pipe_draw: int = 0

## Bracket del pase de script del frame.
var _script_begin_usec: int = 0
var _script_usec_last: int = 0

## Memoria entre lineas.
var _last_memory: int = 0
var _peak_memory: int = 0

## Escena anterior, para detectar cambios.
var _last_scene_path: String = ""
var _scene_change_started_ms: int = 0

## Deteccion de suspend (Android background).
var _paused_at_msec: int = 0
var _suspended_ms: int = 0

## Timers manuales begin/end.
var _timers: Dictionary = {}  # name -> start usec

## Cache del package Android.
var _android_pkg: String = ""


func _ready() -> void:
	# Procesar aun con el arbol pausado (para loguear pausas).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Priority minima: nuestro _process corre ANTES de todo lo demas en el
	# frame. Eso hace que _script_begin_usec marque el inicio real del pase
	# de script (todos los demas _process vienen despues).
	process_priority = -4096

	_session_start_ms = Time.get_ticks_msec()
	_frame_times.resize(WINDOW_SIZE)
	_frame_times.fill(0.0)

	if not _open_log():
		push_warning("[PerfProbe] no pude abrir log, deshabilitado")
		set_process(false)
		return

	_running = true
	_write_header()
	_last_memory = OS.get_static_memory_usage()

	# Registrar custom monitors: cada metrica tambien aparece graficada en
	# el editor (Debugger > Monitors) con la unidad correcta, y otras tools
	# pueden leerlas con Performance.get_custom_monitor() sin parsear el
	# .log. Ver _register_monitors() para la lista.
	_register_monitors()

	# Suscribir a cambios de escena. No hay signal nativo; chequeamos en
	# _process con string compare (virtualmente gratis).
	var scene := get_tree().current_scene
	_last_scene_path = "" if scene == null else scene.scene_file_path
	# Arrancar el contador del primer scene change en _ready, no en 0.
	# Sin esto el primer cambio de escena reporta dur = toda la sesion.
	_scene_change_started_ms = Time.get_ticks_msec()


## Registra los custom monitors en Performance. Cada uno aparece en el
## editor (Debugger > Monitors) con la unidad correcta, y otras tools los
## leen con Performance.get_custom_monitor("Washos/perf/<id>").
##
## Los ids usan el prefijo "Washos/" para que el filtro en cualquier
## consumidor sea trivial: solo mirar los que empiezan con el prefijo.
## Convencion de unidad (afecta como el editor los grafica):
##   - TIME: segundos o milisegundos, el editor lo muestra como ms
##   - MEMORY: bytes, el editor lo muestra en KB/MB automaticamente
##   - QUANTITY: cuenta, numero plano
##   - PERCENTAGE: 0-100
##
## IMPORTANTE: si Performance.add_custom_monitor() falla con el mismo id
## dos veces seguidas (por ejemplo, el autoload se recrea en un test),
## hacemos has_custom_monitor() primero para evitar warnings.
func _register_monitors() -> void:
	_add_monitor("Washos/perf/frame_ms", func(): return _last_frame_ms, Performance.MONITOR_TYPE_TIME)
	_add_monitor("Washos/perf/median_ms", func(): return _median_frame_ms(), Performance.MONITOR_TYPE_TIME)
	_add_monitor("Washos/perf/script_ms", func(): return float(_script_usec_last) / 1000.0, Performance.MONITOR_TYPE_TIME)
	_add_monitor("Washos/perf/spikes_total", func(): return _spikes_total, Performance.MONITOR_TYPE_QUANTITY)
	_add_monitor("Washos/mem/static_mb", func(): return float(OS.get_static_memory_usage()) / 1048576.0, Performance.MONITOR_TYPE_MEMORY)
	_add_monitor("Washos/mem/peak_mb", func(): return float(_peak_memory) / 1048576.0, Performance.MONITOR_TYPE_MEMORY)
	_add_monitor("Washos/mem/leaps_total", func(): return _mem_leaps_total, Performance.MONITOR_TYPE_QUANTITY)
	_add_monitor("Washos/pipe/canvas", func(): return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)), Performance.MONITOR_TYPE_QUANTITY)
	_add_monitor("Washos/pipe/mesh", func(): return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)), Performance.MONITOR_TYPE_QUANTITY)
	_add_monitor("Washos/pipe/draw", func(): return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)), Performance.MONITOR_TYPE_QUANTITY)


## Wrapper idempotente sobre Performance.add_custom_monitor.
func _add_monitor(id: String, cb: Callable, type: int) -> void:
	if Performance.has_custom_monitor(id):
		Performance.remove_custom_monitor(id)
	Performance.add_custom_monitor(id, cb, [], type)


## Procesa cada frame. Orden dentro del frame:
##   1. Sella el fin del pase de script del frame anterior (script_usec).
##   2. Reabre el bracket del pase actual (script_begin).
##   3. Mide frame_ms con wall clock.
##   4. Chequea suspend, spike, memoria, heartbeat, scene change.
func _process(delta: float) -> void:
	# 1. Cerrar bracket del frame anterior.
	if _script_begin_usec > 0:
		_script_usec_last = Time.get_ticks_usec() - _script_begin_usec
	# 2. Reabrir para este frame.
	_script_begin_usec = Time.get_ticks_usec()

	# 3. Frame time con wall clock, no delta.
	var now_usec := Time.get_ticks_usec()
	var frame_ms: float = (
		float(now_usec - _last_frame_usec) / 1000.0
		if _last_frame_usec > 0
		else delta * 1000.0
	)
	_last_frame_usec = now_usec
	_last_frame_ms = frame_ms

	# 4a. Suspend: la app volvio de background. El frame que la cruza es
	# la duracion del suspend, no un stall del juego.
	if _suspended_ms > 0:
		_entry("SUSPEND", "dur=%.1fs frame=%.1fms" % [
			_suspended_ms / 1000.0, frame_ms,
		])
		_suspended_ms = 0
		_last_memory = OS.get_static_memory_usage()
		_last_frame_usec = Time.get_ticks_usec()
		return

	# 4b. Guardar frame time en el ring buffer.
	var median := _median_frame_ms()
	_frame_times[_frame_index] = frame_ms
	_frame_index = (_frame_index + 1) % WINDOW_SIZE
	_frames_seen += 1

	# 4c. Spike detection.
	_time_since_spike += frame_ms / 1000.0
	var is_spike := false
	if frame_ms >= SPIKE_ALWAYS_MS:
		is_spike = true
	elif _frames_seen > WARMUP_FRAMES and median > 0.0:
		if frame_ms >= median * SPIKE_FACTOR and frame_ms >= SPIKE_MIN_MS:
			is_spike = true
	if is_spike and _time_since_spike >= SPIKE_COOLDOWN_SEC:
		_time_since_spike = 0.0
		_spikes_total += 1
		_entry("SPIKE", "frame=%.1fms median=%.1fms ratio=%.2f %s" % [
			frame_ms, median,
			(frame_ms / median if median > 0.0 else 0.0),
			_counters_str(),
		])

	# 4d. Memoria.
	var mem := OS.get_static_memory_usage()
	if mem > _peak_memory:
		_peak_memory = mem
	var mem_delta_mb := float(mem - _last_memory) / 1048576.0
	if absf(mem_delta_mb) >= MEMORY_JUMP_MB:
		_mem_leaps_total += 1
		_entry("MEMLEAP", "delta=%+.1fMB now=%.1fMB peak=%.1fMB" % [
			mem_delta_mb,
			float(mem) / 1048576.0,
			float(_peak_memory) / 1048576.0,
		])
		_last_memory = mem

	# 4e. Heartbeat.
	_time_since_heartbeat += frame_ms / 1000.0
	if _time_since_heartbeat >= HEARTBEAT_SEC:
		_time_since_heartbeat = 0.0
		_entry("HEARTBEAT", "frame=%.1fms median=%.1fms %s" % [
			frame_ms, median, _counters_str(),
		])

	# 4f. Scene change.
	var scene := get_tree().current_scene
	var scene_path := "" if scene == null else scene.scene_file_path
	if scene_path != _last_scene_path:
		# Scene OUT del anterior.
		if _last_scene_path != "":
			var dur := Time.get_ticks_msec() - _scene_change_started_ms
			_entry("SCENE", "%s -> %s dur=%dms mem=%.1fMB" % [
				_last_scene_path.get_file(),
				scene_path.get_file(),
				dur,
				float(mem) / 1048576.0,
			])
		_last_scene_path = scene_path
		_scene_change_started_ms = Time.get_ticks_msec()
		# Reset del warmup: los frames del load son muy largos y
		# envenenarian la mediana del scene nuevo.
		_frames_seen = 0
		_frame_times.fill(0.0)


## Handler de notifications del arbol. Android manda WM_GO_BACK_REQUEST y
## NOTIFICATION_APPLICATION_PAUSED/RESUMED, que no llegan como InputEvent.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_paused_at_msec = Time.get_ticks_msec()
		NOTIFICATION_APPLICATION_RESUMED:
			if _paused_at_msec > 0:
				_suspended_ms = Time.get_ticks_msec() - _paused_at_msec
				_paused_at_msec = 0


# ============================================================================
# API publica (para el engine y los mods)
# ============================================================================

## Escribe una linea MARK al log. Los mods lo usan para correlacionar
## eventos propios con las metricas de performance.
func mark(kind: String, detail: String = "") -> void:
	_entry("MARK:" + kind, detail)


## Arranca un timer manual. El `end()` correspondiente loguea el elapsed.
func begin(name: String) -> void:
	_timers[name] = Time.get_ticks_usec()


## Cierra un timer y loguea el elapsed.
func end(name: String) -> void:
	if not _timers.has(name):
		return
	var elapsed_ms := float(Time.get_ticks_usec() - int(_timers[name])) / 1000.0
	_timers.erase(name)
	_entry("TIMER:" + name, "elapsed=%.2fms" % elapsed_ms)


## Fuerza un log completo con motivo custom. Util para capturar un estado
## puntual sin esperar al proximo heartbeat.
func snapshot(reason: String) -> void:
	_entry("SNAPSHOT", "%s %s" % [reason, _counters_str()])


# ============================================================================
# Internals
# ============================================================================

## Escribe una linea al log. Silencioso si _file es null.
func _entry(kind: String, detail: String) -> void:
	if _file == null:
		return
	var seconds := float(Time.get_ticks_msec() - _session_start_ms) / 1000.0
	_file.store_line("[%8.2fs] %-10s %s" % [seconds, kind, detail])


## Colector comun de contadores para HEARTBEAT / SPIKE / SNAPSHOT.
func _counters_str() -> String:
	# Cadena base con los contadores built-in que no estan expuestos como
	# monitor custom.
	var fps := Engine.get_frames_per_second()
	var draw := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var base := "fps=%d draw=%d nodes=%d orphans=%d" % [fps, draw, nodes, orphans]

	# Deltas de pipeline compilation desde la ultima lectura. Si alguno
	# subio en este entry, significa que el engine compilo pipelines en
	# runtime durante el frame (tipo 50-300ms de stall en Adreno con
	# ubershaders deshabilitados). Se muestra siempre, con `+N` solo si
	# hubo cambio, `+0` si no.
	var pc := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS))
	var pm := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH))
	var pd := int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW))
	var pipe_str := "pipe=+%d/+%d/+%d" % [
		pc - _last_pipe_canvas,
		pm - _last_pipe_mesh,
		pd - _last_pipe_draw,
	]
	_last_pipe_canvas = pc
	_last_pipe_mesh = pm
	_last_pipe_draw = pd

	# Metricas propias leidas via los custom monitors que registramos en
	# _ready. Mantener el orden de registro para que la salida sea estable
	# entre entries y facil de diffear.
	var extras: PackedStringArray = []
	for id in PERFORMANCE_EXTRA_IDS:
		if Performance.has_custom_monitor(id):
			# id.replace() en vez de substr(): saca el prefijo "Washos/"
			# sin asumir largos, y aplana "/" a "_" para que el key sea
			# legible en el log (mem_static_mb, perf_median_ms).
			# Tipo explicito: id viene de un Array sin tipar, asi que
			# Godot no puede inferir el tipo de retorno de .replace().
			var short_id: String = String(id).replace("Washos/", "").replace("/", "_")
			extras.append("%s=%s" % [short_id, str(Performance.get_custom_monitor(id))])

	return base + " " + pipe_str + " " + " ".join(extras)




## Mediana del ring buffer de frame times. Filtra los ceros del warmup.
func _median_frame_ms() -> float:
	var valid: Array[float] = []
	for v in _frame_times:
		if v > 0.0:
			valid.append(v)
	if valid.is_empty():
		return 0.0
	valid.sort()
	var n := valid.size()
	if n % 2 == 0:
		return (valid[n / 2 - 1] + valid[n / 2]) * 0.5
	return valid[n / 2]


# ============================================================================
# Apertura + rotacion del archivo
# ============================================================================

func _open_log() -> bool:
	_log_dir = _pick_log_dir()
	if _log_dir.is_empty():
		return false
	_rotate()

	var stamp := Time.get_datetime_string_from_system(false, true) \
		.replace(":", "-").replace(" ", "_")
	log_path = "%s/%s_%s%s" % [_log_dir, LOG_FILE_PREFIX, stamp, LOG_FILE_EXT]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_warning("[PerfProbe] no puedo abrir %s (err=%d)" % [
			log_path, FileAccess.get_open_error(),
		])
		return false
	return true


## Elige la carpeta de logs: Android app-private primero, user:// fallback.
func _pick_log_dir() -> String:
	if OS.get_name() == "Android":
		var pkg := _android_package()
		if not pkg.is_empty():
			var android_dir := ANDROID_APP_LOG_DIR_FMT % pkg
			var err := DirAccess.make_dir_recursive_absolute(android_dir)
			if err == OK or DirAccess.dir_exists_absolute(android_dir):
				# Probe de escritura: en algunos Android modernos el dir
				# existe pero no es escribible sin SAF.
				var probe := android_dir.path_join(".write_probe")
				var pf := FileAccess.open(probe, FileAccess.WRITE)
				if pf != null:
					pf.close()
					DirAccess.remove_absolute(probe)
					return android_dir

	# Fallback.
	var err := DirAccess.make_dir_recursive_absolute(FALLBACK_LOG_DIR)
	if err == OK or DirAccess.dir_exists_absolute(FALLBACK_LOG_DIR):
		return FALLBACK_LOG_DIR
	return ""


## Lee el package name real desde user://. Godot no expone una API; el
## path de user:// en Android es /data/user/0/<pkg>/files. Parsearlo del
## path real es mas robusto que hardcodear el package.
func _android_package() -> String:
	if not _android_pkg.is_empty():
		return _android_pkg
	var up := ProjectSettings.globalize_path("user://")
	# /data/user/0/com.foo.bar/files/...
	var parts := up.split("/")
	for i in parts.size():
		if parts[i] == "0" and i + 1 < parts.size():
			_android_pkg = parts[i + 1]
			return _android_pkg
	return ""


## Rota los logs. Guarda los MAX_LOG_FILES-1 mas nuevos, borra el resto.
func _rotate() -> void:
	var dir := DirAccess.open(_log_dir)
	if dir == null:
		return
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with(LOG_FILE_PREFIX) and f.ends_with(LOG_FILE_EXT):
			files.append(f)
	files.sort()
	var excess := files.size() - (MAX_LOG_FILES - 1)
	for i in maxi(excess, 0):
		DirAccess.remove_absolute(_log_dir.path_join(files[i]))


## Escribe el header del log con info del device / version. Util para
## saber que build produjo el archivo.
func _write_header() -> void:
	_entry("START", "engine=%s v=%s" % [
		Engine.get_version_info().get("string", "?"),
		ProjectSettings.get_setting("application/config/version", "?"),
	])
	_entry("DEVICE", "os=%s model=%s" % [
		OS.get_name(), OS.get_model_name(),
	])
	_entry("GFX", "driver=%s api=%s" % [
		RenderingServer.get_video_adapter_name(),
		"Vulkan" if RenderingServer.get_rendering_device() != null else "OpenGL",
	])
	# Bloque SYNTH: escenas/pantallas como contadores iniciales.
	var scene := get_tree().current_scene
	_entry("SCENE", "initial=%s" % (
		"none" if scene == null else scene.scene_file_path.get_file()
	))
	_entry("MONITORS", "registered=%d ids=%s" % [
		PERFORMANCE_EXTRA_IDS.size() + 6,  # +6 cuenta los monitores no-extra
		", ".join(PERFORMANCE_EXTRA_IDS),
	])
