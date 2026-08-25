extends CanvasLayer

## Emitted around a scene load so the diagnostics log can record what
## was loaded, how long it took and what it cost in memory - the scene
## transitions are exactly where the game stutters worst on a phone.
signal scene_change_started(path: String)
signal scene_change_finished(path: String)

## Emitted once the swap is over, with the two costs it is made of, in ms.
##
## `change_scene_to_packed()` is one call from the outside and three completely
## different jobs inside, and until now the log could only see their sum. On
## the Collector's Shop that sum is the worst single frame in the project:
##
##     SPIKE frame=10523.4ms (633.9x) vram_delta=+42.0MB  pipe=145 (+0 ...)
##
## Ten and a half seconds, frozen, with the loading animation stopped dead.
## Which of the three it is decides the fix, and they have nothing in common:
## instantiate() is 835 nodes of allocation and no API in 4.7 can split it -
## only taking nodes out of the scene makes it smaller; add_child() is every
## `_ready()` in the room running at once, which is fixable in script; and the
## 42MB of VRAM is upload bandwidth, fixable only by shrinking textures. The
## same 10.5 seconds points at three different files depending on the answer.
signal scene_swap_measured(path: String, instantiate_ms: float, enter_tree_ms: float)

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
			_current_loader.update_progress(_blended_progress(progress[0]))
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
	# Before the request, so the count is of what is cached from here on and
	# not of whatever the outgoing scene happened to leave behind.
	_collect_direct_deps(_watching_path)
	ResourceLoader.load_threaded_request(_watching_path)
	_is_loading = true
	awaiting_manual_end = end_manually

func _complete() -> void:
	_is_loading = false

	get_window().gui_disable_input = false

	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(_watching_path)
	var path: String = _watching_path

	scene_change_finished.emit(_watching_path)
	_watching_path = ""
	_swap_to(packed_scene, path)

	if not awaiting_manual_end:
		finish_loading_screen()

## Puts the loaded scene in the tree, timing the two halves separately.
##
## Why not change_scene_to_packed(). That call does instantiate(), the
## `current_scene` bookkeeping and add_child() back to back inside one deferred
## block, so both costs land on one frame and the log can only ever report
## their sum. On the Collector's Shop that sum is 10523.4ms in a single frozen
## frame, and the two halves want opposite fixes - fewer nodes in the scene
## file, or cheaper `_ready()` scripts. Timing them apart is the whole point.
##
## Doing the swap by hand is not novel here: tools/harness/render_cutscene.gd
## already mounts a song this way, for the unrelated reason that
## change_scene_to_file() frees the caller.
##
## NO `await` BETWEEN THE TWO HALVES, and that is a correctness constraint, not
## a style choice. The first version of this put a `process_frame` in the
## middle so the loading screen could draw once mid-swap. That is cosmetic -
## the timers make the split, not the frame boundary - and it delays the
## `current_scene` assignment by a frame, which this project has already paid
## for once. lullaby_light_budget_applier waits for `current_scene` to go
## non-null and then rewrites every material's shading flags; it MUST land
## before the scene's first draw, because a frame late means the driver
## compiles both variant sets. Its own docstring records the bill: `surf`
## pipelines 209 -> 491, the shop's precache 9889ms -> 34493ms, Chimera's
## 3715ms -> 27371ms. Nothing about the delay looked dangerous then either.
##
## Run contiguously, the swap happens during `_process` on the frame the load
## completes, where change_scene_to_packed() would have deferred it to that
## same frame's end. Every waiter on `current_scene != null` therefore sees it
## at the same time or sooner than before, never later - and sooner is the safe
## direction, since the regression above was caused by applying *later*, after
## a draw. `process_frame` is emitted before rendering, so a one-frame waiter
## still resumes with the scene present and not yet drawn.
##
## `current_scene` is assigned before add_child() because add_child() is what
## runs every `_ready()` in the new tree, and a `_ready()` that reads
## `get_tree().current_scene` should find the scene it belongs to rather than
## null. The harness gets away with the reverse because a toy scene reads
## nothing.
##
## unload_current_scene() already ran back in change_to(), before the threaded
## request, so there is nothing to take down here.
func _swap_to(packed_scene: PackedScene, path: String) -> void:
	var tree: SceneTree = get_tree()

	var t0: int = Time.get_ticks_usec()
	var instance: Node = packed_scene.instantiate()
	var t1: int = Time.get_ticks_usec()

	tree.current_scene = instance
	tree.root.add_child(instance)
	var t2: int = Time.get_ticks_usec()

	scene_swap_measured.emit(path, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0)

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
