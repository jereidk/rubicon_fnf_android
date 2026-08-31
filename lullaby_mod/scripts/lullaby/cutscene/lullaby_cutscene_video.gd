class_name LullabyCutsceneVideo
extends Node

## Dibuja una cutscene con un vídeo pre-renderizado en vez de con la escena viva.
##
## Por qué existe
## -------------
## Medido en el log del dispositivo del 2026-08-24: la intro de Safety Lullaby
## corre de 198.76s a 230.3s -31.5 segundos- y un tercio de sus frames pasan de
## 28ms. No es relleno y no es el renderizador:
##
##     draw=3-7  prims=68-76  rend=[3d=0/0/0]  over=0.6x  cpu_render=0.6-1.7ms
##
## Cinco draw calls y menos de una pantalla de relleno. Lo que cuesta es CPU de
## animación: `intro.tscn` son 22 nodos sin un solo script, pero el censo cuenta
## `anim_players=57 trees=15(active=15) anim_tracks=89-105` porque la escena
## entera de la canción está corriendo detrás de la cutscene. Los picos son de
## 50-86ms y caen en las transiciones de plano.
##
## Descartados con evidencia del mismo log: creación de pipelines
## (`pipe=347(+0 ... +0)` en toda la intro), subida de texturas
## (`vram_delta=+0.0MB` en todos los picos), gdanimate (`anim2d=0.00ms/s`, no
## despierta hasta 232.28) y reconstrucción de cachés de mixer (el aviso
## `couldn't resolve track` sale dos veces en toda la sesión).
##
## Un vídeo cambia todo eso por un coste conocido y plano. Medido sobre el
## decodificador real del motor (Xeon @2.10GHz, 4 reproductores para sacar la
## señal del ruido, base 10.68s):
##
##     800x360   0.29 Mpx   2.31 ms/frame
##     960x432   0.42 Mpx   2.78 ms/frame
##     1280x576  0.74 Mpx   3.94 ms/frame
##     1600x720  1.15 Mpx   5.33 ms/frame     ms = 1.32 + 3.49 x Mpx
##
## libtheora va en C genérico en TODAS las plataformas -`x86_libtheora_opt_gcc`
## y `_vc` están fijos a False en el SConstruct de Godot y no se activan en
## ningún sitio del árbol, y la carpeta `arm/` ni siquiera está vendorizada-,
## así que esa medición y el teléfono ejecutan el mismo código y la
## extrapolación es solo microarquitectura. A 960x432 son ~3ms en el g53 y
## ~8.5ms en un A12, cada 1/30s, sin picos.
##
## Tres modos, y la diferencia importa
## -----------------------------------
## CON `live_cutscene`: la escena viva sigue en el árbol y el vídeo se pone
## ENCIMA en su propio CanvasLayer. Se le apaga el `process_mode` Y el `visible`.
##
## El `visible` no se tocaba, y el relleno de la cutscene tapada se daba por
## desperdicio consciente para no pelearse con las pistas que animan esa misma
## propiedad -la trampa que `settings.gd` documenta para las Light2D-. El log
## 10226-4fe0a6db puso precio a ese desperdicio, en todos los censos del prelude:
##
##     over=2.1x  relleno=[PreludeVideo/...VideoStreamPlayer@1.00x,
##                         Intro/ColorRect2@1.00x, ...]
##
## `Intro/ColorRect2` es un ColorRect de 1957x1103 -pantalla entera y de sobra-,
## negro OPACO y con un ShaderMaterial encima: una pasada de shader a pantalla
## completa por fotograma, debajo de un vídeo que la tapa del todo. Duplicaba el
## overdraw del tramo él solo.
##
## Se apaga guardando el valor y devolviéndolo SOLO si nadie lo cambió mientras
## tanto, que es lo que hace segura la pelea con las pistas: si otra escribe,
## gana ella y este apaño deja de aplicarse. Degrada en vez de corromper.
##
## SIN `live_cutscene`: la escena viva ya no está. Es el caso de Safety
## Lullaby desde que se midió que ningún preset la elegía - los cuatro ponen
## `prefer_cutscene_video` y el flag no está en la interfaz-, así que sus 8.2 MB
## de sprites se cargaban, ocupaban RAM y viajaban en el APK para no dibujarse
## nunca. Ahí el vídeo no es una preferencia de calidad, es la cutscene: no hay
## `process_mode` que apagar, y `_wanted()` deja de consultar al preset.
##
## SIN `live_cutscene` pero CON `live_fallback_exists`: la escena viva está
## entera, pero repartida. Es la sesión de fotos de Chimera: catorce clips de
## `103_stroll` a `116_hexstare` sobre seis nodos de `Sequences`, sin un padre
## común que apagar - `Sequences` lleva dentro `ReferenceSong`, la referencia de
## sincronía de la canción, y `SequencePlayer`, que dispara los clips. Ahí no se
## apaga a nadie el proceso; lo que se ahorra es el pase 3D, con
## `disable_3d_while_playing`, porque ese tramo iba a 30fps por GPU y no por CPU.
##
## Cuándo empieza a dibujarse
## --------------------------
## Cuando el reloj llega a `starts_at`, no en `_ready()`. La prelude tiene
## `starts_at = 0.0` y con ella daba igual; la sesión de fotos empieza en 53.7s y
## un reproductor arrancado en `_ready()` habría tapado la prelude y el intro
## desde el primer fotograma de la canción.
##
## Se retira en silencio si no hay vídeo. El `.ogv` lo produce CI, así que un
## checkout de desarrollo no lo tiene y la canción tiene que funcionar igual -
## mismo criterio que `trance_shaders.gd` cuando el preset le quita el material.

## El nodo de la cutscene viva a la que se le apaga el proceso Y el dibujado
## mientras corre el vídeo (ver arriba).
##
## OPCIONAL, y vacío puede querer decir dos cosas distintas - las separa
## `live_fallback_exists`:
##
##   * vacío y `live_fallback_exists = false`: la cutscene viva se retiró del
##     árbol y no hay a qué volver. Safety Lullaby. El preset deja de opinar.
##   * vacío y `live_fallback_exists = true`: la cutscene viva sigue ahí pero no
##     hay un solo nodo que apagar. La sesión de fotos de Chimera. El preset
##     sigue decidiendo.
@export var live_cutscene: Node

## Que exista una versión viva a la que volver, aunque no haya un solo nodo al
## que apagarle el `process_mode`.
##
## `live_cutscene` hacía dos trabajos a la vez: decir a quién se apaga, y decir
## si hay algo a lo que caer si el preset dice que no al vídeo. Para la prelude
## coinciden -un nodo, `Intro`- pero para la sesión de fotos de Chimera no: son
## catorce clips (`103_stroll` a `116_hexstare`) repartidos por seis nodos de
## `Sequences`, y no hay un padre común que se pueda apagar sin llevarse por
## delante `ReferenceSong` -la referencia de sincronía de la canción- y
## `SequencePlayer`, que es quien dispara los clips.
##
## Así que ahí `live_cutscene` va vacío y esto va a `true`: no se apaga a nadie,
## pero el preset SÍ decide, porque la escena viva sigue estando entera.
@export var live_fallback_exists: bool = false

## Saltarse el pase 3D del viewport mientras el vídeo tapa la pantalla.
##
## No es lo mismo que apagar `process_mode` y para la sesión de fotos es lo
## único que sirve. Dos razones, las dos medidas:
##
##   * Los clips los mueve `SequencePlayer`, que es HERMANO de los nodos que
##     anima. Apagarle el proceso al nodo destino no impide que un
##     AnimationPlayer de fuera le siga escribiendo propiedades.
##   * `104_photographysesh` iba a 30fps con 23.5ms de GPU, 54 draw calls y
##     26565 primitivas. El cuello es el pase 3D, no la animación.
##
## `disable_3d` deja las animaciones corriendo -solo no las dibuja-, que es
## justo lo que hace falta: en 113.140144s el mando vuelve a la mecánica de
## heartbeat y la cámara y las poses tienen que estar donde el clip las dejó.
## Apagar el proceso las habría congelado y el traspaso caería en el sitio
## equivocado.
@export var disable_3d_while_playing: bool = false

## El `.ogv` pre-renderizado. Vacío o inexistente = este nodo se retira.
@export_file("*.ogv") var video_path: String = ""

## El AnimationPlayer cuya posición es la verdad para la sincronía. En Safety
## Lullaby es `Timeline` con la animación `play`.
@export var clock: AnimationPlayer

## Posición del reloj en la que se sitúa el frame 0 del vídeo.
@export var starts_at: float = 0.0

## Posición del reloj en la que se devuelve el mando a la escena viva. 0 = usar
## la duración del propio vídeo.
@export var ends_at: float = 0.0

## Deriva tolerada antes de corregir con un seek.
##
## Un seek de Theora no es barato: `VideoStreamPlaybackTheora::seek()` retrocede
## por el fichero en bloques de 512 KB buscando el keyframe anterior y luego
## decodifica hacia adelante hasta el destino. Corregir por frame sería peor que
## la deriva. En la práctica no debería hacer falta casi nunca: el reproductor
## avanza con el mismo `delta` de reloj de pared que el audio de la canción, así
## que los dos derivan juntos.
@export var max_drift: float = 0.25

## Cuanto hay que esperar entre dos correcciones, pase lo que pase.
##
## El techo que faltaba, y lo que costo descubrirlo: bajar `max_drift` de 0.25 a
## 0.05 para curar una desincronia audible metio un bucle. Un seek cuesta, el
## seek alarga el fotograma, el fotograma largo genera mas deriva, la deriva
## dispara otro seek. La region del componente en el log del dispositivo llego a
##
##     PhotoshootVideo=23.31/11.52
##
## 23.31 ms de MEDIA sobre 927 fotogramas, cuando decodificar 960x540 son ~3.1ms
## por la formula medida en este mismo fichero. Siete veces el coste, y el
## docstring de `max_drift` ya avisaba de que corregir por fotograma seria peor
## que la deriva.
##
## Con un techo el bucle no puede cerrarse: por muy mal que vaya el fotograma,
## no se paga mas de un seek por segundo. La deriva entre correcciones se ve;
## el bucle se nota mucho mas.
@export var min_seek_interval: float = 1.0

## En qué capa se dibuja el vídeo. Tiene que quedar por encima de la cutscene y
## por debajo del HUD.
##
## Que la capa 0 baste está MEDIDO, no supuesto - fue el único riesgo que quedó
## abierto al cablear esto. Un ColorRect rojo en el lienzo por defecto con
## `z_index = 1`, contra otro verde dentro de un CanvasLayer(0), leyendo el
## píxel del medio:
##
##     CanvasLayer(0) vs Node2D z_index=1  ->  gana el CanvasLayer
##
## O sea que un CanvasLayer gana al lienzo por defecto aunque el z_index del
## otro sea mayor, porque el z_index solo ordena DENTRO de un lienzo. Por eso el
## vídeo en capa 0 tapa la cutscene, y por eso `UILayer` en capa 1 sigue por
## encima del vídeo.
##
## La otra cara: cualquier cosa del lienzo por defecto queda tapada, tenga el
## z_index que tenga. En Chimera, `Prelude` es un Node2D con `z_index = 1` que
## lleva el texto traducible de la tarjeta de fotos - el vídeo lo taparía, y
## marcarlo en `cutscene_live_overlay` lo dejaría invisible en los dos lados.
## Ese texto tiene que subir a un CanvasLayer antes de que Chimera pueda ir a
## vídeo.
@export var canvas_layer: int = 0

var _player: VideoStreamPlayer = null
var _layer: CanvasLayer = null
var _live_mode: int = Node.PROCESS_MODE_INHERIT

## El `visible` que traia la cutscene viva al abrir el video, para devolverselo.
## Ver `_open()` y `_hand_back()`.
var _live_visible: bool = true
var _handed_back: bool = false
var _seen_playing: bool = false
var _seeks: int = 0

## Posicion del reloj en la ultima correccion. Negativo = ninguna todavia.
var _last_seek_at: float = -1.0

## Si la ventana ya se abrió. Hasta entonces el reproductor existe pero ni se ve
## ni suena.
var _opened: bool = false

## El `disable_3d` que traía el viewport, para devolverlo tal cual.
var _was_3d_disabled: bool = false


func _ready() -> void:
	set_process(false)

	if not _wanted():
		return

	if video_path.is_empty() or not ResourceLoader.exists(video_path):
		# Sin fichero no hay nada que hacer, y hay que retirarse, no fallar: el
		# .ogv lo produce CI y un checkout de desarrollo no lo trae.
		return

	var stream: VideoStream = load(video_path) as VideoStream
	if stream == null:
		push_warning("LullabyCutsceneVideo: '%s' no es un VideoStream" % video_path)
		return

	if clock == null:
		push_warning("LullabyCutsceneVideo: falta clock, no se sustituye")
		return

	_layer = CanvasLayer.new()
	_layer.layer = canvas_layer
	add_child(_layer)

	_player = VideoStreamPlayer.new()
	_player.stream = stream
	_player.expand = true
	_layer.add_child(_player)

	# El preset DESPUÉS de entrar al árbol, y con
	# set_anchors_and_offsets_preset() en vez de escribir `anchors_preset`.
	#
	# Medido, porque la primera versión lo hacía al revés y el resultado fue una
	# pantalla gris en el teléfono: escribir `anchors_preset` sobre un Control
	# que todavía no tiene padre deja `size = (0, 0)` - fija las anclas pero no
	# tiene contra qué resolver los offsets. El reproductor existía, reproducía
	# y no dibujaba un solo píxel, y lo único que se veía era la cutscene
	# congelada detrás, porque a esa ya se le había apagado el process_mode.
	#
	#     anclas antes de add_child   -> size=(0, 0)
	#     preset dentro del árbol     -> size=(1920, 1080)
	_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Montado pero CERRADO. La primera versión llamaba a play() aquí mismo, y con
	# `starts_at = 0.0` -la prelude, el único caso que había- eso era correcto.
	#
	# Con la sesión de fotos de Chimera deja de serlo: su frame 0 cae en 53.7s, y
	# un reproductor que arranca en `_ready()` dibuja su primer fotograma sobre la
	# prelude y sobre el intro, cincuenta y tres segundos antes de que le toque.
	# La ventana la abre `_process()` cuando el reloj llega.
	_layer.visible = false
	set_process(true)


## Si el preset pide vídeo. Ausente el singleton (bancos, pruebas), no.
##
## Salvo que no haya a qué volver. Cuando `live_cutscene` está vacío la escena
## viva ya no existe -se retiró del árbol- y el vídeo no es una preferencia de
## calidad, es la cutscene. Dejar que el preset lo apagase ahí no daría la
## versión bonita, daría treinta segundos de pantalla vacía.
func _wanted() -> bool:
	if live_cutscene == null and not live_fallback_exists:
		return true

	var settings: Object = Engine.get_singleton(&"Settings") if Engine.has_singleton(&"Settings") else null
	if settings == null:
		settings = get_node_or_null(^"/root/Settings")
	if settings == null:
		return false
	return bool(settings.get("graphics_prefer_cutscene_video"))


func _process(_delta: float) -> void:
	if _player == null or _handed_back:
		return

	# Sin animacion en curso no hay posicion que leer, y preguntarla igualmente
	# es un error rojo por fotograma: `current_animation_position` llama a
	# get_current_animation_position(), que exige un playback activo. Pasa de
	# verdad y no solo en un banco - `_ready()` enciende el proceso en el mismo
	# fotograma en que la escena entra al arbol, antes de que nadie haya llamado
	# a play() sobre el reloj. Se veia en la salida de test_cutscene_video.gd
	# desde antes de esto; con el arte fuera y el video como unica capa, valia la
	# pena dejar de ensuciar el log.
	if clock.current_animation.is_empty():
		return

	var here: float = clock.current_animation_position
	var finish: float = ends_at
	if finish <= 0.0:
		finish = starts_at + _player.get_stream_length()

	# Pasado el final se devuelve el mando aunque nunca se llegara a abrir. Pasa
	# cuando alguien sitúa el reloj más allá de la ventana - el harness lo hace
	# con `desde=`, y una repetición tras morir podría hacerlo también.
	if here >= finish:
		_hand_back()
		return

	if not _opened:
		if here < starts_at:
			return
		_open(here)

	# El reloj manda. `is_playing()` es solo la red por si el vídeo se acaba
	# antes de tiempo, y solo cuenta DESPUÉS de haberlo visto reproducir: en un
	# servidor de vídeo que no decodifica (headless, un banco) arranca en false
	# y sin este cerrojo el nodo devolvería el mando en el primer frame.
	if _player.is_playing():
		_seen_playing = true
	if _seen_playing and not _player.is_playing():
		_hand_back()
		return

	var want: float = here - starts_at
	if want < 0.0:
		return
	if absf(_player.stream_position - want) > max_drift and _seek_allowed():
		_seeks += 1
		_last_seek_at = here
		_player.stream_position = want


## Si ha pasado bastante desde la ultima correccion.
##
## Se mide con el RELOJ de la cancion y no con el de pared: es el mismo que
## decide la deriva, y usar dos relojes distintos para decidir y para frenar es
## como se cuelan los bucles.
func _seek_allowed() -> bool:
	if _last_seek_at < 0.0:
		return true
	return absf(clock.current_animation_position - _last_seek_at) >= min_seek_interval


## Abre la ventana: muestra el vídeo, lo sitúa y calla lo que tape.
##
## Se sitúa con `stream_position` en vez de arrancar en cero porque el reloj
## puede llegar ya empezado - el primer fotograma en que `here >= starts_at`
## puede caer perfectamente a mitad de la ventana si la escena se montó con el
## reloj adelantado.
func _open(here: float) -> void:
	_opened = true
	_layer.visible = true
	_player.play()

	var want: float = here - starts_at
	if want > 0.0:
		_player.stream_position = want

	if live_cutscene != null:
		_live_mode = live_cutscene.process_mode
		live_cutscene.process_mode = Node.PROCESS_MODE_DISABLED

		# Y que ademas deje de DIBUJARSE, que es otra cosa. `process_mode` para
		# los `_process`; un CanvasItem apagado sigue rasterizando igual.
		#
		# Chimera lo tenia medido en cada censo del log 10226-4fe0a6db mientras
		# sonaba el prelude:
		#
		#     over=2.1x  relleno=[PreludeVideo/...VideoStreamPlayer@1.00x,
		#                         Intro/ColorRect2@1.00x, ...]
		#
		# `Intro/ColorRect2` es un ColorRect de 1957x1103 - pantalla entera y de
		# sobra - negro OPACO y con un ShaderMaterial encima. O sea una pasada de
		# shader a pantalla completa, cada fotograma, debajo de un video que la
		# tapa por completo. Duplicaba el overdraw del tramo el solo.
		var canvas := live_cutscene as CanvasItem
		if canvas != null:
			_live_visible = canvas.visible
			canvas.visible = false

	if disable_3d_while_playing:
		var vp: Viewport = get_viewport()
		if vp != null:
			_was_3d_disabled = vp.disable_3d
			vp.disable_3d = true


## Devuelve el mando a la escena viva y se apaga.
##
## Restaura el `process_mode` que la escena traía en vez de fijar INHERIT: si
## alguien authorea la cutscene con un modo propio, sobrevive.
##
## `is_instance_valid` y no `!= null`, y la diferencia no es teórica. Una
## cutscene puede liberarse a sí misma antes de que el vídeo termine: en
## Chimera la pista de método de `103_stroll` llama a `Intro.queue_free()` en
## el segundo 34.583, y el vídeo devuelve el mando en 34.708 - 125
## milisegundos después. Un `Node` liberado NO deja la variable a null, deja
## una referencia colgante que pasa el `!= null` y revienta al tocarle una
## propiedad con "Attempt to call function on previously freed instance".
##
## Que la cutscene desaparezca sola es un final legítimo, no un error: si ya no
## está, no hay `process_mode` que restaurar y no hay nada que hacer.
func _hand_back() -> void:
	_handed_back = true
	set_process(false)

	# Solo si la ventana llegó a abrirse. Por el camino de "el reloj ya iba
	# pasado" no se apagó nada, y escribir `false` a ciegas le pisaría el ajuste
	# a quien lo tuviera puesto por su cuenta.
	if _opened and disable_3d_while_playing:
		var vp: Viewport = get_viewport()
		if vp != null:
			vp.disable_3d = _was_3d_disabled

	# Tambien solo si se abrio, y por lo mismo: `_live_mode` se captura en
	# `_open()`, asi que por el camino de "el reloj ya iba pasado" todavia vale
	# INHERIT y restaurarlo le pisaria a la cutscene su modo authoreado. Lo
	# encontro test_cutscene_video.gd, que monta el arbol de verdad; leyendo el
	# codigo no se veia.
	if _opened and is_instance_valid(live_cutscene):
		live_cutscene.process_mode = _live_mode

		# El `visible` se devuelve SOLO si nadie lo ha tocado mientras tanto.
		#
		# `Intro:visible` lo escriben pistas de `101_prelude`, `102_intro`,
		# `103_stroll` y `RESET`. Hoy ninguna resuelve - el log las lleva como
		# `couldn't resolve track: '../Intro:visible'` - pero si alguna vuelve a
		# hacerlo y enciende la cutscene a mitad de ventana, reponer aqui el valor
		# de `_open()` la apagaria contra lo que la pista pidio.
		#
		# Comprobando que sigue en `false` el fallo se degrada en vez de corromper:
		# si otro escribio, se respeta y este apaño simplemente deja de aplicarse.
		# Es el mismo criterio de `_restore_forced_lights()` en
		# lullaby_preload_camera.gd, y por la misma razon.
		var canvas := live_cutscene as CanvasItem
		if canvas != null and not canvas.visible:
			canvas.visible = _live_visible

	if _player != null:
		_player.stop()
	if _layer != null:
		_layer.queue_free()
		_layer = null
		_player = null


## Para los diagnósticos: cuántas correcciones de deriva hicieron falta.
func drift_corrections() -> int:
	return _seeks
