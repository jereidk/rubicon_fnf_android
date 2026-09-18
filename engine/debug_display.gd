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
const FONT_SIZE := 20
const OUTLINE_SIZE := 4
const TEXT_COLOR := Color.WHITE
const OUTLINE_COLOR := Color(0.05, 0.03, 0.05, 1.0)

var _label: Label
var _timer: float = 0.0
## Peak de memoria desde que arranco el proceso. MEMORY_STATIC_MAX
## reporta el maximo absoluto del motor, pero no siempre esta disponible
## en release; este lo trackea a mano por si el monitor del motor no lo
## actualiza en tiempo real.
var _mem_peak_mb: int = 0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_label = Label.new()
	_label.position = Vector2(20.0, 14.0)
	if ResourceLoader.exists(FONT_PATH):
		_label.add_theme_font_override("font", load(FONT_PATH))
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
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

	var mem_now_mb: int = int(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576
	if mem_now_mb > _mem_peak_mb:
		_mem_peak_mb = mem_now_mb

	var vram_mb: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576
	var buf_mb: int = int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576

	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var resources: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	var scene_name := _scene_name()
	var mods := _mods_summary()

	# Dos lineas. La primera es el estado del frame; la segunda, el estado
	# del mundo. Separadas para que se pueda leer de un vistazo sin tener
	# que escanear una sola linea muy larga.
	_label.text = (
		"FPS %d (%.1fms)   MEM %d/%d MB   VRAM %d MB   BUF %d MB\n" % [
			fps, frame_ms, mem_now_mb, _mem_peak_mb, vram_mb, buf_mb,
		]
		+ "NODES %d   OBJ %d   RES %d   DRAW %d   PRIM %d   PROC %.1fms   PHYS %.1fms\n" % [
			nodes, objects, resources, draw_calls, primitives, proc_ms, phys_ms,
		]
		+ "SCENE %s   MODS %s" % [scene_name, mods]
	)


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
