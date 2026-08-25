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

## Posicion del reloj desde la que empezar. 0 = desde el principio.
##
## SOLO PARA SONDEAR, y la razon importa: adelantar el reloj con seek() aplica
## las pistas de valor hasta ese punto, pero NO vuelve a disparar las pistas de
## metodo que ya pasaron. En Chimera la pista `../Sequences/SequencePlayer`
## tiene llaves en 0.0, 3.0, 19.9167 y 34.5833 - saltar a 19.9 aplica el estado
## visible pero no ejecuta las dos llamadas anteriores, asi que lo que sale
## puede no ser lo que el jugador ve.
##
## Para una captura de entrega hay que grabar desde 0. Esto existe para
## responder "¿esta parte sale iluminada?" en dos minutos en vez de treinta.
var _from: float = 0.0
var _preset: String = "High"

## MSAA para la captura. Vacio = lo que diga el preset.
##
## `msaa=off` existe porque en esta ruta el MSAA es casi todo desperdicio: se
## renderiza al nativo del proyecto (1366x768) y se entrega escalado a 960, y
## ese reescalado de ffmpeg ya promedia ~1.4 pixeles por pixel de salida, que
## es antialiasing. Encima el rasterizador de CI es por software, donde MSAA 2
## multiplica el trabajo de fragmento de verdad.
##
## Lo que cuesta: los bordes de geometria salen algo mas duros ANTES del
## reescalado. Por eso es una opcion explicita y no un apagado silencioso -
## degradar la captura a espaldas de quien la pide es justo lo que
## `preset=High` existe para evitar.
var _msaa: String = ""

## Escala del bufer 3D para la captura. <= 0 = lo que diga el preset.
##
## Es LA palanca en una escena 3D y no sirve para nada en una 2D, porque
## `scaling_3d_scale` escala solo el bufer 3D - el 2D siempre se dibuja a la
## resolucion completa de la ventana. Safety Lullaby es 2D pura
## (`rend=[3d=0/0/0]`) y esto no la habria tocado; Chimera es lo contrario.
##
## Se entrega escalado a 960 de ancho desde un nativo de 1366, asi que 0.75
## deja el bufer 3D en 1024 - por encima de la entrega, perdida despreciable -
## y 0.5 lo deja en 683, por debajo, o sea visiblemente blando.
var _scale: float = 0.0

## Grupo de lo que NO se hornea: la escena viva lo sigue dibujando.
##
## jereidk lo cazo antes de que llegase a una entrega: los subtitulos cambian de
## idioma en vivo, y un video pre-renderizado los congela. La sonda de Chimera
## lo demuestra - trae "Serena Yvonne Gabena, 20 years old. Photos recovered
## on-site." horneado en ingles, y esa cadena exacta esta en ui_strings.csv con
## su traduccion al español y al portugues. Un jugador en español habria visto
## ingles pegado al video para siempre.
##
## Lo que lo hace arreglable es la geometria de capas que ya teniamos: `UILayer`
## es un CanvasLayer en capa 1 y el video se dibuja en la 0, o sea que el texto
## VIVO ya queda por encima del video. Solo sobra la copia horneada. Marcando el
## nodo en este grupo, la captura lo esconde y la reproduccion lo deja en paz,
## asi que sale traducido y encima.
##
## Cuidado con el caso que esto NO resuelve: un texto que viva por DEBAJO del
## video (en el lienzo por defecto, dentro del subarbol de la cutscene) queda
## tapado en reproduccion, asi que esconderlo en la captura lo hace invisible en
## los dos lados. Ese hay que subirlo de capa antes, o esa cutscene no puede ir
## a video.
const LIVE_OVERLAY_GROUP := &"cutscene_live_overlay"

var _clock: AnimationPlayer = null
var _elapsed: float = 0.0
var _frames: int = 0
var _started: int = 0
var _last_report: int = 0

## Frames ya contados en el latido anterior, para medir el coste del tramo en
## vez del promedio desde el arranque.
var _last_frames: int = 0


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
		elif a.begins_with("msaa="):
			_msaa = a.substr(5)
		elif a.begins_with("desde="):
			_from = float(a.substr(6))
		elif a.begins_with("escala="):
			_scale = float(a.substr(7))

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
	if _msaa == "off":
		settings.set("graphics_msaa_3d_quality", Viewport.MSAA_DISABLED)
	if _scale > 0.0:
		settings.set("graphics_render_scale", _scale)
	settings.call("apply_settings")
	print("OUT preset forzado=%s escala=%s msaa=%s" % [
		chosen.get("name"), str(settings.get("graphics_render_scale")),
		str(settings.get("graphics_msaa_3d_quality"))])


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
	_hide_live_overlays(current)

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
	_started = Time.get_ticks_msec()
	_last_report = _started
	_clock.play(_anim)
	if _from > 0.0:
		_clock.seek(_from, true)
		_elapsed = _from
		print("OUT SONDA: arrancando en %.2fs - las pistas de metodo anteriores"
			% _from + " no se dispararon, esto no vale como entrega")
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


## Esconde lo que la escena viva va a seguir dibujando encima del video.
func _hide_live_overlays(scene: Node) -> void:
	var hidden: PackedStringArray = []
	for node: Node in get_tree().get_nodes_in_group(LIVE_OVERLAY_GROUP):
		var item := node as CanvasItem
		if item != null:
			item.visible = false
			hidden.append(scene.get_path_to(node))
			continue
		var layer := node as CanvasLayer
		if layer != null:
			layer.visible = false
			hidden.append(scene.get_path_to(node))
	print("OUT fuera del horneado (%s): %s" % [
		LIVE_OVERLAY_GROUP,
		", ".join(hidden) if not hidden.is_empty() else "nada marcado"])


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

	# Un latido cada cinco segundos de reloj de pared.
	#
	# Sin esto el paso no imprime nada entre "reloj=" y "listo", y un render 3D
	# bajo GL por software tarda minutos: no hay forma de distinguir lento de
	# colgado. Ya paso dos veces - una era un cuelgue de verdad (el harness se
	# libero a si mismo, corrida #179) y la otra no lo era, y desde fuera se
	# veian igual. Ese es el problema que esto resuelve, no la impaciencia.
	var ahora: int = Time.get_ticks_msec()
	if ahora - _last_report >= 5000:
		var por_hacer: float = maxf(_until, 0.001)

		# Coste por frame de ESTE tramo, no del total, y el que queda.
		#
		# Anadido despues de estimar mal una corrida por un factor que resulto
		# no serlo: extrapolar los primeros 40 frames de Chimera daba 3.0h y la
		# corrida tardo 3h08m, o sea que acerto - pero acerto por suerte, con
		# una regla de tres hecha a mano sobre un porcentaje. La otra vez que
		# se hizo lo mismo el resultado fue "87 minutos" para un render que se
		# cancelo sin llegar a saberse. El paso puede calcular esto solo, y
		# quien mira el log no deberia tener que hacer aritmetica para saber si
		# le da tiempo a cenar.
		#
		# Por tramo y no acumulado porque los primeros frames pagan costes que
		# no se repiten - compilar pipelines, subir texturas - y un promedio
		# desde el arranque los reparte sobre todo el render y miente hacia
		# arriba justo cuando mas se mira, al principio.
		# `delta` es exacto aqui y no una medida: con --fixed-fps Godot entrega
		# siempre 1/fps pase lo que pase con el reloj de pared, que es la misma
		# propiedad por la que Movie Maker puede grabar a 60fps en una maquina
		# que va a 0.2. Asi que los frames que faltan son una division, no una
		# estimacion.
		var ms_frame: float = float(ahora - _last_report) / maxf(float(_frames - _last_frames), 1.0)
		var faltan_frames: float = maxf(_until - _elapsed, 0.0) / maxf(delta, 0.0001)
		var quedan: float = faltan_frames * ms_frame / 1000.0

		# Donde se va el tiempo, para no volver a adivinarlo. Bajo un
		# rasterizador por software el coste es de fragmento, asi que el tamano
		# del bufer 3D y la cantidad de geometria son las dos palancas, y hasta
		# ahora ninguna de las dos salia en el log.
		var draws: int = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims: int = RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)

		print("OUT progreso %.1f%%  %d frames  %.1fs de %.1fs  %.0f ms/frame  faltan ~%s  draw=%d prims=%d" % [
			100.0 * _elapsed / por_hacer, _frames, _elapsed, _until,
			ms_frame, _reloj(quedan), draws, prims])
		_last_report = ahora
		_last_frames = _frames

	if _elapsed >= _until:
		print("OUT listo: %.2fs de escena en %d frames, anim en %.2fs" % [
			_elapsed, _frames, _clock.current_animation_position])
		get_tree().quit()


## Segundos como "1h23m" / "12m40s" / "45s", que es como se lee una espera.
func _reloj(segundos: float) -> String:
	var total: int = int(round(maxf(segundos, 0.0)))
	if total >= 3600:
		return "%dh%02dm" % [total / 3600, (total % 3600) / 60]
	if total >= 60:
		return "%dm%02ds" % [total / 60, total % 60]
	return "%ds" % total


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
