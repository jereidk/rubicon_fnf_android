extends SceneTree

## Los props de la casa de Chimera se dibujan con recorte alfa, no con mezcla.
##
## El glTF de la casa marca cinco materiales `alphaMode: BLEND`. Cuatro de ellos
## tienen alfa BINARIO - lo unico que hay entre 0 y 255 son los bordes
## antialiaseados del recorte:
##
##     material                a=0      a=255   intermedio
##     props1                31.64%    67.98%     0.39%
##     props2                22.55%    77.16%     0.29%
##     propruhhhhhoneofthem  33.64%    64.93%     1.43%
##     Material.001          52.81%    46.35%     0.83%
##
## Un material mezclado no escribe profundidad, asi que el motor no lo puede
## ordenar por pixel y lo ordena por objeto. Dos props que se solapan cambian de
## orden segun se mueve la camara: parpadean, o uno se mete dentro del otro.
## `props1` es ademas `doubleSided`, con lo que la cara de delante y la de detras
## del mismo objeto se mezclan sin orden ninguno.
##
## Se prueba corriendo el `_ready()` de verdad sobre una jerarquia con los
## materiales tal y como los deja el importador, y no leyendo el codigo, porque
## lo que hay que demostrar es que el recorrido LLEGA a un material colgado de
## una malla anidada y que no toca a los que no van en la lista - `foliage` entre
## ellos, que si tiene borde suave (4.85% intermedio) y ya lleva su propio
## override en `chimera_house.tscn`.
##
## Run with:
##   godot --headless --path . --script tools/test_house_props_not_blended.gd

const HOUSE_SCRIPT := "res://lullaby_mod/assets/funkin/chimera/models/house/chimera_house.gd"
const HOUSE_SCENE := "res://lullaby_mod/assets/funkin/chimera/models/house/chimera_house.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var script: GDScript = load(HOUSE_SCRIPT)
	if not _check(script != null, "chimera_house.gd carga"):
		_finish()
		return

	var listed: Variant = script.get_script_constant_map().get("ALPHA_SCISSOR_MATERIALS")
	if not _check(listed != null, "existe ALPHA_SCISSOR_MATERIALS"):
		_finish()
		return
	var names: Array = Array(listed)
	for wanted in ["props1", "props2", "propruhhhhhoneofthem", "Material.001"]:
		_check(names.has(StringName(wanted)), "%s esta en la lista" % wanted)
	_check(not names.has(&"foliage"),
		"foliage NO esta: tiene borde suave de verdad y ya lleva override propio")

	# Una casa de mentira con la forma que importa: mallas anidadas, un material
	# de la lista colgando de la mas profunda, y uno que no lo esta.
	var root: Node3D = script.new()
	var deep := Node3D.new()
	root.add_child(deep)

	var prop: MeshInstance3D = _mesh_with("props1")
	deep.add_child(prop)
	var leaves: MeshInstance3D = _mesh_with("foliage")
	root.add_child(leaves)
	var unnamed: MeshInstance3D = _mesh_with("")
	root.add_child(unnamed)
	var empty := MeshInstance3D.new()          # sin malla: no puede reventar
	root.add_child(empty)

	# Al arbol y cediendo un fotograma: dentro de `_initialize()` el arbol aun no
	# ha procesado, y sin esta espera `_ready()` no ha corrido cuando se mira.
	get_root().add_child(root)
	await process_frame

	var prop_mat: BaseMaterial3D = prop.mesh.surface_get_material(0)
	_check(prop_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
		"props1 pasa a recorte alfa aunque cuelgue de una malla anidada")
	_check(is_equal_approx(prop_mat.alpha_scissor_threshold, 0.5),
		"con umbral 0.5, el mismo que el override de foliage de la escena")
	_check(prop_mat.alpha_antialiasing_mode == BaseMaterial3D.ALPHA_ANTIALIASING_OFF,
		"y con el antialias de alfa apagado, igual que ese override")

	var leaf_mat: BaseMaterial3D = leaves.mesh.surface_get_material(0)
	_check(leaf_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"foliage se queda en mezcla: no es de los que se tocan")
	var plain_mat: BaseMaterial3D = unnamed.mesh.surface_get_material(0)
	_check(plain_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"un material sin nombre tampoco se toca")

	# Idempotente, que es lo que permite volver a entrar a la cancion sin repetir
	# el recorrido: pasarlo otra vez no cambia nada.
	prop_mat.alpha_scissor_threshold = 0.42
	root.call("_scissor_blended_props", root)
	_check(is_equal_approx(prop_mat.alpha_scissor_threshold, 0.42),
		"una segunda pasada no vuelve a escribir lo que ya esta en recorte")

	# Y que el override que da el patron sigue en la escena.
	var scene: String = _read(HOUSE_SCENE)
	_check(scene.contains("transparency = 2") and scene.contains("alpha_scissor_threshold = 0.5"),
		"chimera_house.tscn conserva el override de recorte de foliage")

	root.free()
	_finish()


func _mesh_with(material_name: String) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = material_name
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3.ZERO, Vector3.RIGHT, Vector3.UP,
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - los props escriben profundidad")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
