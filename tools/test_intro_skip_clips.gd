extends SceneTree

## Saltarse el intro tras morir no puede dejar las animaciones congeladas.
##
## Reportado de Chimera: "las animaciones fallan". Solo ocurre en el REINTENTO,
## porque LullabyIntroSkipModule solo hace algo si LullabyGameoverModule.has_died
## - de ahi que se leyera como un fallo intermitente y no como una cancion rota.
##
## La causa esta en el motor. AnimationMixer procesa las pistas TYPE_ANIMATION
## -las que arrancan otro AnimationPlayer desde la linea de tiempo- asi
## (animation_mixer.cpp, 4.7.1):
##
##     if (player2->is_playing() || !is_external_seeking) {
##         player2->play(anim_name);
##     } else {
##         player2->set_assigned_animation(anim_name);
##         player2->seek(at_anim_pos, true);
##     }
##
## `seek(x, true)` es un external seek, asi que la rama de abajo le da al
## sub-clip su nombre y su posicion y NO le da un play. Se queda quieto. Y el
## modulo de salto hace exactamente eso: seek(19.3, true) sobre la linea de
## tiempo de Chimera.
##
## Esto no lo comprueba leyendo el fuente: lo REPRODUCE. Monta un
## AnimationPlayer anfitrion con una pista TYPE_ANIMATION apuntando a otro,
## hace el mismo salto externo, y comprueba primero que el motor deja el
## sub-clip parado - que es el control negativo, sin el esta guarda pasaria en
## verde contra un motor arreglado y contra el modulo borrado por igual - y
## despues que _dispatch_clips_at() lo vuelve a poner en marcha en la posicion
## correcta.
##
## Run with:
##   godot --headless --path . --script tools/test_intro_skip_clips.gd

const MODULE := "res://lullaby_mod/scripts/lullaby/intro_skip_module.gd"

## Donde arranca el sub-clip en la linea de tiempo, y a donde salta el intro.
## La diferencia -8 segundos- es lo que el sub-clip tiene que llevar corrido
## cuando lo rescatemos: si se rescatara desde cero se veria el personaje
## empezando su animacion en mitad de la cancion, que es el otro fallo posible.
const CLIP_AT := 2.0
const SKIP_TO := 10.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host_root := Node.new()
	host_root.name = "SkipRig"
	root.add_child(host_root)

	var sub := AnimationPlayer.new()
	sub.name = "Sub"
	host_root.add_child(sub)
	sub.add_animation_library(&"", _sub_library())

	var host := AnimationPlayer.new()
	host.name = "Host"
	host_root.add_child(host)
	host.add_animation_library(&"", _host_library())

	# El salto, tal cual lo hace el modulo.
	host.play(&"timeline")
	host.seek(SKIP_TO, true)

	# Control negativo: sin esto, la guarda no distingue un arreglo de un motor
	# que nunca tuvo el problema.
	_check(sub.assigned_animation == "spin",
		"el motor SI le asigna el clip al sub-player (%s)" % sub.assigned_animation)
	var frozen: bool = not sub.is_playing()
	_check(frozen,
		"...y NO lo pone a sonar: queda congelado (is_playing=%s)" % sub.is_playing())

	# Y el rescate.
	var module: Node = load(MODULE).new()
	module.call("_dispatch_clips_at", host, SKIP_TO)

	_check(sub.is_playing(), "_dispatch_clips_at lo vuelve a poner en marcha")
	_check(sub.current_animation == "spin",
		"...con el clip que tocaba (%s)" % sub.current_animation)

	var want: float = SKIP_TO - CLIP_AT
	var got: float = sub.current_animation_position
	_check(absf(got - want) < 0.05,
		"...y en su posicion, no desde cero (%.2fs, se esperaba %.2fs)" % [got, want])

	# Idempotente: un segundo pase no puede reiniciar lo que ya va bien, o
	# rescatar dos veces seria peor que no rescatar.
	module.call("_dispatch_clips_at", host, SKIP_TO)
	_check(absf(sub.current_animation_position - want) < 0.05,
		"un segundo pase no lo reinicia (%.2fs)" % sub.current_animation_position)

	module.free()
	host_root.queue_free()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## Un clip cualquiera con duracion suficiente para que SKIP_TO caiga dentro.
func _sub_library() -> AnimationLibrary:
	var spin := Animation.new()
	spin.length = 30.0
	var track: int = spin.add_track(Animation.TYPE_VALUE)
	spin.track_set_path(track, NodePath(".:speed_scale"))
	spin.track_insert_key(track, 0.0, 1.0)
	spin.track_insert_key(track, 30.0, 1.0)

	var lib := AnimationLibrary.new()
	lib.add_animation(&"spin", spin)
	return lib


## La linea de tiempo de la cancion, reducida a lo unico que importa aqui: una
## pista TYPE_ANIMATION que arranca el sub-clip antes del punto de salto.
func _host_library() -> AnimationLibrary:
	var timeline := Animation.new()
	timeline.length = 100.0
	var track: int = timeline.add_track(Animation.TYPE_ANIMATION)
	timeline.track_set_path(track, NodePath("Sub"))
	timeline.animation_track_insert_key(track, CLIP_AT, &"spin")

	var lib := AnimationLibrary.new()
	lib.add_animation(&"timeline", timeline)
	return lib


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
