extends SceneTree

## A light at zero energy must stop being paired with anything.
##
## Godot's mobile renderer decides whether a light touches an object from its
## RANGE, never from its energy. So a light switched on at `light_energy = 0.0`
## is still handed to the shader and still evaluated per fragment, for a result
## multiplied by zero. Chimera's TvLight is that light for the first ~78 seconds
## of the song - authored at 0, range 43.9 in a house ten units across, so it
## reaches every fragment of exactly the wide shots the device measures at
## 57-59ms.
##
## Nothing had spotted it because the diagnostics log's own `luz=` counter
## skips `light_energy <= 0.0`: the light was invisible to the field built to
## find expensive lights, and visible to the GPU. That is the whole bug.
##
## What this pins:
##
##   1. energy 0 -> cull mask 0 (paired with nothing, dropped before shading)
##   2. energy back up -> the AUTHORED mask returns, not a constant. Three of
##      Chimera's lights and two of the shop's ship a custom mask, so restoring
##      0xFFFFF would silently relight layers their author excluded.
##   3. a lit light is never touched at all
##   4. the pass reports its own count, so a device log can tell "fired" from
##      "found nothing"
##
## Run with:
##   godot --headless --path . --script tools/test_dark_light_cull.gd

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var budget: Node = root.get_node_or_null(^"LightBudget")
	if budget == null:
		print("FALLO: no existe el autoload LightBudget")
		quit(1)
		return

	# A real scene, announced as the current one, because the applier caches
	# its light list on the scene change and does nothing before that.
	var scene: Node3D = Node3D.new()

	var dark := OmniLight3D.new()
	dark.name = "TvLightDouble"
	dark.light_energy = 0.0
	dark.omni_range = 43.927
	dark.light_cull_mask = 4293918733  # el de TvLight, con capas quitadas
	scene.add_child(dark)

	var lit := OmniLight3D.new()
	lit.name = "LitLight"
	lit.light_energy = 2.0
	lit.light_cull_mask = 0xFFFFF
	scene.add_child(lit)

	root.add_child(scene)
	current_scene = scene

	# _apply_when_scene_ready awaits two frames before it caches anything.
	for _i in 4:
		await process_frame

	_check("una luz a energia 0 deja de emparejarse",
		dark.light_cull_mask == 0,
		"mascara=%d" % dark.light_cull_mask)

	_check("una luz encendida no se toca",
		lit.light_cull_mask == 0xFFFFF,
		"mascara=%d" % lit.light_cull_mask)

	_check("el pase cuenta lo que tiene apagado",
		budget.call("dark_culled_count") == 1,
		"apagadas=%d" % budget.call("dark_culled_count"))

	# The animation raises it: the authored mask has to come back exactly.
	dark.light_energy = 5.485
	for _i in 2:
		await process_frame

	_check("al subir la energia vuelve la mascara AUTORIZADA",
		dark.light_cull_mask == 4293918733,
		"mascara=%d" % dark.light_cull_mask)

	_check("y deja de contarse",
		budget.call("dark_culled_count") == 0,
		"apagadas=%d" % budget.call("dark_culled_count"))

	# And back down again, twice, because a pass that stashes on every frame
	# instead of only on the transition would stash 0 the second time and
	# restore 0 forever after.
	dark.light_energy = 0.0
	for _i in 3:
		await process_frame
	dark.light_energy = 1.0
	for _i in 2:
		await process_frame

	_check("aguanta un segundo ciclo sin perder la mascara",
		dark.light_cull_mask == 4293918733,
		"mascara=%d" % dark.light_cull_mask)

	print("")
	if _checks < 6:
		print("FALLO: solo %d de 6 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - las luces a energia cero no se evaluan")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
