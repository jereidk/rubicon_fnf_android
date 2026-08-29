@tool
extends Node
class_name RubiconLevelSong

enum SyncTime {
	STEP,
	BEAT,
	MEASURE,
}

@export var audio_players: Array[AudioStreamPlayer]:
	set(value):
		audio_players = value
		if sync_reference_player == null or !audio_players.has(sync_reference_player):
			if audio_players.is_empty():
				sync_reference_player = null
				return
			sync_reference_player = audio_players[0]
@export var offset:float = 0

@export_group("Syncing", "sync_")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var sync_enabled: bool = true

@export var sync_check_every: SyncTime = SyncTime.MEASURE:
	set(value):
		sync_check_every = value
		set_level()

@export var sync_reference_player: AudioStreamPlayer
@export var sync_desync_threshold: float = 0.045

var playing:bool = false

var _level:RubiconLevel:
	set(value):
		_level = value
		set_level()

func _ready() -> void:
	set_process_internal(true)
	connect(&"child_entered_tree", added_player_child)
	connect(&"child_exiting_tree", removed_player_child)

func set_level():
	if _level == null:
		return
	
	_level.clock.animation_player.connect(&"animation_started", func(_a:StringName):start_playing())
	_level.clock.animation_player.connect(&"animation_finished", func(_a:StringName):stop_playing())
	
	if !sync_enabled:
		return
	
	match sync_check_every:
		SyncTime.STEP:
			if _level.clock.beat_change.is_connected(check_for_desync):
				_level.clock.beat_change.disconnect(check_for_desync)
			
			if _level.clock.measure_change.is_connected(check_for_desync):
				_level.clock.measure_change.disconnect(check_for_desync)
			
			if !_level.clock.step_change.is_connected(check_for_desync):
				_level.clock.step_change.connect(check_for_desync)
		
		SyncTime.BEAT:
			if _level.clock.step_change.is_connected(check_for_desync):
				_level.clock.step_change.disconnect(check_for_desync)
			
			if _level.clock.measure_change.is_connected(check_for_desync):
				_level.clock.measure_change.disconnect(check_for_desync)
			
			if !_level.clock.beat_change.is_connected(check_for_desync):
				_level.clock.beat_change.connect(check_for_desync)
		
		SyncTime.MEASURE:
			if _level.clock.step_change.is_connected(check_for_desync):
				_level.clock.step_change.disconnect(check_for_desync)
			
			if _level.clock.beat_change.is_connected(check_for_desync):
				_level.clock.beat_change.disconnect(check_for_desync)
			
			if !_level.clock.measure_change.is_connected(check_for_desync):
				_level.clock.measure_change.connect(check_for_desync)

func start_playing() -> void:
	playing = true
	for player:AudioStreamPlayer in audio_players:
		var start_time:float = _level.clock.animation_player.current_animation_position + offset
		if start_time < 0:
			var timer:SceneTreeTimer = get_tree().create_timer(abs(start_time))
			timer.timeout.connect(start_playing)
			return
		player.play(start_time)

func stop_playing() -> void:
	playing = false
	for player:AudioStreamPlayer in audio_players:
		player.stop()

func added_player_child(_node: Node) -> void:
	if !(_node is AudioStreamPlayer) and audio_players.has(_node):
		return
	
	audio_players.append(_node)

func removed_player_child(_node: Node) -> void:
	if !audio_players.has(_node):
		return
	
	audio_players.remove_at(audio_players.find(_node))

## Donde esta de verdad el audio, y no donde `get_playback_position()` lo deja.
##
## `get_playback_position()` sola es la posicion del ULTIMO BLOQUE MEZCLADO, y
## eso no es la posicion del audio por dos motivos distintos que se suman:
##
##   se actualiza una vez por bloque de mezcla, asi que entre bloque y bloque
##   se queda quieta y se lee atrasada en cualquier cantidad de 0 a la duracion
##   del bloque - `get_time_since_last_mix()` es exactamente eso;
##
##   y lo que se ha mezclado todavia no ha sonado: pasa por el buffer de salida
##   antes de llegar al altavoz, asi que se lee adelantada en
##   `get_output_latency()`.
##
## Es la formula que documenta el propio Godot para sincronizar con musica, y
## aqui no estaba ninguna de las dos mitades. El error de lectura resultante no
## es un detalle: los dos terminos son del orden de decenas de milisegundos y
## `sync_desync_threshold` son 45, asi que el ruido de medicion entra y sale
## solo del umbral que decide si hay desincronizacion. Cada vez que entra,
## check_for_desync() cree ver una deriva que no existe y HACE UN SEEK de los
## tres reproductores a la vez - instrumental, voces y efectos - lo que si es
## un salto audible de verdad.
##
## En PC pasa desapercibido porque la latencia de salida es pequena y estable.
## En Android no lo es, y eso es lo que separa "en PC va bien" de lo que
## reportaron de Chimera: fallos de ambiente y notas desincronizadas A RATOS.
## A ratos es la firma de un umbral rozado, no la de una deriva real, que
## crecería en vez de ir y venir.
##
## Corregida, la comparacion mide deriva de verdad en vez de su propio error de
## lectura, asi que esto solo puede hacer MENOS seeks, nunca mas.
func _reference_time() -> float:
	var mixed: float = sync_reference_player.get_playback_position()
	return mixed + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()

func check_for_desync() -> void:
	if _level == null or sync_reference_player == null or !sync_enabled:
		return

	var anim_player_time:float = _level.clock.animation_player.current_animation_position + offset
	var drift: float = _reference_time() - anim_player_time
	if absf(drift) > sync_desync_threshold:
		_report_resync(drift)
		for player:AudioStreamPlayer in audio_players:
			if player.playing:
				player.seek(anim_player_time)

## Un seek de la cancion entera no puede seguir siendo invisible.
##
## La linea que habia aqui era un `print` comentado, asi que hasta ahora no
## habia forma de saber si esto disparaba nunca, cuanto, ni en que sitios de la
## cancion - y es justo el dato que decide si lo de arriba era todo el problema
## o solo la mitad. Queda registrado con el signo y la magnitud:
##
##   drift positivo  el audio va por delante del reloj de la animacion;
##   drift negativo  el reloj de la animacion va por delante del audio, que es
##                   lo que deja un frame largo cuando el delta que avanza al
##                   AnimationPlayer se come menos tiempo del que paso de
##                   verdad.
##
## Si el proximo log del dispositivo trae estas lineas con derivas de decenas
## de ms y signo alternante, quedaba ruido de medicion. Si trae derivas grandes
## y siempre del mismo signo, es deriva real y hay que decidir que reloj manda,
## que es una pregunta bastante mas cara que esta.
##
## Sin dependencia dura del autoload: esta escena se abre desde el editor a
## menudo y el addon no tiene por que saber nada del juego que lo usa.
func _report_resync(drift: float) -> void:
	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node == null or not log_node.has_method("mark"):
		return

	log_node.call("mark", "audio resync %+.0fms at %.2fs (umbral %.0fms)" % [
		drift * 1000.0,
		_level.clock.animation_player.current_animation_position,
		sync_desync_threshold * 1000.0,
	])

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_INTERNAL_PROCESS:
			if _level != null and (!_level.clock.animation_player.is_playing() and playing):
				stop_playing()
		
		NOTIFICATION_PARENTED:
			if _level != null:
				_level = null
			
			var parent: Node = get_parent()
			while parent != null:
				if parent is RubiconLevel:
					_level = parent
					break
				
				parent = parent.get_parent()
