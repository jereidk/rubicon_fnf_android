extends SceneTree

## Las animaciones de Hex mueven huesos que EXISTEN.
##
## El fallo que esto cubre no daba error de ninguna clase. `misc/jumpscare_short`
## conservaba los nombres de hueso de Blender -`BackDress.L.001`- mientras el
## importador GLTF de Godot los mete al proyecto con guiones bajos
## -`BackDress_L_001`-. 107 de sus 115 pistas apuntaban a huesos inexistentes.
## Una pista de hueso que no resuelve no avisa ni al cargar ni al reproducir: la
## animación "se reproduce", dura sus 4.75 segundos, y el modelo no se mueve.
##
## Jugando se veía como Hex congelado en su jumpscare, sin cabeza y sin que la
## cámara acompañase. Leyendo la escena no se veía NADA: la animación existe,
## está en la librería, la librería resuelve por uid, las pistas de los clips que
## la disparan resuelven, y las texturas están todas. Todo lo comprobable por
## texto salía verde.
##
## Por eso esta guarda no lee texto. Carga el modelo, saca los nombres reales del
## Skeleton3D y comprueba cada pista de cada animación contra ellos. Es la única
## forma de ver un nombre de hueso equivocado.
##
## Y comprueba las diecinueve, no solo la que falló: el error es de autoría - una
## animación exportada sin pasar por el mismo camino que las demás - así que la
## siguiente puede ser cualquiera.
##
## Run with:
##   godot --headless --path . --script tools/test_hex_bones_resolve.gd

const HEX := "res://lullaby_mod/assets/funkin/chimera/models/hex/hex.tscn"

## Cuánto tiene que moverse una animación para contar como viva.
##
## No es un umbral inventado: la rota daba 18 cambios de pose sumando sus cuatro
## tramos, y las sanas dan entre 176 y 328. Cualquier corte entre medias vale;
## 50 deja sitio de sobra por los dos lados.
const MIN_CHANGES := 50

## Las que son poses fijas por definición y no tienen que mover nada con el
## tiempo. `rest` mide 0.00s: es una pose, no una animación.
const STATIC_ANIMS := ["misc/rest", "RESET"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(HEX)
	if not _check(packed != null, "hex.tscn carga"):
		_finish()
		return

	var hex: Node = packed.instantiate()
	root.add_child(hex)

	var player := hex.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if not _check(player != null, "hex.tscn trae su AnimationPlayer en la raíz"):
		_finish()
		return

	var skel: Skeleton3D = _find_skeleton(hex)
	if not _check(skel != null, "y su Skeleton3D"):
		_finish()
		return

	var bones: Dictionary = {}
	for i: int in skel.get_bone_count():
		bones[skel.get_bone_name(i)] = true
	_check(bones.size() > 0, "el esqueleto tiene %d huesos" % bones.size())

	var names: PackedStringArray = player.get_animation_list()
	_check(names.size() >= 19, "Hex trae sus %d animaciones" % names.size())

	for name: String in names:
		_bone_names_check(player, bones, name)
		if not STATIC_ANIMS.has(name):
			_moves_check(player, skel, name)

	hex.free()
	_finish()


## Todo nombre de hueso que una pista pide está en el esqueleto.
func _bone_names_check(player: AnimationPlayer, bones: Dictionary, name: String) -> void:
	var anim: Animation = player.get_animation(name)
	if anim == null:
		return
	var missing: PackedStringArray = []
	for i: int in anim.get_track_count():
		var path: String = String(anim.track_get_path(i))
		if not path.contains(":"):
			continue
		var bone: String = path.get_slice(":", 1)
		if bone.is_empty() or bones.has(bone):
			continue
		# Solo cuentan las que apuntan al esqueleto. Una pista sobre otra
		# propiedad -`:visible`, `:position`- no lleva nombre de hueso.
		if bones.has(bone.replace(".", "_")) or bone.contains("."):
			missing.append(bone)
	_check(missing.is_empty(),
		"%s: sus huesos existen%s" % [name,
			"" if missing.is_empty() else " - NO: " + ", ".join(missing.slice(0, 4))])


## Y la animación mueve el esqueleto de verdad mientras corre.
##
## Se mide el cambio de pose ENTRE INSTANTES de la propia animación, no contra
## una pose de referencia. La primera versión de esta medida comparaba cada
## animación contra la pose que había dejado la anterior: las medidas no eran
## independientes y la primera de la lista se comparaba contra la pose de
## importación, lo que dio un número engañoso.
func _moves_check(player: AnimationPlayer, skel: Skeleton3D, name: String) -> void:
	var anim: Animation = player.get_animation(name)
	if anim == null or anim.length <= 0.0:
		return

	player.play(name)
	var total: int = 0
	var prev: Array[Transform3D] = []
	for step: int in 5:
		player.seek(anim.length * (float(step) / 4.0), true)
		player.advance(0.0)
		var pose: Array[Transform3D] = []
		for b: int in skel.get_bone_count():
			pose.append(skel.get_bone_pose(b))
		if step > 0:
			for b: int in skel.get_bone_count():
				if not pose[b].is_equal_approx(prev[b]):
					total += 1
		prev = pose
	player.stop()

	_check(total >= MIN_CHANGES,
		"%s: mueve el esqueleto (%d cambios de pose)" % [name, total])


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - las animaciones de Hex mueven huesos que existen")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
