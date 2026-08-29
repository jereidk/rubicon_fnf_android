class_name LullabyIntroSkipModule
extends Node


@export var start_player: AnimationPlayer
@export var skips: Dictionary[Node, float] = {}


func _ready() -> void :
	if not LullabyGameoverModule.has_died or skips.is_empty():
		return

	if is_instance_valid(start_player):
		start_player.play(&"start")

	await RenderingServer.frame_pre_draw

	for player in skips:
		player.play()

		if player is AnimationPlayer:
			player.seek(skips[player], true)
			_dispatch_clips_at(player, skips[player])
		else:
			player.seek(skips[player])


## Vuelve a poner en marcha los sub-clips que el salto deja congelados.
##
## Esto es lo que se rompe, y esta en el motor, no aqui. `AnimationMixer`
## procesa las pistas TYPE_ANIMATION -las que arrancan OTRO AnimationPlayer
## desde la linea de tiempo- asi (animation_mixer.cpp, 4.7.1):
##
##     if (player2->is_playing() || !is_external_seeking) {
##         player2->play(anim_name);
##         ...
##     } else {
##         player2->set_assigned_animation(anim_name);
##         player2->seek(at_anim_pos, true);
##     }
##
## `seek(x, true)` ES un external seek. Asi que en la rama de abajo el sub-clip
## recibe su nombre y su posicion y NO recibe un play: se queda quieto en ese
## fotograma para siempre. Solo se salva el que ya estuviera sonando.
##
## Y este modulo hace justo eso: `seek(19.3, true)` sobre la linea de tiempo de
## Chimera. Todo sub-clip que a los 19.3s deberia llevar rato corriendo entra
## congelado. No es una teoria sobre el motor, es la misma rama que ya obligo a
## despachar los clips a mano en el render de cutscenes
## (tools/harness/render_cutscene.gd) para que la captura no saliera con los
## personajes clavados.
##
## Corre en el retry despues de morir, que es la unica vez que este modulo hace
## algo - de ahi que se reportara como "las animaciones de Chimera fallan" y no
## como "Chimera esta rota": en la primera pasada no salta ningun intro.
##
## `FIND_MODE_NEAREST` devuelve la llave EN o ANTES del tiempo pedido, que es el
## clip vigente, y no la mas cercana en valor absoluto. Comprobado contra este
## mismo motor con llaves en 0/5/12/25/40: pedir 4.9 da la de 0.0, no la de 5.0.
## `limit` no cambia nada en esa consulta, asi que no se le da ningun papel.
##
## Lo que esto NO hace, dicho para que nadie lo descubra a base de un reporte:
## los efectos PERMANENTES de los clips anteriores siguen sin ocurrir. Si un
## clip anterior al punto de salto liberaba un nodo o movia algo de sitio, ese
## nodo sigue donde estaba. Esto arregla la capa de animacion, no reescribe lo
## que paso antes del salto.
func _dispatch_clips_at(host: AnimationPlayer, at: float) -> void:
	var anim: Animation = host.get_animation(host.current_animation)
	if anim == null:
		return

	var root: Node = host.get_node_or_null(host.root_node)
	if root == null:
		return

	for i: int in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ANIMATION:
			continue

		var sub := root.get_node_or_null(anim.track_get_path(i)) as AnimationPlayer
		if sub == null:
			continue

		var idx: int = anim.track_find_key(i, at, Animation.FIND_MODE_NEAREST)
		if idx < 0:
			continue

		var clip: StringName = anim.animation_track_get_key_animation(i, idx)
		if clip == &"[stop]" or not sub.has_animation(clip):
			continue

		# El que ya va bien se deja en paz. Cuando el motor toma su rama buena
		# -porque el sub-clip ya estaba sonando- volver a llamar a play() lo
		# reiniciaria desde cero, que seria cambiar un clip congelado por uno
		# adelantado. Solo se rescata al que quedo parado.
		if sub.is_playing() and sub.current_animation == clip:
			continue

		var started_at: float = anim.track_get_key_time(i, idx)
		sub.play(clip)
		sub.seek(at - started_at, true)
