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
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			printerr("Scene %s is invalid" % _watching_path)
			_is_loading = false
			ErrorHandler.show_error("Attemped to load invalid resource\n%s" % _watching_path, ERR_INVALID_DATA)
		ResourceLoader.THREAD_LOAD_FAILED:
			printerr("Failed to load scene %s" % _watching_path)
			_is_loading = false
			ErrorHandler.show_error("Failed to load resource.\n%s" % _watching_path, ERR_CANT_ACQUIRE_RESOURCE)

func change_to(path: String, loading_screen: StringName = &"hypno", end_manually: bool = false) -> void:
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

	# Pay for shader compilation here, behind the loading screen, rather than
	# letting it land on the frame a cutscene first reveals something. See
	# LullabyShaderPrewarm - the scene has to be in the tree first, which it
	# is not until the frame after change_scene_to_packed().
	if Settings.lullaby_shader_prewarm:
		await get_tree().process_frame
		await LullabyShaderPrewarm.prewarm(get_tree(), get_tree().current_scene)

	if not awaiting_manual_end:
		finish_loading_screen()

func finish_loading_screen() -> void:
	get_tree().paused = false
	awaiting_manual_end = false

	await _current_loader.complete()

	remove_child(_current_loader)
	_current_loader.queue_free()
