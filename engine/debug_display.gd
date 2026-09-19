extends CanvasLayer
## Debug display siempre visible en cualquier pantalla. Muestra FPS,
## tiempo de frame, memoria, VRAM, contadores del motor, la escena actual
## y cuantos mods hay cargados.
##
## Autoload, asi que sobrevive los cambios de escena, incluidos los
## cambios a un mod. Layer 190: por encima del MobileControls (80) y del
## gameplay, por debajo del ErrorToast (200) y de las transiciones (4096).
##
## Se puede ocultar con F3 (desktop) o tocando la esquina superior
## izquierda (tactil, 160x160 px). El estado no se persiste en disco: al
## reiniciar la app vuelve al default (START_VISIBLE).
##
## En HolyQuintet el equivalente era debug-build-only y mostraba solo FPS
## y memoria en una linea. Este es universal (siempre visible), muestra
## mas contadores y se puede ocultar sin tocar la build.
##
## Extensiones futuras (sin tocar codigo): cambiar START_VISIBLE,
## REFRESH o el layout del texto. Los contadores de Performance los
## provee el motor y no dependen de nada del proyecto.

const LAYER := 190
## Cada cuanto se actualiza el texto, en segundos. 4 veces por segundo es
## suficiente para leer los numeros sin consumir ciclos de sobra.
const REFRESH := 0.25
## Esquina en la que un tap alterna la visibilidad (touch). En desktop
## F3 hace lo mismo.
const TOGGLE_CORNER := Vector2(160.0, 160.0)
## Si esta en false el overlay arranca oculto. Se puede flipear a true
## para desarrollo sin tocar la logica.
const START_VISIBLE := true

## Fuente del overlay. Usa la del engine si esta disponible; si no, cae
## a la default del sistema.
const FONT_PATH := "res://resources/fonts/fnt_vcr.ttf"
const FONT_SIZE := 28
const OUTLINE_SIZE := 5
const TEXT_COLOR := Color.WHITE
const OUTLINE_COLOR := Color(0.05, 0.03, 0.05, 1.0)
## Espacio entre letras. Negativo para juntarlas (el usuario lo pidio).
## Se aplica con un FontVariation que envuelve la fuente original.
const LETTER_SPACING := -2
## Espacio entre lineas. Negativo para pegar las dos lineas del overlay.
const LINE_SPACING := -4

var _label: Label
var _timer: float = 0.0
## Peak de memoria desde que arranco el proceso. MEMORY_STATIC_MAX
## reporta el maximo absoluto del motor, pero no siempre esta disponible
## en release; este lo trackea a mano por si el monitor del motor no lo
## actualiza en tiempo real.
var _mem_peak_mb: int = 0
## True cuando FileAccess.open() sobre /proc/self/status ya fallo una vez.
## Evita spamear el log con el mismo error cada refresh (4 veces/seg).
var _proc_open_failed: bool = false
## True cuando ya hicimos el dump crudo de /proc/self/status al log.
## Solo se hace una vez por sesion, para no spamear.
var _proc_dump_done: bool = false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_label = Label.new()
	_label.position = Vector2(20.0, 14.0)
	if ResourceLoader.exists(FONT_PATH):
		# FontVariation envuelve la fuente para poder ajustar el spacing
		# entre glifos. La fuente original no se modifica.
		var fv := FontVariation.new()
		fv.base_font = load(FONT_PATH)
		fv.spacing_glyph = LETTER_SPACING
		_label.add_theme_font_override("font", fv)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	# Espacio vertical entre las dos lineas del overlay.
	_label.add_theme_constant_override("line_spacing", LINE_SPACING)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	visible = START_VISIBLE
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer < REFRESH:
		return
	_timer = 0.0
	_refresh()


func _refresh() -> void:
	var fps: int = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / maxf(float(fps), 1.0)

	var mem_now_mb: int
	var mem_peak_mb: int
	if OS.get_name() == "Android":
		# En Android leemos /proc/self/status en vez de
		# Performance.MEMORY_STATIC. En builds release (--export-release)
		# Memory::get_mem_usage() esta compilado a 0, asi que en el APK
		# de release el monitor devolveria 0/0. /proc/self/status siempre
		# esta disponible y da el RSS real del proceso.
		#
		# VmRSS = RSS actual, VmHWM = peak (high water mark).
		# Los dos vienen en kB en el archivo.
		var rss_kb := _read_proc_kb("/proc/self/status", "VmRSS:")
		var hwm_kb := _read_proc_kb("/proc/self/status", "VmHWM:")
		mem_now_mb = rss_kb / 1024
		mem_peak_mb = hwm_kb / 1024
		# Igual trackear en paralelo el peak del motor, por si el /proc
		# alguna vez reporta menos que el pico real del frame.
		if mem_now_mb > _mem_peak_mb:
			_mem_peak_mb = mem_now_mb
		if mem_peak_mb < _mem_peak_mb:
			mem_peak_mb = _mem_peak_mb

		# Fallback: si /proc no dio nada util (0/0), probar el monitor
		# del motor. En debug builds de Android suele estar activo.
		# Cubre el caso de fabricantes que bloquean /proc/self/status
		# o que lo tienen en un formato que no reconocemos.
		if mem_now_mb == 0:
			mem_now_mb = int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576
			if mem_now_mb > _mem_peak_mb:
				_mem_peak_mb = mem_now_mb
			if mem_peak_mb == 0:
				mem_peak_mb = int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576
				if mem_peak_mb < _mem_peak_mb:
					mem_peak_mb = _mem_peak_mb
	else:
		# Fuera de Android (PC, iOS, etc.) usamos el monitor del motor,
		# que en builds de editor y debug está activo.
		mem_now_mb = int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576
		if mem_now_mb > _mem_peak_mb:
			_mem_peak_mb = mem_now_mb
		mem_peak_mb = int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576
		if mem_peak_mb < _mem_peak_mb:
			mem_peak_mb = _mem_peak_mb

	var vram_mb: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576

	var scene_name := _scene_name()
	var mods := _mods_summary()

	# Dos lineas: estado del frame arriba, contexto del mundo abajo.
	_label.text = (
		"FPS: %d (%.1fms)   MEM: %d/%d MB   VRAM: %d MB\n" % [
			fps, frame_ms, mem_now_mb, mem_peak_mb, vram_mb,
		]
		+ "SCENE: %s   MODS: %s" % [scene_name, mods]
	)


## Lee un valor en kB de un archivo tipo /proc/self/status.
## Formato esperado: "VmRSS:	  234560 kB" en alguna linea.
## Devuelve 0 si no encuentra la clave o el archivo no existe.
##
## En Android /proc/self/status es legible sin permisos especiales
## (es por proceso). FileAccess.get_as_text() no sirve porque el
## archivo reporta tamaño 0, por eso leemos con get_line() en loop.
func _read_proc_kb(path: String, key: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		# Log de error solo la primera vez (no en cada refresh).
		# Si esta variable se queda true, ya reportamos el fallo.
		if not _proc_open_failed:
			_proc_open_failed = true
			DebugLog.log("[DebugDisplay] no puedo abrir %s (err=%d)" % [path, FileAccess.get_open_error()])
		return 0

	# Log crudo la PRIMERA vez: nos dice exactamente que formato tiene
	# /proc/self/status en este dispositivo. Distintas versiones de
	# Android y distintos fabricantes pueden cambiar el espaciado,
	# tabs vs espacios, o incluso el encoding. Con esto vemos la verdad
	# en vez de asumir.
	if not _proc_dump_done:
		_proc_dump_done = true
		var dump_count := 0
		while dump_count < 8:
			var dump_line := f.get_line()
			if dump_line.is_empty():
				break
			DebugLog.log("[DebugDisplay] proc[%d] len=%d '%s'" % [dump_count, dump_line.length(), dump_line])
			dump_count += 1
		# Volver al inicio para el parseo normal. NO usamos f.seek(0):
		# /proc/self/status es un archivo virtual del kernel y no
		# garantiza posicionamiento. Cerramos y reabrimos, que es el
		# patron estandar para /proc.
		f.close()
		f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			return 0

	var result := 0
	while true:
		var line := f.get_line()
		if line.is_empty():
			break
		if not line.begins_with(key):
			continue
		# Los campos de /proc/self/status estan separados por tabs, no
		# por espacios. split(" ", false) no los separa, y el token
		# entero ("VmRSS:\t123456") falla is_valid_int(). Normalizamos
		# tabs a espacios antes de splitear para que el numero quede
		# como token aislado.
		for token in line.replace("\t", " ").split(" ", false):
			if token.is_valid_int():
				result = int(token)
				break
		break
	f.close()
	return result


## Nombre del archivo de la escena actual, o su node name si la escena
## no tiene file_path (por ejemplo, un .gd instanciado por el ModSelector
## como nodo raiz, que no es una escena "de verdad").
func _scene_name() -> String:
	if not is_inside_tree():
		return "-"
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return "-"
	var scene: Node = tree.current_scene
	var path: String = scene.scene_file_path
	if not path.is_empty():
		return path.get_file()
	return String(scene.name)


## "N (active: X)" si el ModLoader esta presente, "-" si no.
##
## No depende del ModLoader para funcionar: si no esta, sigue mostrando
## el resto de los contadores. Esto importa porque en un futuro el
## DebugDisplay podria usarse en proyectos sin mods.
func _mods_summary() -> String:
	var ml: Node = get_node_or_null("/root/ModLoader")
	if ml == null:
		return "-"
	var mods = ml.get("mods")
	if not (mods is Array):
		return "-"
	var total: int = mods.size()
	if total == 0:
		return "0"
	var active: int = 0
	for m in mods:
		if m is Dictionary and bool(m.get("enabled", true)):
			active += 1
	return "%d (active: %d)" % [total, active]


func _unhandled_input(event: InputEvent) -> void:
	# F3 en desktop o teclado externo. Se consume el evento para que no
	# lo vea otra pantalla (el editor de dev console tambien escucha F3).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()
		return

	# Tap en la esquina superior izquierda en tactil. Mismo comportamiento
	# que la tecla: alterna visible / oculto. La zona se superpone al
	# MenuVirtualPad si algun dia se pone un boton ahi, pero en las
	# pantallas de menu no hay pad.
	if event is InputEventScreenTouch and event.pressed:
		if event.position.x < TOGGLE_CORNER.x and event.position.y < TOGGLE_CORNER.y:
			visible = not visible
			get_viewport().set_input_as_handled()
