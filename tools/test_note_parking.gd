extends SceneTree

## Checks the note-parking path in RubiconLevelNoteHandler without needing a
## song, a chart or a single imported asset.
##
## spawn_note() and despawn_note() only reach the controller when the pool
## misses, so a handler with a pre-filled pool exercises the whole
## park/unpark path on its own. That is deliberate: this has to be runnable
## while the project's textures are still importing, and it has to fail
## loudly on the things that would be invisible on device - a note that
## silently left the tree, a mixer that got invalidated anyway, a parked set
## that grows without bound.
##
## Run with:
##   godot --headless --path . --script tools/test_note_parking.gd

const POOL_SIZE := 40

var _failures: int = 0

class StubNote extends RubiconLevelNote:
	## Stands in for the real note. What matters here is only that it is a
	## RubiconLevelNote with children, so entering and leaving the tree is
	## observable and so is being left alone.
	var enter_count: int = 0
	var exit_count: int = 0

	func _init() -> void:
		var child := Node.new()
		child.name = "Guts"
		add_child(child)

	func _enter_tree() -> void:
		enter_count += 1

	func _exit_tree() -> void:
		super()
		exit_count += 1

class StubHandler extends RubiconLevelNoteHandler:
	## sort_graphic is the only abstract member spawn_note actually calls.
	func get_mode_id() -> StringName:
		return &"test"

	func get_unique_id() -> StringName:
		return &"test_lane"

	func sort_graphic(_data_index: int) -> void:
		pass

	func _press(_event: InputEvent) -> void:
		pass

	func _release(_event: InputEvent) -> void:
		pass

	func _autoplay_process(_millisecond_position: float) -> void:
		pass

	## The handler normally gets these from a controller and a chart; here
	## they are set directly so no level has to exist.
	func setup(count: int) -> void:
		data.clear()
		for i in count:
			data.append(RubiChartNote.new())
		graphics.clear()
		graphics.resize(count)
		results.clear()
		results.resize(count)

		var pool: Array = []
		for i in POOL_SIZE:
			pool.append(StubNote.new())
		_note_pool[&"test"] = pool

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	_test_reuse_keeps_notes_in_tree()
	_test_park_cap_is_respected()
	_test_missed_is_cleared_on_park()
	_test_counters_add_up()

	print("")
	if _failures == 0:
		print("todo OK")
		quit(0)
	else:
		print("%d fallo(s)" % _failures)
		quit(1)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok    %s%s" % [name, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %s%s" % [name, "  (%s)" % detail if detail else ""])

func _make_handler(count: int) -> StubHandler:
	var handler := StubHandler.new()
	root.add_child(handler)
	handler.setup(count)
	RubiconLevelNoteHandler.take_churn_stats()
	return handler

## The whole point: a note that has been used once and is used again must not
## have entered the tree a second time.
func _test_reuse_keeps_notes_in_tree() -> void:
	print("reuso sin tocar el arbol")
	var handler := _make_handler(8)

	for i in 4:
		handler.spawn_note(i)
	var first_wave: Array[StubNote] = []
	for i in 4:
		first_wave.append(handler.graphics[i])

	var entered_once: bool = true
	for note in first_wave:
		entered_once = entered_once and note.enter_count == 1
	_check("cada nota entro al arbol una vez", entered_once)

	for i in 4:
		handler.despawn_note(i)

	var still_children: bool = true
	var all_hidden: bool = true
	var all_disabled: bool = true
	for note in first_wave:
		still_children = still_children and note.get_parent() == handler
		all_hidden = all_hidden and not note.visible
		all_disabled = all_disabled and note.process_mode == Node.PROCESS_MODE_DISABLED
	_check("al despawnear siguen siendo hijos", still_children)
	_check("al despawnear quedan ocultas", all_hidden)
	_check("al despawnear quedan sin procesar", all_disabled)

	var exited: int = 0
	for note in first_wave:
		exited += note.exit_count
	_check("ninguna salio del arbol", exited == 0, "exit_count total=%d" % exited)

	for i in range(4, 8):
		handler.spawn_note(i)

	var reused: int = 0
	var re_entered: int = 0
	for i in range(4, 8):
		var note: StubNote = handler.graphics[i]
		if note in first_wave:
			reused += 1
			re_entered += note.enter_count - 1
	_check("la segunda tanda reusa las aparcadas", reused == 4, "reusadas=%d/4" % reused)
	_check("y ninguna volvio a entrar al arbol", re_entered == 0)

	var live_shown: bool = true
	var live_running: bool = true
	for i in range(4, 8):
		var note: StubNote = handler.graphics[i]
		live_shown = live_shown and note.visible
		live_running = live_running and note.process_mode == Node.PROCESS_MODE_INHERIT
	_check("las reusadas vuelven a estar visibles", live_shown)
	_check("las reusadas vuelven a procesar", live_running)

	handler.queue_free()

## Past the cap the handler has to fall back to taking notes out of the tree,
## or a pathological chart grows the scene tree without bound.
func _test_park_cap_is_respected() -> void:
	print("tope del aparcado")
	var total: int = RubiconLevelNoteHandler.PARK_MAX + 6
	var handler := _make_handler(total)

	for i in total:
		handler.spawn_note(i)
	var spawned: Array[StubNote] = []
	for i in total:
		spawned.append(handler.graphics[i])

	for i in total:
		handler.despawn_note(i)

	var parked: int = 0
	var removed: int = 0
	for note in spawned:
		if note.get_parent() == handler:
			parked += 1
		else:
			removed += 1

	_check("aparca hasta el tope", parked == RubiconLevelNoteHandler.PARK_MAX,
		"aparcadas=%d tope=%d" % [parked, RubiconLevelNoteHandler.PARK_MAX])
	_check("el resto sale del arbol como antes", removed == 6,
		"fuera del arbol=%d" % removed)

	# The six that fell out of the tree belong to _note_pool now, and the
	# handler's _exit_tree() frees whatever is in there - freeing them here
	# too is a double free.
	handler.queue_free()

## _exit_tree() used to clear this and a parked note never leaves the tree,
## so parking has to clear it by hand or a note comes back still missed.
func _test_missed_is_cleared_on_park() -> void:
	print("missed se limpia al aparcar")
	var handler := _make_handler(2)

	handler.spawn_note(0)
	var note: StubNote = handler.graphics[0]
	note.missed = true
	handler.despawn_note(0)

	_check("missed queda en false", not note.missed)

	handler.queue_free()

func _test_counters_add_up() -> void:
	print("contadores")
	var handler := _make_handler(6)
	RubiconLevelNoteHandler.take_churn_stats()

	for i in 3:
		handler.spawn_note(i)
	for i in 3:
		handler.despawn_note(i)
	for i in range(3, 6):
		handler.spawn_note(i)

	var churn: Dictionary = RubiconLevelNoteHandler.take_churn_stats()
	_check("spawn cuenta 6", int(churn[&"spawned"]) == 6,
		"spawn=%d" % int(churn[&"spawned"]))
	_check("despawn cuenta 3", int(churn[&"despawned"]) == 3,
		"despawn=%d" % int(churn[&"despawned"]))
	_check("park cuenta las 3 reusadas", int(churn[&"unparked"]) == 3,
		"park=%d" % int(churn[&"unparked"]))
	_check("inst se queda en 0 con el pool lleno",
		int(churn[&"instantiated"]) == 0,
		"inst=%d" % int(churn[&"instantiated"]))
	_check("leerlos los deja a cero",
		int(RubiconLevelNoteHandler.take_churn_stats()[&"spawned"]) == 0)

	handler.queue_free()
