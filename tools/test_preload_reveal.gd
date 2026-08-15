extends SceneTree

## The precache now reveals the scene a few nodes per frame instead of all at
## once. This checks the reveal cannot leave the scene wrong.
##
## Spreading the work is the easy part; the risk is entirely in what the scene
## looks like when the loading screen lifts. Three ways to get that wrong, and
## the player sees every one of them:
##
##   something stays hidden       - a hole in the scene, for the whole song
##   something authored hidden
##     gets switched on           - exactly the bug that put a black rect over
##                                  Chimera, from the other direction
##   the reveal never finishes    - a loading screen that never ends, which is
##                                  worse than the 35-second freeze it replaces
##
## Run with:
##   godot --headless --path . --script tools/test_preload_reveal.gd

const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	await _hide_case()
	await _stagger_case()
	await _first_frame_case()
	await _deadline_case()

	print("")
	if _checks < 13:
		print("FALLO: solo %d de 13 comprobaciones corrieron" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el reparto no deja la escena mal")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## What gets hidden, and what must not be.
func _hide_case() -> void:
	var scene := Node3D.new()
	var shown: Array[MeshInstance3D] = []
	for i in 5:
		var mesh := MeshInstance3D.new()
		scene.add_child(mesh)
		shown.append(mesh)

	# Authored hidden. The reveal must never turn this on - a scene hides
	# things on purpose, and switching them back is how a black rect ends up
	# over a song.
	var authored_hidden := MeshInstance3D.new()
	authored_hidden.visible = false
	scene.add_child(authored_hidden)

	# Not a VisualInstance3D, so out of scope entirely.
	var plain := Node3D.new()
	scene.add_child(plain)

	root.add_child(scene)
	await process_frame
	var cam := _camera()
	cam._hide_everything(scene)

	_check("recoge solo lo visible", cam._hidden.size() == 5, "%d" % cam._hidden.size())
	_check("y lo oculta", not shown[0].visible and not shown[4].visible)
	_check("no toca lo que ya estaba oculto", not authored_hidden.visible)
	_check("no recoge un Node3D pelado", not cam._hidden.has(plain))

	# Revealing everything restores exactly the set it hid.
	cam._reveal(cam._hidden.size())
	var all_back: bool = true
	for mesh in shown:
		all_back = all_back and mesh.visible
	_check("revelar devuelve todo lo que oculto", all_back)
	_check("y sigue sin encender lo autorizado oculto", not authored_hidden.visible)

	cam.free()
	scene.queue_free()
	await process_frame

## The whole point: the work must not land on one frame.
func _stagger_case() -> void:
	var scene := Node3D.new()
	for i in 400:
		scene.add_child(MeshInstance3D.new())

	root.add_child(scene)
	await process_frame
	var cam := _camera()
	cam._hide_everything(scene)
	var total: int = cam._hidden.size()

	# One frame's worth, at the largest batch the pacing can ever reach.
	cam._batch = cam.MAX_BATCH
	cam._reveal(cam._batch)

	_check("un frame no revela toda la escena", cam._revealed < total,
		"%d de %d" % [cam._revealed, total])
	_check("pero avanza de verdad", cam._revealed >= cam.FIRST_BATCH,
		"%d" % cam._revealed)

	cam.free()
	scene.queue_free()
	await process_frame

## The first _process must reveal nothing.
##
## The pacing decides each batch from how the previous frame went, and on the
## first frame there is no previous frame - it read a TIME_PROCESS from before
## the scene existed, took that for a cheap frame, and revealed FIRST_BATCH
## nodes on top of a baseline draw cost nobody had measured. The device log put
## 11.28 seconds in that one frame.
##
## Driven through _process() rather than by calling _reveal() directly, because
## the whole claim is about what _process does on its first call - a test that
## reaches past it would pass with the guard deleted.
func _first_frame_case() -> void:
	var scene := Node3D.new()
	for i in 40:
		scene.add_child(MeshInstance3D.new())

	root.add_child(scene)
	await process_frame

	# Never added to the tree, for the reason _camera() documents: add_child
	# runs _ready(), which outside a real scene change calls finish_preload()
	# and frees the camera. The first version of this case did add it, so
	# _finished was already true, every _process returned on its first line,
	# and both checks passed against a camera that was doing nothing at all.
	var cam := _camera()
	cam._hide_everything(scene)
	# What _ready() sets on the real path, and the guard _process checks first.
	cam._started_msec = Time.get_ticks_msec()
	var total: int = cam._hidden.size()
	_check("el doble tiene algo que revelar", total == 40, "%d ocultos" % total)

	cam._process(0.016)
	_check("el primer _process no revela nada", cam._revealed == 0,
		"%d de %d" % [cam._revealed, total])

	cam._process(0.016)
	_check("el segundo si revela", cam._revealed > 0, "%d" % cam._revealed)

	# The guard must not strand a scene that had nothing to hide.
	var cam2 := _camera()
	cam2._started_msec = Time.get_ticks_msec()
	cam2._anim_done = true
	cam2._process(0.016)
	cam2._process(0.016)
	_check("sin nada que ocultar aun asi termina", cam2._finished)

	cam.free()
	cam2.free()
	scene.queue_free()
	await process_frame

## The safety net. Whatever the pacing does, finish_preload has to leave the
## scene whole.
func _deadline_case() -> void:
	var scene := Node3D.new()
	var meshes: Array[MeshInstance3D] = []
	for i in 20:
		var mesh := MeshInstance3D.new()
		scene.add_child(mesh)
		meshes.append(mesh)

	root.add_child(scene)
	await process_frame
	var cam := _camera()
	cam._hide_everything(scene)
	cam._reveal(3)

	# Straight to the handover with most of the scene still hidden, which is
	# what the deadline path and every early return do.
	cam._finished = false
	cam._started_msec = 0
	cam._reveal(cam._hidden.size() - cam._revealed)

	var whole: bool = true
	for mesh in meshes:
		whole = whole and mesh.visible
	_check("terminar no deja nada oculto", whole)

	cam.free()
	scene.queue_free()
	await process_frame

## Deliberately never added to the tree. _ready() reads
## SceneChanger.awaiting_manual_end and, when it is false - which it is
## outside a real scene change - calls finish_preload() and queue_free()s
## itself, so anything the test did afterwards would run on a dead object.
func _camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.set_script(load(CAMERA))
	return cam

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])
