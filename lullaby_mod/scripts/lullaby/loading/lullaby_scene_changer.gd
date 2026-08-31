class_name LullabySceneChanger extends CanvasLayer

## Emitted around a scene load so the diagnostics log can record what
## was loaded, how long it took and what it cost in memory - the scene
## transitions are exactly where the game stutters worst on a phone.
signal scene_change_started(path: String)
signal scene_change_finished(path: String)

@export var loading_screens: Dictionary[StringName, PackedScene] = {
	&"default": preload("res://lullaby_mod/resources/loading/load_default.tscn"), 
	&"hypno": preload("res://lullaby_mod/resources/loading/load_hypno.tscn")
}

## Si las dependencias de una escena pueden cargarse en paralelo.
##
## Es el tercer parametro de `load_threaded_request()` y su defecto es `false`.
## Ver la llamada, que lleva la evidencia del log: el contador de dependencias se
## queda fijo en 196/348 durante cuatro segundos y salta a 233 de golpe con el
## lote de modelos .gltf.
##
## Constante y no `@export` a proposito: es un interruptor de riesgo, no un
## ajuste. Si aparece un cuelgue de carga se pone a `false` aqui y se vuelve al
## comportamiento por defecto de Godot en una linea.
const USE_SUB_THREADS := true

var _is_loading: bool = false
var _current_loader: LullabyLoadingScreen
var _watching_path: String

var awaiting_manual_end: bool = false

func _ready() -> void :
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void :
	if not _is_loading:
		return

	var progress: Array = [0.0]
	var status: int = ResourceLoader.load_threaded_get_status(_watching_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_current_loader.update_progress(_blended_progress(progress[0]))
		ResourceLoader.THREAD_LOAD_LOADED:
			_current_loader.update_progress(1.0)
			_complete()
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			printerr("Scene %s is invalid" % _watching_path)
			_is_loading = false

			ErrorHandler.show_error("Attemped to load invalid resource\n%s" % _watching_path, ERR_INVALID_DATA)
		ResourceLoader.THREAD_LOAD_FAILED:
			printerr("Failed to load scene %s" % _watching_path)
			_is_loading = false

			ErrorHandler.show_error("Failed to load resource.\n%s" % _watching_path, ERR_CANT_ACQUIRE_RESOURCE)

## The scene's direct dependencies, and the highest fraction reported so far.
var _direct_deps: PackedStringArray = PackedStringArray()
var _reported_progress: float = 0.0

## A progress figure that moves, from two measurements that are both true.
##
## load_threaded_get_status' fraction is nearly useless on the scenes that
## need a loading screen at all. Every one of the eight stalls in the last
## device log sits between 48.6% and 50.0%, and Chimera's load reads 48.6% at
## 3 seconds and 49.9% at 26 - the bar jumps to half in the first second and
## then holds still for forty. The game is working the whole time; the number
## is not.
##
## So it is combined with a second one that does move: how many of the
## scene's direct dependencies are in the resource cache. Neither is the
## truth on its own - the engine's fraction is coarse, and direct
## dependencies are only the first level of a graph hundreds deep - but both
## are honest lower bounds on how far the load has got, so the larger of the
## two is a better lower bound than either.
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

func change_to(path: String, loading_screen: StringName, end_manually: bool = false) -> void :
	if not loading_screens.has(loading_screen):
		loading_screen = &"default"

	get_tree().paused = true
	get_window().gui_disable_input = true

	_watching_path = path
	scene_change_started.emit(path)
	_current_loader = loading_screens[loading_screen].instantiate()
	add_child(_current_loader)

	await _current_loader.start()

	get_tree().unload_current_scene()

	# Y se le deja terminar ANTES de pedir la carga nueva.
	#
	# `unload_current_scene()` hace `queue_free`, que difiere la destruccion al
	# final del fotograma. Pedir la carga en la linea siguiente ponia a destruir
	# la escena vieja y a cargar la nueva a la vez, peleandose por la misma cola
	# del servidor de render. El log del dispositivo lo mide sin ambiguedad:
	#
	#   saliendo de intro.tscn   (189/849 retenidos)   ->  5.3s, sin un paron
	#   saliendo de la tienda    (459/1722 retenidos)  -> 18.4s, 11s clavado
	#   saliendo de sng_chimera  (459/1722 retenidos)  -> 19.0s,  9s clavado
	#
	# Los dos parones se quedan en un numero FIJO de dependencias -196/348 y
	# 296/459- sin avanzar ni una durante esos segundos, y se desbloquean
	# exactamente cuando aparece el lote de modelos .gltf. La unica carga rapida
	# es la unica que salia de una escena pequeña.
	#
	# Dos fotogramas y no uno: el primero corre los `queue_free` encolados, y el
	# segundo deja que el servidor de render procese las RID que esos frees le
	# dejaron. La pantalla de carga ya esta montada -`await _current_loader
	# .start()` esta justo arriba- asi que el jugador no ve ninguno de los dos.
	await get_tree().process_frame
	await get_tree().process_frame

	# Before the request, so the count is of what is cached from here on and
	# not of whatever the outgoing scene happened to leave behind.
	_collect_direct_deps(_watching_path)

	# `use_sub_threads = true`, que es el tercer parametro y por defecto va en
	# false: las dependencias se cargan EN SERIE, en un solo hilo del pool, en un
	# telefono de ocho nucleos.
	#
	# El parrafo de arriba culpaba del paron al solape entre destruir la escena
	# vieja y pedir la nueva, y acerto a medias - los dos `process_frame` bajaron
	# el paron de Chimera de 9-11s a 4s. Pero el log 10226-4fe0a6db conserva la
	# firma entera:
	#
	#     50.0% at 11384ms deps=196/348 status=in_progress
	#     50.0% at 12391ms deps=196/348 status=in_progress
	#     50.0% at 13392ms deps=196/348 status=in_progress
	#     50.0% at 14407ms deps=196/348 status=in_progress
	#     50.0% at 15412ms deps=233/348 +chimera_house.tscn +mdl_chimera_camera.gltf
	#                                   +tex_chimera_sky.png +house_outside.png
	#
	# El contador clavado en 196 durante cuatro segundos y saltando a 233 de
	# golpe, con los nombres del lote a la vista. Son 37 dependencias que se
	# resuelven una detras de otra pudiendo ir a la vez.
	#
	# El riesgo con nombre: con sub-hilos Godot puede llamar a un
	# ResourceFormatLoader propio desde varios hilos. El unico que hay aqui es
	# `RubiChartFileLoader`, y es stateless - ni un miembro, todo en locales, un
	# FileAccess por llamada -, asi que por ahi no hay nada que romper. Lo que
	# queda es el propio soporte de Godot, que historicamente ha dado problemas
	# con esta opcion; si aparece un cuelgue de carga, este parametro es lo
	# primero que hay que quitar, y quitarlo es volver a la firma por defecto.
	#
	# Sin verificar en el dispositivo. Lo que dice si funciono es que el contador
	# de `LOADING` deje de quedarse fijo en un numero durante segundos.
	ResourceLoader.load_threaded_request(_watching_path, "", USE_SUB_THREADS)
	_is_loading = true
	awaiting_manual_end = end_manually

func _complete() -> void :
	_is_loading = false

	get_window().gui_disable_input = false

	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(_watching_path)

	scene_change_finished.emit(_watching_path)
	_watching_path = ""
	get_tree().change_scene_to_packed(packed_scene)

	if !awaiting_manual_end:
		finish_loading_screen()

func finish_loading_screen() -> void :
	get_tree().paused = false
	awaiting_manual_end = false

	await _current_loader.complete()

	remove_child(_current_loader)
	_current_loader.queue_free()
