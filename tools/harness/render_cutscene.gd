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

	if _scene_path.is_empty():
		printerr("OUT falta la escena")
		get_tree().quit(1)
		return

	# Solo se informa; el tamaño del vídeo lo fijó Movie Maker al arrancar.
	print("OUT ventana=%s escena=%s anim=%s hasta=%.2fs" % [
		get_window().size, _scene_path, _anim, _until])

	_swap.call_deferred()


## La escena pasa a ser la escena actual, no un hijo de este nodo: es lo que
## hace que las rutas `../` de las pistas resuelvan igual que en el juego.
func _swap() -> void:
	var err: int = get_tree().change_scene_to_file(_scene_path)
	if err != OK:
		printerr("OUT no se pudo cambiar de escena: %d" % err)
		get_tree().quit(1)
		return

	# change_scene_to_file() es diferido: el árbol nuevo existe en el frame
	# siguiente.
	await get_tree().process_frame
	await get_tree().process_frame

	var current: Node = get_tree().current_scene
	if current == null:
		printerr("OUT la escena no montó")
		get_tree().quit(1)
		return

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
