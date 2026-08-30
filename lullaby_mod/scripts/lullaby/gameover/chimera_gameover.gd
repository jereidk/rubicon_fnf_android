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
func _on_gameover_finished() -> void :
	LullabyGameoverModule.has_died = false
	get_tree().change_scene_to_file("uid://k26b7med2dat")


func _on_animation_player_animation_finished(_anim_name: StringName) -> void :
	_on_gameover_finished()


func _on_timer_timeout() -> void :
	# Antes que la animación y sin await por medio, para que los dos arranquen
	# en el mismo fotograma. Es la única sincronización que existe entre el
	# vídeo y la escena.
	if video_player:
		video_player.play()

	if anim_player:
		anim_player.play(&"animation")
	elif sound_player:
		sound_player.play()
