extends SceneTree

## The precache's camera sweep has to be driven by the reveal, not by the clock.
##
## The header of lullaby_preload_camera.gd diagnosed this in its first line and
## only half-fixed it. An AnimationPlayer advances by delta, so on a scene whose
## frames cost hundreds of milliseconds an 0.8 second sweep is over in four or
## five of them - while 67c9fad deliberately stretched the *reveal* across many
## more than that (6737ms for Chimera's 88 nodes on the device). Everything
## revealed after the animation ran out was drawn from whatever pose the last
## key left the camera in, which is the file's own stated failure:
##
##   "Only what the camera saw from its starting pose was ever warmed, which is
##    why pipelines keep compiling later, during play."
##
## Three ways to get the fix wrong, and none of them shows up as a crash:
##
##   poses never collected      - the sweep silently keeps the old behaviour and
##                                nothing moves, which looks exactly like a pass
##   the sweep fights the       - both write the transform on the same frame and
##     animation                  the camera jitters between two sources
##   a scene with no sweep       - the shop and Chimera both author .:position,
##     breaks                     but a scene that does not must still load
##
## Run with:
##   godot --headless --path . --script tools/test_preload_sweep.gd

const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame

	_collect_case()
	_cycle_case()
	_no_sweep_case()
	_lighting_stays_on_case()
	_lighting_baseline_case()
	await _serves_only_after_animation_case()

	print("")
	if _checks < 24:
		print("FALLO: solo %d de 24 comprobaciones corrieron" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el barrido lo guia el revelado, no el reloj")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## The poses come out of the animation the scene already authors, so a scene
## that changes its sweep changes this without anyone editing code.
func _collect_case() -> void:
	var cam := _camera()
	var player := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	lib.add_animation(&"precache", _sweep_animation(
		[Vector3(0.79, 2.61, 4.84), Vector3(-2.60, 2.78, 2.51), Vector3(-0.52, 3.08, -3.12)]))
	player.add_animation_library(&"", lib)
	cam.animation_player = player
	cam.animation_name = &"precache"

	cam._collect_sweep_poses()

	_check("recoge una pose por clave", cam._sweep_poses.size() == 3,
		"%d" % cam._sweep_poses.size())
	_check("y conserva el origen autorado",
		cam._sweep_poses.size() == 3
			and cam._sweep_poses[1].origin.distance_to(Vector3(-2.60, 2.78, 2.51)) < 0.001)
	_check("la rotacion entra en la base",
		cam._sweep_poses.size() == 3 and not cam._sweep_poses[2].basis.is_equal_approx(Basis.IDENTITY))

	player.free()
	cam.free()


## Cycling matters because there are always more revealing frames than poses:
## Chimera authors 15 and spends 30-40 frames revealing 88 nodes. Running off
## the end of the array and stopping would leave the tail parked again, which
## is the bug.
func _cycle_case() -> void:
	var cam := _camera()
	# Typed on this side too: _sweep_poses is Array[Transform3D], and GDScript
	# refuses a bare Array literal for it rather than converting.
	var poses: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)),
		Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)),
	]
	cam._sweep_poses = poses

	var seen: Array[float] = []
	for i in 5:
		cam._serve_sweep_pose()
		seen.append(cam.transform.origin.x)

	var expected: Array[float] = [1.0, 2.0, 1.0, 2.0, 1.0]
	_check("sirve una pose por frame", seen.size() == 5)
	_check("y vuelve al principio al agotarlas", seen == expected, str(seen))
	_check("cuenta los frames extra que sirvio", cam._sweep_extra_frames == 5,
		"%d" % cam._sweep_extra_frames)

	cam.free()


## A scene whose precache does not move the camera must still load. The guard is
## in _collect_sweep_poses (find_track returns -1) and in _serve_sweep_pose (an
## empty array), and both halves are needed: the first stops the collection, the
## second stops a caller that never checked.
func _no_sweep_case() -> void:
	var cam := _camera()
	var player := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var anim := Animation.new()
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, ^"../hex:visible")
	anim.track_insert_key(track, 0.0, true)
	lib.add_animation(&"precache", anim)
	player.add_animation_library(&"", lib)
	cam.animation_player = player
	cam.animation_name = &"precache"

	cam._collect_sweep_poses()
	_check("sin pista de posicion no recoge nada", cam._sweep_poses.is_empty())

	var before: Transform3D = cam.transform
	cam._serve_sweep_pose()
	_check("y servir una pose no toca la camara", cam.transform.is_equal_approx(before))

	# The other no-op path: no animation at all.
	var bare := _camera()
	bare._collect_sweep_poses()
	_check("sin AnimationPlayer tampoco revienta", bare._sweep_poses.is_empty())
	bare.free()

	player.free()
	cam.free()


## While the animation plays it owns position and rotation - it is authored to.
## Serving a pose underneath it would put two writers on one transform, so the
## reveal loop only takes over once animation_finished has fired.
##
## Driven through _process() rather than by calling _serve_sweep_pose() directly,
## because the claim is about what _process does with _anim_done false; a test
## that reached past it would pass with the guard deleted.
func _serves_only_after_animation_case() -> void:
	var scene := Node3D.new()
	for i in 40:
		scene.add_child(MeshInstance3D.new())
	root.add_child(scene)
	await process_frame

	var cam := _camera()
	cam._hide_everything(scene)
	cam._started_msec = Time.get_ticks_msec()
	var one_pose: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(9, 9, 9))]
	cam._sweep_poses = one_pose
	# Spend the baseline frame the pacing needs before it will reveal anything.
	cam._process(0.016)

	cam._anim_done = false
	cam._process(0.016)
	_check("con la animacion viva no sirve poses", cam._sweep_extra_frames == 0,
		"%d" % cam._sweep_extra_frames)
	_check("pero el revelado si avanza", cam._revealed > 0, "%d" % cam._revealed)

	cam._anim_done = true
	cam._process(0.016)
	_check("terminada la animacion, toma el relevo", cam._sweep_extra_frames >= 1,
		"%d" % cam._sweep_extra_frames)
	_check("y mueve la camara a la pose", cam.transform.origin.is_equal_approx(Vector3(9, 9, 9)),
		str(cam.transform.origin))

	cam.free()
	scene.queue_free()
	await process_frame


func _sweep_animation(origins: Array) -> Animation:
	var anim := Animation.new()
	var pos := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos, ^".:position")
	var rot := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot, ^".:rotation")
	for i in origins.size():
		anim.track_insert_key(pos, float(i) * 0.05, origins[i])
		anim.track_insert_key(rot, float(i) * 0.05, Vector3(0.0, float(i) * 0.4, 0.0))
	return anim


## What defines the scene's lighting must not be hidden by the reveal.
##
## _hide_everything() used to take every VisualInstance3D, and against the
## 4.7.1 binary that includes Light3D and LightmapGI - neither of which carries
## a material or compiles a pipeline of its own. What they do carry is the
## lighting state, which IS part of the pipeline key. Measured on Vulkan /
## Forward Mobile with three meshes and three distinct shaders:
##
##     geometria, cero luces          spec=3
##     + una omni                     spec=6    (+3, las mismas otra vez)
##     + una spot                     spec=9    (+3)
##     quitando la omni               spec=12   (+3)
##
## versus the control, where the lights are never hidden: turning them on with
## no geometry visible compiles 0, and revealing the same six shaders into an
## already-lit scene compiles 6 instead of 12. So hiding the lights makes the
## precache warm variants the game never draws, and then compile the real ones
## anyway when the reveal reaches the lights.
##
## The other half is safety: taking the bake out from under a mesh is the exact
## failure that blacked Chimera's house out, and both scenes with a LightmapGI
## also carry BAKE_STATIC lights.
##
## The two exclusions this must NOT grow into are checked here too.
## VisibleOnScreenNotifier3D has to keep being hidden or it fires
## screen_entered while a 109-degree camera sweeps the room, and ReflectionProbe
## does real capture work that nothing here has measured against the variant
## cost.
func _lighting_stays_on_case() -> void:
	var cam := _camera()
	var root := Node3D.new()

	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	var omni := OmniLight3D.new()
	root.add_child(omni)
	var spot := SpotLight3D.new()
	root.add_child(spot)
	var lm := LightmapGI.new()
	root.add_child(lm)
	var notifier := VisibleOnScreenNotifier3D.new()
	root.add_child(notifier)
	var probe := ReflectionProbe.new()
	root.add_child(probe)

	cam._hide_everything(root)

	_check("la geometria sigue escondiendose", not mesh.visible)
	_check("la omni se queda encendida", omni.visible)
	_check("y la spot tambien", spot.visible)
	_check("el LightmapGI no se toca", lm.visible)
	_check("el notifier SI se esconde", not notifier.visible)
	_check("y la sonda de reflejos tambien", not probe.visible)
	# El numero que el log usa para decir si el arreglo llego al dispositivo.
	# Aqui nada cuelga de una malla escondida, asi que los dos coinciden; en el
	# telefono una luz dentro de un .gltf podria no hacerlo, y eso es
	# exactamente lo que la linea de MARK esta ahi para delatar.
	_check("cuenta lo que dejo encendido", cam._kept_lit.size() == 3,
		"%d" % cam._kept_lit.size())

	root.free()
	cam.free()


## Una luz bajo un padre que la ESCENA ya trae oculto no es una perdida, y la
## primera version de este contador dijo que si.
##
## Chimera registro `11 luces/bakes intactos de 16` y se leyo como cinco luces
## perdidas por el escondite. Cuatro son `flash` y `PhoneGlow` bajo
## `Sequences/SerenaTakingPictures`, y `Cameralight` y un `OmniLight3D` bajo
## `Environment/chimera_house/mdl_chimera_camera` - y los dos padres shipean
## `visible = false`. Esas luces ya estaban apagadas. Un recuento tomado solo
## despues de esconder no distingue "lo apago mi escondite" de "venia
## apagado", asi que informo de lo segundo como si fuera lo primero.
##
## Con la base tomada antes, el caso queda separado: aqui la luz bajo el padre
## oculto NO cuenta ni antes ni despues, y la que cuelga de una malla que si
## se esconde cuenta antes y no despues. Esa segunda es la perdida real.
func _lighting_baseline_case() -> void:
	var cam := _camera()
	var root := Node3D.new()

	# Caso A: la escena ya lo trae oculto. No debe leerse como perdida.
	var apagado := Node3D.new()
	apagado.visible = false
	root.add_child(apagado)
	var luz_en_apagado := OmniLight3D.new()
	apagado.add_child(luz_en_apagado)

	# Caso B: cuelga de una malla que este walk SI esconde. Perdida real.
	var malla := MeshInstance3D.new()
	malla.mesh = BoxMesh.new()
	root.add_child(malla)
	var luz_en_malla := OmniLight3D.new()
	malla.add_child(luz_en_malla)

	# Control: una luz suelta, que no debe moverse.
	var suelta := OmniLight3D.new()
	root.add_child(suelta)

	# Dentro del arbol de verdad, y esto no es un detalle: is_visible_in_tree()
	# se resuelve al entrar en el arbol, asi que sobre un subarbol suelto
	# devuelve true para todo y las tres comprobaciones de abajo pasan sin
	# medir nada. La primera version de este caso fallaba por eso.
	root.set_script(null)
	get_root().add_child(root)

	cam._hide_everything(root)

	_check("exime las tres luces", cam._kept_lit.size() == 3,
		"%d" % cam._kept_lit.size())
	_check("la base ignora la que ya venia apagada", cam._kept_lit_before == 2,
		"%d" % cam._kept_lit_before)
	# El caso A cambio a proposito, y estas dos comprobaciones lo fijaban al
	# reves. `_open_lit_ancestors()` abre ahora el padre oculto para que la luz
	# alcance el barrido: el log del movil midio
	# `104_photographysesh@0.3s frame=1693.0ms spec+31` con la vram plana, y el
	# banco del propio preload dice por que - el estado de iluminacion forma
	# parte de la clave del pipeline, asi que barrer a oscuras compila la
	# variante sin luz y la sesion de fotos pide otra al encender el flash.
	#
	# Se comprueban las tres luces por separado en vez del agregado, porque el
	# agregado ya no distingue los dos casos: A suma una y B resta otra, y
	# `before - effective` da 0 tapando las dos. B sigue siendo perdida real -
	# una luz colgada de una malla que este walk esconde se apaga - y eso no ha
	# cambiado.
	_check("caso A: la luz bajo el padre oculto ya alumbra",
		luz_en_apagado.is_visible_in_tree())
	_check("caso B: la colgada de una malla escondida sigue perdida",
		not luz_en_malla.is_visible_in_tree())
	_check("y la suelta no se movio", suelta.is_visible_in_tree())

	get_root().remove_child(root)
	root.free()
	cam.free()


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
