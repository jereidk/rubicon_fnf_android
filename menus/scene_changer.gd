extends CanvasLayer

## Emitted around a scene load so the diagnostics log can record what
## was loaded, how long it took and what it cost in memory - the scene
## transitions are exactly where the game stutters worst on a phone.
signal scene_change_started(path: String)
signal scene_change_finished(path: String)


## Real port of Lullaby's LullabySceneChanger
## (lullaby_mod/scripts/lullaby/loading/lullaby_scene_changer.gd), using the
## same loading screen scenes/keys the rest of the ported code calls
## SceneChanger.change_to(path, &"hypno" or &"default") with.
##
## That file is the reference port and is NOT what runs: project.godot
## autoloads this one. Worth stating because the divergence has already cost
## something - `_blended_progress()` was written there, documented against
## device logs, guarded by tools/test_load_progress.gd, and never reached the
## game, which went on showing the raw engine fraction. The 2026-08-25 log
## shows what that looks like from the player's side:
##
##     STALL 49.1% for 4.0s,   19 deps arrived while stuck
##     STALL 49.7% for 4.0s,   32 deps arrived while stuck
##     STALL 50.0% for 19.6s, 284 deps arrived while stuck
##
## Twenty seconds of bar frozen at half while 284 dependencies land behind it.
## Both halves of that feature now live here, where they run.

@export var loading_screens: Dictionary = {
	&"default": preload("res://lullaby_mod/resources/loading/load_default.tscn"),
	&"hypno": preload("res://lullaby_mod/resources/loading/load_hypno.tscn"),
}

var _is_loading: bool = false
var _current_loader: LullabyLoadingScreen
var _watching_path: String

## True from the moment change_to() is entered until the loading screen has
## been taken back down again - which for end_manually callers is not until
## something calls finish_loading_screen().
##
## change_to() used to be re-entrant, and a second call while the first was
## still in flight overwrote _current_loader while the first loader was
## still parented here. This CanvasLayer is layer 128, so that orphan
## covered the whole game with nothing left holding a reference to free it:
## the scene loaded, the song played, and the player stared at a loading
## screen. It only takes two calls in one frame to do it, which is exactly
## what an unguarded _input() handler produces on Android, where
## emulate_mouse_from_touch turns one tap into a touch event AND a mouse
## event (monochrome_gameover.gd, fixed in the same commit).
##
## Guarding here as well as at the call site because every caller is one
## missing guard away from the same soft-lock, and a refused scene change
## is a far cheaper failure than an unkillable overlay.
var _change_in_flight: bool = false

var awaiting_manual_end: bool = false

## Si las dependencias de una escena pueden cargarse en paralelo.
##
## Es el tercer parametro de `load_threaded_request()` y su defecto es `false`.
## Ver la llamada, que lleva la evidencia del log.
##
## Constante y no `@export` a proposito: es un interruptor de riesgo, no un
## ajuste. Si aparece un cuelgue de carga se pone a `false` aqui y se vuelve al
## comportamiento por defecto de Godot en una linea.
const USE_SUB_THREADS := true

## Que parte de la barra se lleva la carga cuando quien llama se queda con la
## pantalla puesta (`end_manually`).
##
## Sin esto la barra MIENTE, y el log del dispositivo dice cuanto. Entrando a
## Chimera:
##
##   [ 79.36s] SCENE_OUT  (la pantalla de carga sube, la barra arranca)
##   [126.81s] SCENE_IN   took=47467ms   -> update_progress(1.0), barra LLENA
##   [166.47s] preload camera finished (38871ms, 267 nodos)
##   [~167.3s] la pantalla de carga baja
##
## Son CUARENTA segundos con la barra al 100%, a 1 fps (`fps_now=1`, fotogramas
## sueltos de 251ms y 1138ms), sin nada que se mueva en pantalla. Eso no se lee
## como "esta trabajando", se lee como colgado, y asi se reporto: "tiene la
## barra ya casi completa ... el Sprite de pantalla sigue ahi ... se queda
## congelado".
##
## Y no se puede arreglar animando algo: el AnimatedSprite2D de la pantalla de
## carga tambien esta a 1 fps. Lo unico que puede moverse de forma visible en
## esa ventana es la barra, porque es lo unico cuyo avance no depende de que el
## fotograma sea barato.
##
## La mitad y no otro reparto porque las dos fases son del mismo orden - 47s de
## carga contra 39s de precarga - y porque un reparto sacado de una medicion
## concreta envejece con cada cambio de escena. Es un LIMITE INFERIOR honesto,
## igual que `_blended_progress()`: la barra no promete cuanto falta, promete
## que algo sigue avanzando.
const MANUAL_LOAD_SHARE := 0.5

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not _is_loading:
		return

	var progress: Array = [0.0]
	var status: int = ResourceLoader.load_threaded_get_status(_watching_path, progress)
	# Ver MANUAL_LOAD_SHARE: con `end_manually` la carga no es el final de la
	# espera, asi que no puede quedarse con la barra entera.
	var share: float = MANUAL_LOAD_SHARE if awaiting_manual_end else 1.0
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_current_loader.update_progress(_blended_progress(progress[0]) * share)
		ResourceLoader.THREAD_LOAD_LOADED:
			_current_loader.update_progress(share)
			_complete()
		# Both failure branches release _change_in_flight. The loading screen
		# is deliberately left up - unload_current_scene() has already run,
		# so there is nothing behind it - but a failed load must not lock the
		# player out of every future scene change on top of the error.
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			printerr("Scene %s is invalid" % _watching_path)
			_is_loading = false
			_change_in_flight = false
			ErrorHandler.show_error("Attemped to load invalid resource\n%s" % _watching_path, ERR_INVALID_DATA)
		ResourceLoader.THREAD_LOAD_FAILED:
			printerr("Failed to load scene %s" % _watching_path)
			_is_loading = false
			_change_in_flight = false
			ErrorHandler.show_error("Failed to load resource.\n%s" % _watching_path, ERR_CANT_ACQUIRE_RESOURCE)

## The scene's direct dependencies, and the highest fraction reported so far.
var _direct_deps: PackedStringArray = PackedStringArray()
var _reported_progress: float = 0.0

## A progress figure that moves, from two measurements that are both true.
##
## load_threaded_get_status' fraction is nearly useless on the scenes that need
## a loading screen at all. Every stall in the device logs sits between 48.6%
## and 50.0%: the bar jumps to half in the first second and then holds still
## for twenty while 284 dependencies arrive behind it. The game is working the
## whole time; the number is not.
##
## So it is combined with a second one that does move: how many of the scene's
## direct dependencies are in the resource cache. Neither is the truth on its
## own - the engine's fraction is coarse, and direct dependencies are only the
## first level of a graph hundreds deep - but both are honest lower bounds on
## how far the load has got, so the larger of the two is a better lower bound
## than either.
##
## Monotonic, because the alternative is a bar that goes backwards: the
## dependency count is a ratio of a denominator taken once, and the engine's
## fraction is free to drop.
func _blended_progress(engine_fraction: float) -> float:
	var best: float = engine_fraction
	if not _direct_deps.is_empty():
		var cached: int = 0
		for dep in _direct_deps:
			if ResourceLoader.has_cached(dep):
				cached += 1
		best = maxf(best, float(cached) / float(_direct_deps.size()))
	_reported_progress = maxf(_reported_progress, clampf(best, 0.0, 1.0))
	return _reported_progress

## get_dependencies() returns "uid::type::path" for some entries and a bare
## path for others; has_cached() wants the path.
func _collect_direct_deps(path: String) -> void:
	_direct_deps = PackedStringArray()
	_reported_progress = 0.0
	for entry in ResourceLoader.get_dependencies(path):
		var parts: PackedStringArray = entry.split("::")
		var dep: String = parts[parts.size() - 1]
		if dep.begins_with("res://"):
			_direct_deps.append(dep)

func change_to(path: String, loading_screen: StringName = &"hypno", end_manually: bool = false) -> void:
	if _change_in_flight:
		push_warning("SceneChanger: ignoring change_to(%s), already changing to %s" % [
			path, _watching_path if not _watching_path.is_empty() else "(awaiting manual end)",
		])
		return

	_change_in_flight = true

	if not loading_screens.has(loading_screen):
		loading_screen = &"default"

	get_tree().paused = true
	get_window().gui_disable_input = true

	_watching_path = path
	scene_change_started.emit(path)
	# Belt and braces against the orphan described on _change_in_flight: a
	# loader from a previous change must never survive into this one.
	_free_loader()
	_current_loader = loading_screens[loading_screen].instantiate()
	add_child(_current_loader)

	await _current_loader.start()

	get_tree().unload_current_scene()

	# Y se le deja terminar ANTES de pedir la carga nueva.
	#
	# `unload_current_scene()` hace `queue_free`, que difiere la destruccion al
	# final del fotograma. Pedir la carga en la linea siguiente pone a destruir
	# la escena vieja y a cargar la nueva a la vez, peleandose por la misma cola
	# del servidor de render.
	#
	# Dos fotogramas y no uno: el primero corre los `queue_free` encolados, y el
	# segundo deja que el servidor de render procese las RID que esos frees le
	# dejaron. La pantalla de carga ya esta montada - `await _current_loader
	# .start()` esta justo arriba - asi que el jugador no ve ninguno de los dos.
	await get_tree().process_frame
	await get_tree().process_frame

	# Before the request, so the count is of what is cached from here on and
	# not of whatever the outgoing scene happened to leave behind.
	_collect_direct_deps(_watching_path)

	# `use_sub_threads = true`, el tercer parametro, que por defecto va en false:
	# las dependencias se resuelven EN SERIE, en un solo hilo del pool, en un
	# telefono de ocho nucleos.
	#
	# Entrando a Chimera en el log 10252-5c5c1817 eso son 47,5 segundos de los
	# que TREINTA Y DOS no mueven el contador ni una dependencia:
	#
	#   [ 94.00s] LOADING 50.0% at 14599ms deps=196/346 +props1.tres +foliage.png
	#   ... treinta y dos segundos identicos ...
	#   [125.16s] LOADING 50.0% at 45812ms deps=196/346
	#   [126.16s] LOADING 50.0% at 46814ms deps=297/346 +chimera_house.tscn
	#                                       +mdl_chimera_camera.gltf
	#
	# Ciento una dependencias en el ultimo segundo despues de media hora de
	# nada. Y el telefono no estaba trabajando: `fps_now=59-62`, `median=16.7ms`,
	# la RAM clavada en 120-125MB y la VRAM en 138MB durante los treinta y dos
	# segundos enteros. Un hilo serializando la casa de Chimera - 31,5MB de
	# `chimera0.bin` mas una treintena de texturas, tres de ellas de 4 a 5,5MB -
	# mientras los otros siete nucleos miran.
	#
	# El riesgo con nombre: con sub-hilos Godot puede llamar a un
	# ResourceFormatLoader propio desde varios hilos a la vez. El unico que hay
	# aqui es `RubiChartFileLoader`, y es stateless - ni un miembro, todo en
	# locales, un FileAccess por llamada -, cosa que
	# tools/test_threaded_load_parallel.gd comprueba. Si aparece un cuelgue de
	# carga, esta constante a `false` devuelve el comportamiento por defecto.
	ResourceLoader.load_threaded_request(_watching_path, "", USE_SUB_THREADS)
	_is_loading = true
	awaiting_manual_end = end_manually

## Cambia de escena con el motor, y NO con un montaje a mano.
##
## Hubo una version que instanciaba, asignaba `current_scene` y llamaba a
## `add_child()` por separado, para poder cronometrar las dos mitades del
## SPIKE de 10523ms de la tienda. Se envio, y la tienda salio NEGRA en el
## dispositivo. El log lo dijo en una linea:
##
##     ERROR Condition "p_scene && p_scene->get_parent() != root" is true.
##           scene_tree.cpp:1665 set_current_scene
##
## De `scene/main/scene_tree.cpp` del tag 4.7.1-stable:
##
##     void SceneTree::set_current_scene(Node *p_scene) {
##         ERR_FAIL_COND_MSG(!Thread::is_main_thread(), ...);
##         ERR_FAIL_COND(p_scene && p_scene->get_parent() != root);
##         current_scene = p_scene;
##     }
##
## `ERR_FAIL_COND` SALE SIN ASIGNAR. Escribir `current_scene` antes de que la
## escena cuelgue de root no da error de script ni excepcion: rechaza la
## asignacion en silencio y deja `current_scene` a null para siempre, con lo
## que todo lo que espera por el -el aplicador de luces, el de layout de notas,
## el de controles moviles- se rinde y no aplica nada.
##
## Y lo peor del asunto es que el orden era el correcto. `_flush_scene_change()`
## hace exactamente eso:
##
##     // Ensure correct state before `add_child` (might enqueue subsequent scene change).
##     current_scene = pending_new_scene;
##     root->add_child(pending_new_scene);
##
## pero asigna el MIEMBRO, saltandose el setter y su guarda. Desde GDScript solo
## existe el setter. Asi que un swap manual no puede comportarse como el del
## motor: o asigna antes y se lo rechazan, o asigna despues y entonces los
## `_ready()` de la escena nueva ven `current_scene` a null, que es una
## diferencia de comportamiento en CADA cambio de escena del juego.
##
## Por eso las dos mitades del SPIKE se quedan sin medir. Vale mas que medirlas.
func _complete() -> void:
	_is_loading = false

	get_window().gui_disable_input = false

	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(_watching_path)

	scene_change_finished.emit(_watching_path)
	_watching_path = ""
	get_tree().change_scene_to_packed(packed_scene)

	if not awaiting_manual_end:
		finish_loading_screen()

## Reload the running scene the way change_to() loads a new one - announced.
##
## `get_tree().reload_current_scene()` is the right mechanism for a retry: it
## keeps statics, it does not go through the loading screen, and it cannot
## race a second load. What it is not is *visible*. Five autoloads listen to
## `scene_change_finished` and none of them ever heard a retry, because that
## call bypasses this node entirely:
##
##   lullaby_mobile_controls_applier   the pendulum hitbox went back to the
##                                     top strip its scene authors, whatever
##                                     the Mechanic Hitbox Direction row said
##   lullaby_note_layout_applier       VSlice reverted to Classic
##   lullaby_light_budget_applier      no baked-light cull, no cheap shading,
##                                     and its caches still held the freed
##                                     scene's lights
##   lullaby_diagnostics_log           no SCENE_OUT/SCENE_IN for the retry
##
## Only the first was reported ("al reiniciar la hitbox de mecánica siempre
## va arriba"); the other three were the same bug going unnoticed. So the
## reload stays exactly as it was and only gains the announcement, in the
## same order `_complete()` uses - emit, then swap - because the appliers
## wait a frame afterwards to land on the new scene before it has drawn.
func reload_current() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	scene_change_finished.emit(scene.scene_file_path)
	get_tree().reload_current_scene()

## La segunda mitad de la barra, para quien se queda con la pantalla puesta.
##
## `fraction` es 0..1 DENTRO de esa fase, no de la barra: quien la llama sabe
## cuanto lleva de lo suyo y no tiene por que saber nada del reparto.
##
## Silenciosa cuando no hay nada que pintar - la camara de precarga tambien corre
## en escenas a las que se entro sin pantalla de carga (`awaiting_manual_end`
## falso), y ahi esto no debe tocar un loader que ya se esta cerrando.
func report_manual_progress(fraction: float) -> void:
	if _current_loader == null or not awaiting_manual_end:
		return

	_current_loader.update_progress(MANUAL_LOAD_SHARE
		+ clampf(fraction, 0.0, 1.0) * (1.0 - MANUAL_LOAD_SHARE))

func finish_loading_screen() -> void:
	get_tree().paused = false
	awaiting_manual_end = false

	# Callable from anywhere (PreloadCamera, the debug menu), so it has to
	# survive being called with nothing up - otherwise it would latch
	# _change_in_flight and refuse every scene change from then on.
	if _current_loader == null:
		_change_in_flight = false
		return

	await _current_loader.complete()

	_free_loader()
	_change_in_flight = false

func _free_loader() -> void:
	if _current_loader == null:
		return

	if _current_loader.get_parent() == self:
		remove_child(_current_loader)

	_current_loader.queue_free()
	_current_loader = null
