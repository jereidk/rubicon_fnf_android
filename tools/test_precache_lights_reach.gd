extends SceneTree

## The precache has to sweep the scene LIT, and hand it back exactly as found.
##
## KEEP_VISIBLE already exempts every Light3D from the hide walk, and that is
## not the same as the light reaching anything: `visible` is local, so a light
## under an ancestor the scene ships hidden has `is_visible_in_tree() == false`
## and contributes nothing. Chimera keeps 11 lights of 16 by that measure, and
## two of the missing five are `flash` and `PhoneGlow` under
## `Sequences/SerenaTakingPictures`, which ships `visible = false`.
##
## Those are the photo session's lights, and the device log prices the gap:
## `104_photographysesh@0.3s frame=1693.0ms spec+31`, with `vram_delta=+0.0MB`.
## The bench in lullaby_preload_camera.gd is why - the lighting state is part
## of the pipeline key, so a surface swept in an unlit room compiles the unlit
## variant and needs a new one the moment the flash comes on.
##
## What this pins is the shape of the fix and, more importantly, the two ways
## it could quietly wreck the scene:
##
##   1. an ancestor left open hands the song a room with the photo-session
##      props standing in it from the first frame
##   2. a light the scene authored off - Chimera's ClosetLight, which nothing
##      anywhere turns on - must NOT be switched on, or the precache lights a
##      room the game never lights
##
## Run with:
##   godot --headless --path . --script tools/test_precache_lights_reach.gd

const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var scene := Node3D.new()

	# The case: a hidden grouping node with a visible light under it, plus a
	# mesh that is only invisible because of that same ancestor.
	var group := Node3D.new()
	group.name = "SerenaTakingPictures"
	group.visible = false
	var flash := SpotLight3D.new()
	flash.name = "flash"
	var prop := MeshInstance3D.new()
	prop.name = "Prop"
	prop.mesh = BoxMesh.new()
	group.add_child(flash)
	group.add_child(prop)
	scene.add_child(group)

	# The control: a light the scene itself switched off, with nothing hidden
	# above it.
	var closet := SpotLight3D.new()
	closet.name = "ClosetLight"
	closet.visible = false
	scene.add_child(closet)

	# And an ordinary lit mesh, to check the hide walk still works.
	var lit_mesh := MeshInstance3D.new()
	lit_mesh.name = "Casa"
	lit_mesh.mesh = BoxMesh.new()
	scene.add_child(lit_mesh)

	root.add_child(scene)
	await process_frame

	var cam: Node = (load(CAMERA) as GDScript).new()
	scene.add_child(cam)
	cam.call("_hide_everything", scene)

	_check("la luz bajo un ancestro oculto ya alumbra",
		flash.is_visible_in_tree(),
		"en_arbol=%s" % flash.is_visible_in_tree())
	_check("la luz que la escena apago SIGUE apagada",
		not closet.visible and not closet.is_visible_in_tree(),
		"visible=%s" % closet.visible)
	_check("y la malla normal si se oculta para el barrido",
		not lit_mesh.visible,
		"visible=%s" % lit_mesh.visible)

	var opened: Array = cam.get("_opened_ancestors")
	_check("solo se abre el ancestro, no la luz ni la malla",
		opened.size() == 1 and opened[0] == group,
		"abiertos=%d" % opened.size())

	cam.call("_close_lit_ancestors")

	_check("al cerrar, el ancestro vuelve a oculto",
		not group.visible,
		"visible=%s" % group.visible)
	_check("y lo que colgaba de el vuelve a no verse",
		not prop.is_visible_in_tree() and not flash.is_visible_in_tree(),
		"prop=%s flash=%s" % [prop.is_visible_in_tree(), flash.is_visible_in_tree()])
	_check("sin dejar nada pendiente",
		(cam.get("_opened_ancestors") as Array).is_empty())

	# A scene with no hidden ancestors must come out byte-identical, which is
	# what makes this safe to ship on every song rather than just Chimera.
	var plain := Node3D.new()
	var lone := OmniLight3D.new()
	plain.add_child(lone)
	root.add_child(plain)
	var cam2: Node = (load(CAMERA) as GDScript).new()
	plain.add_child(cam2)
	cam2.call("_hide_everything", plain)
	_check("una escena sin ancestros ocultos no abre nada",
		(cam2.get("_opened_ancestors") as Array).is_empty())

	# The restore above is exercised by calling it; this pins that the hand-over
	# actually calls it. Without the wiring every check here still passes and
	# the song starts with the photo-session props in the room.
	var src: String = FileAccess.get_file_as_string(CAMERA)
	var finish: int = src.find("func finish_preload(")
	_check("finish_preload cierra los ancestros que abrio",
		finish >= 0 and src.find("_close_lit_ancestors()", finish) > finish,
		"" if finish >= 0 else "no se encontro finish_preload")

	print("")
	if _checks < 9:
		print("FALLO: solo %d de 9 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el barrido va iluminado y la escena vuelve como estaba")
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
