class_name LullabyCutsceneVideo
extends Node

## Sustituye una cutscene viva por un vídeo pre-renderizado en los presets bajos.
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
## Lo que este nodo NO hace, y por qué
## -----------------------------------
## No toca `visible` de la cutscene. El Timeline de la canción anima
## `../IntroCutscene:visible` con una pista, y una escritura nuestra sobre la
## misma propiedad pelearía con ella - es la trampa que `settings.gd` ya
## documenta para las Light2D. El vídeo se pone ENCIMA en su propio CanvasLayer
## y a la cutscene se le apaga el `process_mode`, que es lo que de verdad
## importa: el gasto son los 57 AnimationPlayer y los 15 AnimationTree, no los
## cinco draw calls. Queda el relleno de la cutscene tapada (0.6 pantallas)
## como desperdicio consciente; el premio son los picos de 50-86ms.
##
## Se retira en silencio si no hay vídeo. El `.ogv` lo produce CI, así que un
## checkout de desarrollo no lo tiene y la canción tiene que funcionar igual -
## mismo criterio que `trance_shaders.gd` cuando el preset le quita el material.

## El nodo de la cutscene viva cuyo procesamiento se apaga mientras corre el
## vídeo. Su `visible` no se toca (ver arriba).
@export var live_cutscene: Node

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

## En qué capa se dibuja el vídeo. Tiene que quedar por encima de la cutscene y
## por debajo del HUD.
@export var canvas_layer: int = 0

var _player: VideoStreamPlayer = null
var _layer: CanvasLayer = null
var _live_mode: int = Node.PROCESS_MODE_INHERIT
var _handed_back: bool = false
var _seen_playing: bool = false
var _seeks: int = 0


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

	if clock == null or live_cutscene == null:
		push_warning("LullabyCutsceneVideo: falta clock o live_cutscene, no se sustituye")
		return

	_layer = CanvasLayer.new()
	_layer.layer = canvas_layer
	add_child(_layer)

	_player = VideoStreamPlayer.new()
	_player.stream = stream
	_player.expand = true
	_player.anchors_preset = Control.PRESET_FULL_RECT
	_layer.add_child(_player)

	_live_mode = live_cutscene.process_mode
	live_cutscene.process_mode = Node.PROCESS_MODE_DISABLED

	_player.play()
	set_process(true)


## Si el preset pide vídeo. Ausente el singleton (bancos, pruebas), no.
func _wanted() -> bool:
	var settings: Object = Engine.get_singleton(&"Settings") if Engine.has_singleton(&"Settings") else null
	if settings == null:
		settings = get_node_or_null(^"/root/Settings")
	if settings == null:
		return false
	return bool(settings.get("graphics_prefer_cutscene_video"))


func _process(_delta: float) -> void:
	if _player == null or _handed_back:
		return

	var here: float = clock.current_animation_position
	var finish: float = ends_at
	if finish <= 0.0:
		finish = starts_at + _player.get_stream_length()

	# El reloj manda. `is_playing()` es solo la red por si el vídeo se acaba
	# antes de tiempo, y solo cuenta DESPUÉS de haberlo visto reproducir: en un
	# servidor de vídeo que no decodifica (headless, un banco) arranca en false
	# y sin este cerrojo el nodo devolvería el mando en el primer frame.
	if _player.is_playing():
		_seen_playing = true
	if here >= finish or (_seen_playing and not _player.is_playing()):
		_hand_back()
		return

	var want: float = here - starts_at
	if want < 0.0:
		return
	if absf(_player.stream_position - want) > max_drift:
		_seeks += 1
		_player.stream_position = want


## Devuelve el mando a la escena viva y se apaga.
##
## Restaura el `process_mode` que la escena traía en vez de fijar INHERIT: si
## alguien authorea la cutscene con un modo propio, sobrevive.
func _hand_back() -> void:
	_handed_back = true
	set_process(false)

	if live_cutscene != null:
		live_cutscene.process_mode = _live_mode

	if _player != null:
		_player.stop()
	if _layer != null:
		_layer.queue_free()
		_layer = null
		_player = null


## Para los diagnósticos: cuántas correcciones de deriva hicieron falta.
func drift_corrections() -> int:
	return _seeks
