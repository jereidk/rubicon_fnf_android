@tool
class_name LullabyLevelSong
extends RubiconLevelSong


var start_timer: Timer


func added_player_child(node: Node) -> void :
	if node is not AudioStreamPlayer or audio_players.has(node):
		return

	audio_players.append(node)


func removed_player_child(node: Node) -> void :
	if node is not AudioStreamPlayer or not audio_players.has(node):
		return

	audio_players.erase(node)


func start_playing() -> void :
	playing = true
	for player: AudioStreamPlayer in audio_players:
		var start_time: float = _level.clock.animation_player.current_animation_position + offset
		if start_time < 0:
			if not is_instance_valid(start_timer):
				start_timer = Timer.new()
				start_timer.wait_time = abs(start_time)
				start_timer.one_shot = true
				add_child(start_timer)

				start_timer.start()
				start_timer.timeout.connect(start_playing)
			return
		player.play(start_time)
		# El arbol pausado congela el reloj, pero NO congela un reproductor que
		# arranca YA pausado.
		#
		# `NOTIFICATION_PAUSED` solo llega en la TRANSICION a pausa. Un
		# AudioStreamPlayer al que se le llama `play()` cuando el arbol ya estaba
		# pausado nunca la recibe, asi que suena - mientras el AnimationPlayer
		# del reloj, que si esta pausado, se queda en 0.
		#
		# Es exactamente lo que se reporto al entrar a Chimera: "se reproduce la
		# cancion pero el Sprite de pantalla [de carga] sigue ahi y no se ve nada
		# de Chimera". El log del dispositivo lo mide, en las tres primeras
		# resincronizaciones de la partida:
		#
		#   [166.51s] audio resync +3006ms at 0.00s
		#   [166.61s] audio resync +2848ms at 0.16s
		#   [168.04s] audio resync +1445ms at 1.57s
		#
		#   166.51 + 3.006 = 169.52    166.61 + 2.848 = 169.46
		#   168.04 + 1.445 = 169.49
		#
		# La referencia de audio esta CLAVADA en 3,01s mientras el reloj va por
		# 0,00: tres segundos de cancion sonaron con la pantalla de carga puesta,
		# y el reloj los perdio. La camara de precarga tiene el arbol pausado
		# durante todo su barrido - 39 segundos en Chimera -, asi que la ventana
		# en la que esto puede pasar es enorme, no es un caso raro.
		#
		# `stream_paused` y no `stop()`: el motor lo limpia solo en
		# `NOTIFICATION_UNPAUSED`, que llega en el mismo `paused = false` que
		# arranca el reloj. Asi el audio reanuda donde se quedo - sincronizado -
		# en vez de arrancar tarde y pedir un seek.
		#
		# Con el arbol sin pausar esto escribe `false` sobre `false`.
		player.stream_paused = get_tree().paused
