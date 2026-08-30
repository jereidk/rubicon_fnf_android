extends SceneTree

## LullabyCutsceneVideo: la sustitución de una cutscene viva por su vídeo.
##
## Lo que este fichero defiende, y por qué cada cosa importa
## --------------------------------------------------------
## 1. Se retira en silencio si el preset no lo pide. El vídeo es para gama baja;
##    en un teléfono que aguanta la escena viva, la escena viva es mejor.
##
## 2. Se retira en silencio si el .ogv no existe. Esto NO es defensivo por
##    gusto: el vídeo lo produce CI, así que todo checkout de desarrollo corre
##    sin él y la canción tiene que funcionar igual. Mismo criterio que
##    `trance_shaders.gd` cuando Very Low le quita el material - y ese caso
##    llegó al dispositivo como un error rojo por frame antes de arreglarse.
##
## 3. Apaga el `process_mode` de la cutscene, no su `visible`. Las dos mitades
##    importan:
##    - apagar el proceso es lo ÚNICO que ahorra algo, porque el coste medido
##      son 57 AnimationPlayer y 15 AnimationTree evaluándose, no los 5 draw
##      calls (`draw=3-7 prims=68-76 over=0.6x cpu_render=0.6-1.7ms`);
##    - no tocar `visible` es obligatorio, porque el Timeline de la canción
##      anima `../IntroCutscene:visible` con una pista y escribir la misma
##      propiedad desde fuera pelearía con ella. `settings.gd` ya documenta esa
##      trampa para las Light2D; es la razón de que allí se use `enabled`.
##
## 4. Devuelve el mando restaurando el `process_mode` AUTHOREADO, no INHERIT.
##
## 5. Solo corrige la deriva por encima del umbral. Un seek de Theora retrocede
##    por el fichero en bloques de 512 KB hasta el keyframe anterior; corregir
##    cada frame costaría más que la deriva.
##
## Limitación conocida: en headless el servidor de vídeo no decodifica (medido:
## un reproductor en headless cuesta lo mismo que ninguno), así que aquí no se
## comprueba que salgan píxeles. Se comprueba la lógica de sustitución, que es
## la que puede romper la canción.
##
## Run with:
##   godot --headless --path . --script tools/test_cutscene_video.gd

const COMPONENT := "res://lullaby_mod/scripts/lullaby/cutscene/lullaby_cutscene_video.gd"
const PRESET := "res://lullaby_mod/scripts/lullaby/settings/lullaby_quality_preset.gd"
const SETTINGS := "res://menus/settings.gd"
const FIXTURE := "res://tools/fixtures/tiny_cutscene.ogv"
const HARNESS := "res://tools/harness/render_cutscene.gd"
const SONG := "res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn"

var _failures: int = 0
var _checks: int = 0


## Cuenta los errores del motor mientras está instalado.
##
## Godot 4.7 trae `OS.add_logger()` y una clase `Logger` instanciable; el
## proyecto ya la usa en `lullaby_error_log.gd`. `_log_error` corre en el hilo
## que levanta el error y `rationale` trae el mensaje del motor.
class _ErrorSink extends Logger:
	var errors: int = 0
	var messages: PackedStringArray = []

	func _log_error(_function: String, _file: String, _line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array) -> void:
		if error_type != 0:  # 0 = error, 1 = warning
			return
		errors += 1
		if messages.size() < 4:
			messages.append(rationale if not rationale.is_empty() else code)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame

	_wiring_checks()
	await _harness_survives_checks()
	await _behaviour_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _wiring_checks() -> void:
	var code: String = FileAccess.get_file_as_string(COMPONENT)
	_check(not code.is_empty(), "lullaby_cutscene_video.gd se lee")

	# El ajuste viaja por las tres partes del preset o no viaja.
	var preset: String = FileAccess.get_file_as_string(PRESET)
	_check(preset.contains("@export var prefer_cutscene_video"),
		"el preset declara prefer_cutscene_video")
	_check(preset.contains("settings.graphics_prefer_cutscene_video = prefer_cutscene_video"),
		"...y apply() lo copia a los ajustes")
	_check(preset.contains("settings.graphics_prefer_cutscene_video == prefer_cutscene_video"),
		"...y is_matching() lo compara, si no el preset se ve 'Custom' al tocarlo")

	var settings: String = FileAccess.get_file_as_string(SETTINGS)
	_check(settings.contains("var graphics_prefer_cutscene_video"),
		"los ajustes tienen el campo")
	# El prefijo graphics_ es lo que hace que save()/load_from() lo persistan.
	_check(settings.contains("graphics_prefer_cutscene_video"),
		"...con prefijo graphics_, que es lo que lo persiste")

	# La trampa del `visible`.
	_check(not code.contains("live_cutscene.visible") and not code.contains(".visible = "),
		"el componente NO escribe visible en la cutscene (pelearía con la pista)")
	_check(code.contains("live_cutscene.process_mode = Node.PROCESS_MODE_DISABLED"),
		"...apaga el process_mode, que es donde está el coste medido")

	_capture_preset_checks()
	_song_wiring_checks()


## El nodo puesto en Safety Lullaby apunta a nodos que EXISTEN.
##
## Escrito no es lo mismo que resuelto, y este proyecto ya pago esa diferencia:
## las 37 entradas diferidas de console.tscn tenian su NodePath authoreado y
## fallaban todas en silencio porque decia `TabContainer` donde tenia que decir
## `../TabContainer` - un NodePath de un export con node_paths resuelve relativo
## al NODO que lo declara, no a su padre, asi que un hermano necesita `../`.
##
## Se comprueba contra el SceneState y no instanciando la cancion: la escena
## trae 750 nodos y no hace falta ninguno para responder "existe ese hermano".
func _song_wiring_checks() -> void:
	var packed: PackedScene = load(SONG) as PackedScene
	_check(packed != null, "sng_safety_lullaby.tscn carga")
	if packed == null:
		return

	var st: SceneState = packed.get_state()

	# Ruta de cada nodo, sin el `./` con el que SceneState las devuelve. Sin
	# normalizar eso, la primera version de esto buscaba `IntroCutscene` contra
	# un conjunto que dice `./IntroCutscene` y suspendia un cableado correcto.
	var rutas: Dictionary = {}
	for i in st.get_node_count():
		var ruta_i: String = String(st.get_node_path(i))
		if ruta_i.begins_with("./"):
			ruta_i = ruta_i.substr(2)
		rutas[ruta_i] = true

	var idx: int = -1
	for i in st.get_node_count():
		if st.get_node_name(i) == "IntroVideo":
			idx = i
	_check(idx >= 0, "IntroVideo esta en la cancion")
	if idx < 0:
		return

	var props: Dictionary = {}
	for j in st.get_node_property_count(idx):
		props[st.get_node_property_name(idx, j)] = st.get_node_property_value(idx, j)

	# node_paths= en la linea del nodo, sin lo cual los dos exports llegan nulos.
	var texto: String = FileAccess.get_file_as_string(SONG)
	var linea: int = texto.find('[node name="IntroVideo"')
	var fin: int = texto.find("]", linea)
	_check(linea >= 0 and texto.substr(linea, fin - linea).contains(
			'node_paths=PackedStringArray("live_cutscene", "clock")'),
		"...con node_paths= declarado, sin lo cual los exports llegan nulos")

	# Y que las dos rutas lleguen a algun sitio. IntroVideo cuelga de la raiz,
	# asi que `../X` desde el es el hijo X de la raiz.
	for campo: String in ["live_cutscene", "clock"]:
		var ruta: String = String(props.get(campo, ""))
		_check(ruta.begins_with("../"),
			"%s sube un nivel (%s) - un hermano no se alcanza sin ../" % [campo, ruta])
		var destino: String = ruta.substr(3)
		_check(rutas.has(destino),
			"...y %s existe en la cancion (%s)" % [destino, campo])

	_check(String(props.get("video_path", "")).ends_with(".ogv")
			and ResourceLoader.exists(String(props.get("video_path", ""))),
		"el .ogv al que apunta existe (%s)" % props.get("video_path", "-"))
	_check(absf(float(props.get("ends_at", 0.0)) - 31.5) < 0.01,
		"corta en 31.5, donde Environment:visible pasa a true (31.533333)")

	# Y por que el video ya entregado no tiene texto congelado: Lyrics cuelga de
	# Environment, y Environment esta oculto durante toda la ventana.
	#
	# Sobre la animacion `play`, no sobre la primera coincidencia del fichero:
	# varias animaciones escriben `../Environment:visible`, y la primera que
	# aparece es un RESET de una sola llave. La primera version de este check
	# leia esa y acertaba por casualidad.
	var play_ini: int = texto.find('resource_name = "play"')
	var play_fin: int = texto.find("[sub_resource", play_ini)
	var play: String = texto.substr(play_ini, play_fin - play_ini)
	var env := RegEx.create_from_string(
		r'NodePath\("\.\./Environment:visible"\)(?:.|\n)*?"times": PackedFloat32Array\(([^)]*)\)(?:.|\n)*?"values": \[([^\]]*)\]'
		).search(play)
	_check(env != null, "la animacion play tiene la pista Environment:visible")
	if env != null:
		var valores: String = env.get_string(2).strip_edges()
		_check(valores.begins_with("false"),
			"Environment arranca OCULTO en play (%s), que deja a Lyrics fuera del video"
				% valores)
		_check(env.get_string(1).contains("31.5"),
			"...y se enciende en 31.5, donde corta el video (%s)" % env.get_string(1))
	_check(texto.contains('[node name="Lyrics" parent="Environment"'),
		"...y Lyrics sigue colgando de Environment, no de otro sitio")

	# Y que algun preset lo encienda: el componente puede estar perfecto y no
	# hacer nada nunca si ningun .tres pide video.
	var encendido: PackedStringArray = []
	for nombre: String in ["qol_very_low", "qol_low", "qol_medium", "qol_high"]:
		var tres: String = FileAccess.get_file_as_string(
			"res://lullaby_mod/resources/quality_presets/%s.tres" % nombre)
		if tres.contains("prefer_cutscene_video = true"):
			encendido.append(nombre)
	_check(encendido.size() == 4,
		"los cuatro presets piden video (%s)" % ", ".join(encendido))
	# Invertida a proposito. Esto exigia `not encendido.has("qol_high")`, con la
	# razon "donde la escena viva corre, la escena viva es mejor". Sustituir la
	# cutscene entera en todos los presets es ahora la intencion del proyecto.
	#
	# Sin fingir que sale gratis: el video se entrega a 960 y el arte esta
	# authoreado a 1280x720, asi que en High se deja un 25% lineal. La anchura
	# no la elige la calidad, la elige el presupuesto de frame del telefono mas
	# lento - Theora decodifica en el hilo principal y 1280x720 se acerca a
	# 14ms de los 16.7 que hay a 60fps en un A12. Subir la anchura "porque el
	# arte da para mas" ya se intento una vez y era mirar solo la mitad de la
	# ecuacion.
	_check(encendido.has("qol_high"),
		"...High incluido: es la intencion, con el 25% lineal como precio")


## El render tiene que grabar con el preset MÁS ALTO.
##
## Es lo que hace que el cambio valga la pena: decodificar cuesta lo mismo sea
## el contenido bonito o feo, así que un teléfono en Very Low ve la cutscene en
## High gratis. La primera versión de render_cutscene.gd no forzaba nada, y el
## preset de una instalación nueva es Very Low - se habría horneado
## `render_scale = 0.5`, sin efectos de shader, sin luces 2D opcionales y
## gdanimate a 12fps, para siempre, en un fichero de dos megas. Que el fallo
## fuese invisible (el vídeo saldría, solo que feo) es lo que lo hace peligroso
## y lo que justifica fijarlo aquí.
func _capture_preset_checks() -> void:
	var harness: String = FileAccess.get_file_as_string(HARNESS)
	_check(not harness.is_empty(), "render_cutscene.gd se lee")
	_check(harness.contains('var _preset: String = "High"'),
		"el render graba con High por defecto, no con lo que traiga la instalación")

	var body: String = _func_body(harness, "_force_preset")
	_check(body.contains("get_script_constant_map()"),
		"...saca el preset del mapa de constantes de Settings (son const, no propiedades)")
	_check(body.contains('call("apply", settings)') and body.contains('call("apply_settings")'),
		"...lo aplica de verdad, no solo lo carga")
	_check(body.contains('set("graphics_prefer_cutscene_video", false)'),
		"...y apaga la sustitución, para no grabar el vídeo anterior dentro del nuevo")

	# Y que se llame ANTES de montar la escena: aplicarlo después dejaría la
	# escena construida con los ajustes viejos.
	var force_at: int = harness.find("_force_preset()")
	var swap_at: int = harness.find("_swap.call_deferred()")
	_check(force_at >= 0 and swap_at > force_at,
		"...antes de montar la escena, no después")

	# El bug que costó la corrida #179: change_scene_to_file() libera la escena
	# actual, y la escena actual es el propio harness.
	#
	# Sobre el CÓDIGO, no sobre el fichero: el docstring del harness nombra
	# `change_scene_to_file()` justo para explicar por qué no se usa, y la
	# primera versión de este check se lo comió y dio rojo sobre el arreglo
	# correcto. Es el mismo tropiezo que test_console_wiring.gd tuvo con
	# "TabContainer".
	_check(not _code_only(harness).contains("change_scene_to_file"),
		"el harness NO usa change_scene_to_file (se liberaría a sí mismo)")
	_check(_func_body(harness, "_swap").contains("tree.root.add_child(current)"),
		"...cuelga la canción de root directamente, sin un nodo en medio")


## Y ahora ejecutándolo, porque los dos checks de texto de arriba son la lección
## de ayer y no protegen de la de mañana.
##
## En la corrida #179 el harness llamó a `change_scene_to_file()`, que liberó la
## escena actual - o sea el harness - y el `await get_tree().process_frame` de
## la línea siguiente reventó contra un `null`. Nadie llamó nunca a `quit()`, así
## que Movie Maker se quedó grabando la canción indefinidamente. Lo que hace que
## eso sea caro no es el fallo, es que el fallo NO PARA el render.
##
## Así que esto monta el harness contra una escena de juguete y comprueba lo
## único que importa: que después de montar siga vivo y con árbol.
func _harness_survives_checks() -> void:
	var script: GDScript = load(HARNESS)
	_check(script != null, "render_cutscene.gd carga como script")
	if script == null:
		return

	# Una escena mínima con un AnimationPlayer y una animación conocida, para no
	# acoplar la prueba a contenido del juego.
	var toy_root := Node2D.new()
	toy_root.name = "Juguete"
	var player := AnimationPlayer.new()
	player.name = "Timeline"
	var anim := Animation.new()
	anim.length = 12.0
	var lib := AnimationLibrary.new()
	lib.add_animation(&"play", anim)
	player.add_animation_library(&"", lib)
	toy_root.add_child(player)
	player.owner = toy_root

	# Dentro de la escena, no colgado de root: ahi el barrido de autoloads no
	# llega, asi que si se esconde solo puede haberlo hecho el del grupo. La
	# primera version lo puso de hermano de la escena y pasaba por el barrido
	# equivocado - la mutacion que quitaba _hide_live_overlays sobrevivia.
	var subtitulo := Label.new()
	subtitulo.name = "SubtituloFalso"
	# El `true` es obligatorio: add_to_group() sin el, el grupo NO se guarda en
	# el PackedScene y el nodo llega al arbol sin el. La escena real lo trae
	# authoreado (`groups = [...]`), que es lo mismo que persistente.
	subtitulo.add_to_group(&"cutscene_live_overlay", true)
	toy_root.add_child(subtitulo)
	subtitulo.owner = toy_root

	var packed := PackedScene.new()
	packed.pack(toy_root)
	var toy_path: String = "user://toy_cutscene.tscn"
	_check(ResourceSaver.save(packed, toy_path) == OK, "se guarda la escena de juguete")
	toy_root.queue_free()

	# Dos autoloads de mentira, uno de cada forma que el juego tiene de verdad:
	# `VolumeSlider` es él mismo un CanvasLayer, y `Debugger` es un Node pelado
	# cuyos HIJOS pintan. Apagar por nombre habría cogido uno solo; la primera
	# captura salió con el "FPS: 30 · Memory: 124.43 MB" horneado en cada
	# fotograma por exactamente eso.
	var capa := CanvasLayer.new()
	capa.name = "VolumenFalso"
	root.add_child(capa)
	var pelado := Node.new()
	pelado.name = "DebuggerFalso"
	var etiqueta := Label.new()
	etiqueta.name = "EtiquetaFPS"
	pelado.add_child(etiqueta)
	root.add_child(pelado)

	# Y lo que la escena viva va a seguir dibujando: subtitulos.
	#
	# Un video pre-renderizado congela el idioma. La sonda de Chimera trae
	# "Serena Yvonne Gabena, 20 years old..." horneado en ingles, y esa cadena
	# esta en ui_strings.csv traducida a es y pt_BR - un jugador en español
	# habria visto ingles pegado al video. Se arregla porque UILayer es capa 1 y
	# el video capa 0: el texto vivo ya va encima, solo sobra la copia.
	var node: Node = script.new()
	node.set("_scene_path", toy_path)
	node.set("_anim", &"play")
	node.set("_until", 999.0)  # que no corte durante la prueba
	root.add_child(node)

	await node.call("_swap")
	await process_frame

	_check(not capa.visible,
		"apaga el autoload que ES un CanvasLayer (como VolumeSlider)")
	_check(not etiqueta.visible,
		"...y el que solo TIENE hijos que pintan (como Debugger)")
	var montado_sub: Node = root.get_node_or_null(^"Juguete/SubtituloFalso")
	_check(montado_sub != null and not (montado_sub as CanvasItem).visible,
		"y saca del horneado lo marcado como cutscene_live_overlay (subtitulos)")
	capa.queue_free()
	pelado.queue_free()

	_check(is_instance_valid(node), "el harness sigue VIVO después de montar la escena")
	if is_instance_valid(node):
		_check(node.get_tree() != null,
			"...y sigue en el árbol, que es lo que reventó en la corrida #179")
		_check(node.get("_clock") != null,
			"...y encontró el reloj de la escena montada")

	var mounted: Node = root.get_node_or_null(^"Juguete")
	_check(mounted != null, "la canción quedó colgada de root")
	if mounted != null:
		_check(mounted.get_parent() == root,
			"...directamente de root, sin un nodo en medio que rompa las rutas ../")
		mounted.queue_free()
	if is_instance_valid(node):
		node.queue_free()
	await process_frame


func _behaviour_checks() -> void:
	var script: GDScript = load(COMPONENT)
	_check(script != null, "el componente carga")
	if script == null:
		return
	_check(ResourceLoader.exists(FIXTURE), "existe el .ogv de prueba")

	# --- 1. El preset no lo pide: no se toca nada.
	var off := _mount(script, FIXTURE, false)
	_check(off.live.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"preset apagado: la cutscene conserva su process_mode authoreado")
	_check(_video_players(off.node) == 0, "preset apagado: no se crea reproductor")
	off.node.queue_free()
	await process_frame

	# --- 2. El preset lo pide pero no hay fichero: se retira igual, EN SILENCIO.
	#
	# El silencio es la mitad que importa y la que casi se me escapa. Quitar la
	# guarda `ResourceLoader.exists()` no cambia el comportamiento -`load()`
	# devuelve null y el componente se retira por la rama de abajo- así que una
	# prueba que solo mire el process_mode y el reproductor pasa igual. Lo que
	# sí cambia es que `load()` de un fichero que no existe empuja un error rojo
	# por cada canción cargada. Este proyecto tiene un `.error` entero dedicado a
	# cazar justo eso, así que aquí se cuenta con la misma API: OS.add_logger().
	var sink := _ErrorSink.new()
	OS.add_logger(sink)
	var missing := _mount(script, "res://tools/fixtures/no_existe.ogv", true)
	OS.remove_logger(sink)
	_check(missing.live.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"sin .ogv: la cutscene sigue viva (CI aún no lo produjo)")
	_check(_video_players(missing.node) == 0, "sin .ogv: no se crea reproductor")
	_check(sink.errors == 0,
		"sin .ogv: y sin un solo error rojo (%d capturados: %s)"
			% [sink.errors, ", ".join(sink.messages)])
	missing.node.queue_free()
	await process_frame

	# --- 3. Con preset y fichero: sustituye.
	var on := _mount(script, FIXTURE, true)
	_check(_video_players(on.node) == 1, "con preset y fichero: hay un reproductor")
	_check(on.live.process_mode == Node.PROCESS_MODE_DISABLED,
		"...y la cutscene deja de procesar")
	_check(on.live.visible, "...pero sigue visible: el nodo no le toca esa propiedad")

	# Y que el reproductor OCUPE la pantalla. Un Control al que se le escriben
	# las anclas antes de tener padre se queda en (0,0): existe, reproduce y no
	# dibuja nada. Eso llego al telefono como una pantalla gris - el video
	# invisible y detras la cutscene congelada, porque a esa ya se le habia
	# apagado el process_mode. Un check de tamano cuesta una linea.
	await process_frame
	var reproductor: Control = null
	var pila: Array[Node] = [on.node]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is VideoStreamPlayer:
			reproductor = n
		for c in n.get_children():
			pila.append(c)
	_check(reproductor != null and reproductor.size.x > 0.0 and reproductor.size.y > 0.0,
		"el reproductor ocupa la pantalla (%s)" % [reproductor.size if reproductor else "sin reproductor"])

	# --- 4. Devuelve el mando al pasar el final, restaurando lo authoreado.
	on.clock.play(&"linea")
	on.clock.seek(9.0, true)
	on.node.call("_process", 0.016)
	_check(on.live.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"pasado el final: restaura el process_mode AUTHOREADO, no INHERIT")
	on.node.queue_free()
	await process_frame

	# --- 5. La deriva solo se corrige por encima del umbral.
	var drift := _mount(script, FIXTURE, true)
	drift.clock.play(&"linea")
	drift.node.set("max_drift", 0.25)
	# Dentro del umbral: ni un seek.
	drift.clock.seek(0.1, true)
	drift.node.call("_process", 0.016)
	_check(int(drift.node.call("drift_corrections")) == 0,
		"deriva por debajo del umbral: no se toca el reproductor")
	# Fuera del umbral: uno.
	drift.clock.seek(3.0, true)
	drift.node.call("_process", 0.016)
	_check(int(drift.node.call("drift_corrections")) == 1,
		"deriva por encima del umbral: un seek, no uno por frame")
	drift.node.call("_process", 0.016)
	_check(int(drift.node.call("drift_corrections")) <= 2,
		"...y no se dispara en cascada")
	drift.node.queue_free()
	await process_frame


## Monta el componente con una cutscene falsa y un reloj de verdad.
func _mount(script: GDScript, path: String, wanted: bool) -> Dictionary:
	var host := Node.new()
	root.add_child(host)

	# El singleton que el componente consulta. Un Node en /root con el nombre
	# que busca, para no depender del autoload real.
	var settings: Node = root.get_node_or_null(^"Settings")
	if settings == null:
		settings = Node.new()
		settings.name = "Settings"
		root.add_child(settings)
	settings.set("graphics_prefer_cutscene_video", wanted)

	var live := Node2D.new()
	live.name = "LiveCutscene"
	live.process_mode = Node.PROCESS_MODE_PAUSABLE
	host.add_child(live)

	var clock := AnimationPlayer.new()
	var anim := Animation.new()
	anim.length = 40.0
	var library := AnimationLibrary.new()
	library.add_animation(&"linea", anim)
	clock.add_animation_library(&"", library)
	host.add_child(clock)

	var node: Node = script.new()
	node.set("live_cutscene", live)
	node.set("video_path", path)
	node.set("clock", clock)
	node.set("starts_at", 0.0)
	node.set("ends_at", 8.0)
	host.add_child(node)

	return {"node": node, "live": live, "clock": clock, "host": host}


func _video_players(node: Node) -> int:
	var found: int = 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VideoStreamPlayer:
			found += 1
		for child in n.get_children():
			stack.append(child)
	return found


## El fichero sin sus comentarios, para que un check mire lo que se ejecuta.
func _code_only(text: String) -> String:
	var out: PackedStringArray = []
	for line: String in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


func _func_body(text: String, name: String) -> String:
	var head: int = -1
	var from: int = 0
	while true:
		var at: int = text.find("func %s(" % name, from)
		if at < 0:
			break
		if at == 0 or text[at - 1] == "\n":
			head = at
			break
		from = at + 1
	if head < 0:
		_check(false, "%s() existe al nivel superior" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
