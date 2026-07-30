extends CanvasLayer

## Autoload (see project.godot [autoload]) that transitions between menu
## scenes using Lullaby's loading-screen pattern: fade in the loading
## overlay, load the target scene on a thread while driving its progress
## bar, swap scenes, then fade the overlay back out.

const LOADING_SCREEN_SCENE := preload("res://menus/loading/loading_hypno.tscn")

var _loading: RubiconLoadingScreen
var _busy := false

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

func change_scene(path: String) -> void:
	if _busy:
		return
	_busy = true

	_loading = LOADING_SCREEN_SCENE.instantiate()
	add_child(_loading)
	await _loading.play_open()

	if ResourceLoader.load_threaded_request(path) == OK:
		var progress: Array = []
		while ResourceLoader.load_threaded_get_status(path, progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading.set_progress(progress[0])
			await get_tree().process_frame
	else:
		push_error("SceneChanger: failed to start loading %s" % path)

	_loading.set_progress(1.0)
	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		push_error("SceneChanger: failed to load %s" % path)

	await _loading.play_close()
	_loading.queue_free()
	_loading = null
	_busy = false
