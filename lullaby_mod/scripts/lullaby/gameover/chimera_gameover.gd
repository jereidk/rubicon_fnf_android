extends Control


@export var anim_player: AnimationPlayer
@export var sound_player: AudioStreamPlayer

## El vídeo de la muerte, en los steps que lo llevan.
##
## Los steps 1-3 tenían su animación como un AnimatedSprite2D de 13 fotogramas
## repartidos en tres hojas de 4096x4096, que costaban 75 MB de PNG en el
## repositorio y 27 MB de ASTC en el dispositivo - por dos segundos y medio de
## animación que nunca cambia y que nadie puede tocar. Ahora son tres .ogv de
## medio mega, y de paso salen del pipeline ASTC, que es lo que hizo que un
## import de CI tardara 12m29s.
##
## Arranca en _on_timer_timeout(), en la MISMA llamada que la animación, y esa
## es toda la sincronización que hay: no queda ningún tiempo de arranque escrito
## ni en la escena ni aquí. Para que eso sea posible el clip lleva su propio
## negro de cabecera y de cola, y ese negro cuesta 30 KB.
##
## Lo que el vídeo NO lleva es la tarjeta de texto de los primeros seis
## segundos. Sigue siendo un PNG dibujado encima, por dos motivos: texto serif
## fino blanco sobre negro es lo peor que se le puede dar a un códec -a 960x540
## se le ven los bordes destellar- y además es estática, así que meterla dentro
## la empeoraba y se llevaba dos tercios del bitrate del clip.
@export var video_player: VideoStreamPlayer


## Terminada la secuencia de muerte, Chimera vuelve a empezar. Desde 0.
##
## `has_died` es lo único que hace algo a LullabyIntroSkipModule: con la bandera
## puesta, el módulo salta el reloj de la canción a un punto más adelante en
## cuanto la escena carga. Chimera lo tenía en 19.3s, así que morir y reintentar
## se saltaba el preludio - y esta secuencia de muerte existe precisamente para
## devolverte al principio, no a la mitad.
##
## Se limpia AQUÍ además de haber quitado el nodo de la canción porque la
## bandera es GLOBAL: dejarla puesta al salir de Chimera hace que la siguiente
## canción que se juegue se salte SU intro sin que nadie haya muerto en ella.
##
## `deaths` NO se toca: es estática a propósito, y es lo que hace que la
## siguiente muerte enseñe el step siguiente.
##
## Y la vuelta va por SceneChanger, no por change_scene_to_file().
##
## El log del dispositivo (10229-33620adb) mide la asimetría sin lugar a dudas:
## entrar al gameover cuesta 371ms y volver de él cuesta 11.843ms, clavados, con
## la VRAM subiendo +184MB antes de bajar. Solo la vuelta pasaba por la ruta
## cruda, y `change_scene_to_file()` destruye la escena vieja y carga la nueva a
## la vez - exactamente el solape que SceneChanger existe para evitar, y cuyo
## arreglo allí bajó este mismo parón de 9-11s a 4s.
##
## Dentro de esos 11.8 segundos el motor crea 123 pipelines y **100 fallan**:
##
##     ERROR Couldn't create Vulkan graphics pipelines (VkResult error -13). (x100)
##           rendering_device_driver_vulkan.cpp:6237 render_pipeline_create
##
## Una pipeline que falla cuesta el intento, no se guarda en ninguna caché y se
## vuelve a intentar la siguiente vez. Por eso morir y reintentar paga el precio
## entero cada vez, y por eso la tienda llegó a costar más en su segunda carga
## que en la primera.
##
## `end_manually = true` no es opcional, y es la mitad menos obvia del arreglo:
## lullaby_preload_camera.gd arranca con `if !SceneChanger.awaiting_manual_end:
## finish_preload(); return`, así que con false se salta el precache ENTERO. La
## vuelta tras morir entraba a Chimera sin precalentar una sola pipeline, que es
## la otra razón de que fallaran cien. Es el mismo tercer parámetro que
## lullaby_debug_menu.gd pasa para esta canción y solo para esta.
func _on_gameover_finished() -> void :
	LullabyGameoverModule.has_died = false
	SceneChanger.change_to("uid://k26b7med2dat", &"hypno", true)


func _on_animation_player_animation_finished(_anim_name: StringName) -> void :
	_on_gameover_finished()


func _on_timer_timeout() -> void :
	# Fuera del árbol no se reproduce nada.
	#
	# `_on_gameover_finished()` justo arriba hace `change_scene_to_file()`, que
	# retira esta escena; un `timeout` que ya estaba encolado llega después, con
	# el nodo ya fuera del árbol, y el motor lo rechaza en rojo. Del .error del
	# dispositivo (10226-4fe0a6db), a los 311.76s - cuatro décimas antes del
	# desmontaje que el log mide como `vram_delta=-168.0MB`:
	#
	#     ERROR Playback can only happen when a node is inside the scene tree
	#           audio_stream_player_internal.cpp:145 play_basic
	#
	# Salir aquí no cambia nada cuando la escena sí está montada: es exactamente
	# el caso que el motor ya rechazaba, solo que sin el error.
	if not is_inside_tree():
		return

	# Antes que la animación y sin await por medio, para que los dos arranquen
	# en el mismo fotograma. Es la única sincronización que existe entre el
	# vídeo y la escena.
	if video_player:
		video_player.play()

	if anim_player:
		anim_player.play(&"animation")
	elif sound_player:
		sound_player.play()
