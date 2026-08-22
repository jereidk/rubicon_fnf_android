extends SceneTree

## The extra-sweep-poses mechanism, and that it stays confined to camera
## viewpoints - never touches visibility or lighting.
##
## `122_fall@6.8s` still costs `frame=1911.7ms` for `spec+8` with RAM/VRAM
## flat - a pipeline-compile stall - and three more sequences show the same
## shape. All four are cutscene shots the precache's own sweep never visits,
## because that sweep only cycles through the handful of viewpoints ITS OWN
## animation authors. A mesh can be `visible = true` for the whole loading
## screen and never get drawn if the camera never points at it, and a
## material that is never drawn never compiles.
##
## `extra_sweep_animations`/`extra_sweep_player` fold each named sequence's
## OWN `Camera3D:position`/`:rotation` keys into the cycling sweep, so the
## loading-screen camera also passes through those viewpoints. Nothing about
## which nodes get hidden/revealed changes - only which poses the reveal loop
## already has get served.
##
## Two things this pins because they were wrong once during design, before
## either reached a scene file:
##
## - `extra_sweep_player` is NOT the same node as `animation_player`. This
##   node's own `animation_player` is `PreloadCamera/AnimationPlayer`, whose
##   library holds only `precache`. The stalling sequences live on
##   `Sequences/SequencePlayer`, a sibling node with its own library -
##   wiring both to the same player would silently find nothing, forever.
## - the track match is by path *suffix* (`Camera3D:position`), not the
##   literal prefix, because `Sequences/SequencePlayer`'s own tracks are
##   `../Camera3D:position` while this node's own animation uses
##   `.:position` - two different relative conventions for the same camera.
##
## Run with:
##   godot --headless --path . --script tools/test_preload_extra_sweep.gd

const SCRIPT_PATH := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"
const CHIMERA_PATH := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
const EXPECTED_SEQUENCES := [
	&"104_photographysesh", &"114_hexapproach", &"121_closetrunout", &"122_fall",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_static_checks()
	_behavioural_checks()
	_scene_wiring_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _static_checks() -> void:
	var source: String = _read(SCRIPT_PATH)
	var code: String = _strip_comments(source)

	# La invariante de seguridad: este mecanismo no puede escribir visible ni
	# tocar KEEP_VISIBLE/_hide_everything. Se comprueba que la funcion nueva
	# no contenga esas palabras, no solo que exista.
	var fn_at: int = code.find("func _collect_extra_sweep_poses(")
	_check(fn_at >= 0, "_collect_extra_sweep_poses existe")
	if fn_at >= 0:
		var fn_body: String = code.substr(fn_at)
		fn_body = fn_body.substr(0, fn_body.find("\nfunc "))
		_check(not fn_body.contains(".visible"),
			"_collect_extra_sweep_poses no escribe ninguna propiedad visible")
		_check(not fn_body.contains("KEEP_VISIBLE") and not fn_body.contains("_hide_everything"),
			"_collect_extra_sweep_poses no toca el mecanismo de ocultar/revelar")

	_check(code.contains("extra_sweep_player: AnimationPlayer"),
		"extra_sweep_player es una referencia de nodo separada")
	_check(not code.contains("extra_sweep_player = animation_player"),
		"extra_sweep_player nunca se reasigna al mismo AnimationPlayer")
	_check(code.contains('.ends_with("Camera3D:position")'),
		"el emparejamiento de pistas es por sufijo, no por prefijo literal")
	_check(code.contains("_collect_extra_sweep_poses()")
			and code.find("_collect_extra_sweep_poses()") != fn_at,
		"se llama desde _collect_sweep_poses")


func _behavioural_checks() -> void:
	var script: GDScript = load(SCRIPT_PATH)
	if script == null:
		_check(false, "el script carga")
		return

	var cam := Camera3D.new()
	cam.set_script(script)

	var player := AnimationPlayer.new()
	var lib := AnimationLibrary.new()

	var anim := Animation.new()
	var pos_idx: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_idx, NodePath("../Camera3D:position"))
	anim.track_insert_key(pos_idx, 0.0, Vector3(1, 2, 3))
	anim.track_insert_key(pos_idx, 1.0, Vector3(4, 5, 6))
	var rot_idx: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_idx, NodePath("../Camera3D:rotation"))
	anim.track_insert_key(rot_idx, 0.0, Vector3.ZERO)
	anim.track_insert_key(rot_idx, 1.0, Vector3(0.1, 0.2, 0.3))
	lib.add_animation(&"122_fall", anim)

	# Una animacion sin pista de camara: no debe aportar nada ni fallar.
	lib.add_animation(&"sin_camara", Animation.new())

	player.add_animation_library(&"", lib)

	cam.extra_sweep_player = player
	cam.extra_sweep_animations = ([&"122_fall", &"sin_camara", &"no_existe"] as Array[StringName])
	cam.call("_collect_extra_sweep_poses")

	var poses: Array = cam.get("_sweep_poses")
	_check(poses.size() == 2, "dos claves de camara recogidas de 122_fall (encontradas: %d)" % poses.size())
	if poses.size() == 2:
		var first: Transform3D = poses[0]
		_check(first.origin.is_equal_approx(Vector3(1, 2, 3)),
			"la primera pose usa la posicion autorada")

	cam.free()

	# extra_sweep_player sin poner: no debe fallar ni cambiar nada.
	var cam2 := Camera3D.new()
	cam2.set_script(script)
	cam2.extra_sweep_animations = ([&"122_fall"] as Array[StringName])
	cam2.call("_collect_extra_sweep_poses")
	var poses2: Array = cam2.get("_sweep_poses")
	_check(poses2.size() == 0, "sin extra_sweep_player no se recoge nada")
	cam2.free()

	player.free()


func _scene_wiring_checks() -> void:
	var scene: String = _read(CHIMERA_PATH)
	var block_start: int = scene.find('[node name="PreloadCamera"')
	_check(block_start >= 0, "el nodo PreloadCamera sigue en la escena")
	if block_start < 0:
		return
	var block: String = scene.substr(block_start)
	block = block.substr(0, block.find("\n[node "))

	_check(block.contains('extra_sweep_player = NodePath("../Sequences/SequencePlayer")'),
		"extra_sweep_player apunta a Sequences/SequencePlayer, no a su propio AnimationPlayer")

	for seq in EXPECTED_SEQUENCES:
		_check(block.contains('&"%s"' % seq),
			"%s esta en extra_sweep_animations" % seq)

	# Las cuatro tienen que existir de verdad en la biblioteca de SequencePlayer,
	# o el nombre esta mal escrito y no aporta nada en silencio.
	var lib_at: int = scene.find('[sub_resource type="AnimationLibrary" id="AnimationLibrary_mao22"]')
	_check(lib_at >= 0, "la biblioteca de SequencePlayer sigue teniendo ese id")
	if lib_at >= 0:
		var lib_block: String = scene.substr(lib_at)
		lib_block = lib_block.substr(0, lib_block.find("\n["))
		for seq in EXPECTED_SEQUENCES:
			_check(lib_block.contains('&"%s"' % seq),
				"%s existe de verdad en la biblioteca de secuencias" % seq)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _strip_comments(text: String) -> String:
	var out: String = ""
	for line in text.split("\n"):
		var quote: String = ""
		var cut: int = -1
		for i in line.length():
			var c: String = line[i]
			if quote != "":
				if c == quote:
					quote = ""
			elif c == "\"" or c == "'":
				quote = c
			elif c == "#":
				cut = i
				break
		out += (line if cut < 0 else line.substr(0, cut)) + "\n"
	return out
