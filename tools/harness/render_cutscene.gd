extends Node

## Renderiza una cutscene real del juego a vídeo, con Movie Maker.
##
## Por qué no sirve `scene_shot.gd` para esto
## ------------------------------------------
## `scene_shot.gd` hace `add_child(scene)`, o sea que cuelga la canción de un
## nodo intermedio. La escena de Safety Lullaby tiene pistas de animación
## escritas con rutas relativas que suben un nivel - `../IntroCutscene:visible`,
## `../IntroCutscene/Scene/Camera2D:enabled` - y con el nodo de más en medio
## esas rutas apuntan fuera del árbol. El motor lo dice al cargar:
##
##     AnimationMixer 'RESET', couldn't resolve track: '../IntroCutscene:visible'
##     AnimationMixer 'play',  couldn't resolve track: '../IntroCutscene/Scene/Camera2D:enabled'
##
## Ninguno de esos dos avisos sale en el log del dispositivo del 2026-08-24,
## que sí trae los de `Timeline/ReferenceSong`. O sea que son artefactos del
## harness, no del juego - y una captura en la que la visibilidad de la
## cutscene y la cámara no están conducidas no es evidencia de nada. Por eso
## aquí la escena se monta con `change_scene_to_file()`, en el mismo sitio del
## árbol en el que el juego la monta.
##
## Cómo mide el tiempo
## -------------------
## No hay `advance()` a mano. Con `--write-movie` el motor fuerza `--fixed-fps`
## y entrega un delta constante de 1/fps por frame sin mirar el reloj de pared,
## así que el AnimationPlayer avanza solo y el vídeo sale con el tiempo de la
## escena, no con el de la máquina. Lo único que hace este script es cortar.
##
## De qué tamaño sale el vídeo
## ---------------------------
## No de aquí. Movie Maker fija el tamaño al arrancar, antes de que este script
## exista, y lo toma de `window/size/window_width_override` del proyecto - 1366
## x768, que con `stretch/aspect=keep` es justo el área de contenido 16:9 que ve
## el jugador. `--resolution` NO lo cambia: probado, pide la ventana y el vídeo
## sale igual. Tampoco lo cambia redimensionar la ventana desde `_ready()`.
##
## Así que se renderiza al nativo y se escala con ffmpeg después, que además da
## mejor resultado que renderizar pequeño. La resolución de entrega es una
## decisión de coste de decode, no de captura: `ms = 1.32 + 3.49 x Mpx` sobre el
## decodificador del motor, o sea ~3.1ms/frame a 960x540.
##
## Uso:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . \
##     --rendering-driver opengl3 --rendering-method gl_compatibility \
##     --write-movie /ruta/out.avi --fixed-fps 30 --disable-vsync \
##     res://tools/harness/render_cutscene.tscn \
##     -- res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn \
##        anim=play hasta=31.5

var _scene_path: String = ""
var _anim: StringName = &"play"
var _until: float = 5.0
var _preset: String = "High"

var _clock: AnimationPlayer = null
var _elapsed: float = 0.0
var _frames: int = 0


func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() > 0:
		_scene_path = argv[0]
	for i in range(1, argv.size()):
		var a: String = argv[i]
		if a.begins_with("anim="):
			_anim = StringName(a.substr(5))
		elif a.begins_with("hasta="):
			_until = float(a.substr(6))
		elif a.begins_with("preset="):
			_preset = a.substr(7)

	if _scene_path.is_empty():
		printerr("OUT falta la escena")
		get_tree().quit(1)
		return

	_force_preset()

	# Solo se informa; el tamaño del vídeo lo fijó Movie Maker al arrancar.
	print("OUT ventana=%s escena=%s anim=%s hasta=%.2fs" % [
		get_window().size, _scene_path, _anim, _until])

	_swap.call_deferred()


## Graba con el preset MÁS ALTO, no con el que traiga la instalación.
##
## Esto es lo que hace que el vídeo valga la pena y es fácil de olvidar: el
## coste de decodificar no depende de lo bonito que sea el contenido, así que un
## teléfono que corre Very Low puede ver la cutscene en High sin pagar nada.
## Grabar con el preset por defecto sería lo contrario de lo que se busca -
## Very Low es lo que arranca una instalación nueva, y trae `render_scale = 0.5`,
## `disable_shader_effects = true`, `disable_optional_2d_lights = true` y
## `atlas_frame_step = 2` (gdanimate a 12fps en vez de 24). Se habría horneado
## la versión fea, para siempre, en un fichero.
##
## `prefer_cutscene_video` se fuerza a false aparte del preset: si el nodo de
## sustitución ya está puesto en la escena y se graba con un preset que lo
## enciende, el render capturaría el vídeo anterior reproduciéndose dentro del
## nuevo. High no lo enciende, pero eso es una propiedad del .tres de hoy y no
## una garantía, así que se apaga explícitamente.
func _force_preset() -> void:
	var settings: Node = get_node_or_null(^"/root/Settings")
	if settings == null:
		printerr("OUT sin autoload Settings: se graba con lo que haya")
		return

	# Del mapa de constantes del propio Settings, no de rutas repetidas aquí:
	# PRESET_HIGH y compañía son `const`, o sea que `settings.get(...)` no los
	# ve - no son propiedades.
	var key: String = "PRESET_%s" % _preset.to_upper().replace(" ", "_")
	var consts: Dictionary = settings.get_script().get_script_constant_map()
	var chosen: Resource = consts.get(key) as Resource
	if chosen == null:
		printerr("OUT preset '%s' (%s) desconocido; hay: %s" % [
			_preset, key, ", ".join(consts.keys().filter(
				func(k: String) -> bool: return k.begins_with("PRESET_")))])
		return

	chosen.call("apply", settings)
	settings.set("graphics_prefer_cutscene_video", false)
	settings.call("apply_settings")
	print("OUT preset forzado=%s escala=%s" % [
		chosen.get("name"), str(settings.get("graphics_render_scale"))])


## La canción se cuelga DIRECTAMENTE de `root`, como hija suya y hermana de
## este nodo.
##
## Que sea hija de `root` y no de este nodo es el punto entero: las pistas de
## animación de la escena usan rutas relativas que suben un nivel
## (`../IntroCutscene:visible`), y un nodo de más en medio las manda fuera del
## árbol. `scene_shot.gd` hace `add_child(scene)` y por eso el motor le dice
## "couldn't resolve track: '../IntroCutscene:visible'" - avisos que el log del
## dispositivo NO tiene, o sea artefactos del harness.
##
## Lo que NO se puede usar es `change_scene_to_file()`, aunque sea lo obvio y
## sea lo que hacía la primera versión: libera la escena actual, y la escena
## actual es ESTE nodo. Se mataba a sí mismo, `get_tree()` pasaba a devolver
## null en el `await` siguiente y el render moría con
##
##     ERROR: Parameter "data.tree" is null.  at: get_tree()
##     SCRIPT ERROR: Invalid access to property 'process_frame' on a null instance
##
## sin que nadie llamase nunca a `quit()`: Movie Maker seguía grabando la
## escena para siempre, escribiendo AVI crudo a ~46MB cada 20s hasta que se
## cancelase el job. El montaje en sí estaba bien - en ese log no hay un solo
## aviso de `../IntroCutscene` sin resolver - lo único roto era el harness
## sobreviviéndose.
func _swap() -> void:
	var packed: PackedScene = load(_scene_path) as PackedScene
	if packed == null:
		printerr("OUT no se pudo cargar la escena: %s" % _scene_path)
		get_tree().quit(1)
		return

	var current: Node = packed.instantiate()
	var tree: SceneTree = get_tree()
	tree.root.add_child(current)
	# Para cualquier código de la canción que pregunte por la escena actual.
	tree.current_scene = current

	_hide_overlays(current)

	# Un par de frames para que todos los _ready() y los mixers se asienten.
	await tree.process_frame
	await tree.process_frame

	_clock = _find_player(current, _anim)
	if _clock == null:
		printerr("OUT no hay AnimationPlayer con la animación '%s'" % _anim)
		_dump_players(current)
		get_tree().quit(1)
		return

	print("OUT reloj=%s duración=%.2fs" % [
		current.get_path_to(_clock), _clock.get_animation(_anim).length])
	_clock.play(_anim)
	set_process(true)


## Apaga todo lo que dibujan los autoloads, que no es parte de la cutscene.
##
## La primera captura salió con "FPS: 30 · Memory: 124.43 MB" horneado en cada
## fotograma y con el círculo del control de volumen en la esquina. Los dos son
## autoloads - `Debugger` (atl_debug.tscn) y `VolumeSlider` - o sea hijos
## directos de `root`, hermanos de la canción y por tanto fuera de cualquier
## barrido que empiece en la escena.
##
## El barrido es recursivo y por tipo, no por nombre: `Debugger` es un `Node`
## pelado y lo que pinta son sus hijos, mientras que `VolumeSlider` es él mismo
## un `CanvasLayer`. Apagar por nombre habría cogido uno y no el otro, y no
## cubriría el autoload con interfaz que se añada mañana.
func _hide_overlays(keep: Node) -> void:
	var hidden: PackedStringArray = []
	for child: Node in get_tree().root.get_children():
		if child == keep or child == self:
			continue
		_hide_canvas_under(child, hidden)
	print("OUT overlays apagados: %s" % [
		", ".join(hidden) if not hidden.is_empty() else "ninguno"])


func _hide_canvas_under(node: Node, hidden: PackedStringArray) -> void:
	var layer := node as CanvasLayer
	if layer != null and layer.visible:
		layer.visible = false
		hidden.append(node.name)
		return
	var item := node as CanvasItem
	if item != null and item.visible:
		item.visible = false
		hidden.append(node.name)
		return
	for child: Node in node.get_children():
		_hide_canvas_under(child, hidden)


func _process(delta: float) -> void:
	if _clock == null:
		return
	_elapsed += delta
	_frames += 1
	if _elapsed >= _until:
		print("OUT listo: %.2fs de escena en %d frames, anim en %.2fs" % [
			_elapsed, _frames, _clock.current_animation_position])
		get_tree().quit()


func _find_player(root: Node, anim: StringName) -> AnimationPlayer:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var p := node as AnimationPlayer
		if p != null and p.has_animation(anim):
			return p
		for child in node.get_children():
			stack.append(child)
	return null


## Para que un fallo diga qué animaciones SÍ hay, en vez de solo que falta una.
func _dump_players(root: Node) -> void:
	var stack: Array[Node] = [root]
	var found: int = 0
	while not stack.is_empty() and found < 12:
		var node: Node = stack.pop_back()
		var p := node as AnimationPlayer
		if p != null:
			found += 1
			printerr("   %s -> %s" % [
				root.get_path_to(p), ", ".join(p.get_animation_list())])
		for child in node.get_children():
			stack.append(child)
