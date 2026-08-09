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

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if not _is_loading:
		return

	var progress: Array = [0.0]
	var status: int = ResourceLoader.load_threaded_get_status(_watching_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_current_loader.update_progress(progress[0])
		ResourceLoader.THREAD_LOAD_LOADED:
			_current_loader.update_progress(1.0)
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
	ResourceLoader.load_threaded_request(_watching_path)
	_is_loading = true
	awaiting_manual_end = end_manually

func _complete() -> void:
	_is_loading = false

	get_window().gui_disable_input = false

	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(_watching_path)

	scene_change_finished.emit(_watching_path)
	_watching_path = ""
	get_tree().change_scene_to_packed(packed_scene)

	if not awaiting_manual_end:
		finish_loading_screen()

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
