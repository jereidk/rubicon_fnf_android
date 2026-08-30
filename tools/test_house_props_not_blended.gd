extends SceneTree

## Los props de la casa de Chimera se dibujan con recorte alfa, no con mezcla.
##
## El glTF de la casa marca cinco materiales `alphaMode: BLEND`. Un material
## mezclado no escribe profundidad, asi que el motor no lo puede ordenar por
## pixel y lo ordena por objeto: dos props que se solapan cambian de orden segun
## se mueve la camara y parpadean, o uno se mete dentro del otro. `props1` es
## ademas `doubleSided`, con lo que la cara de delante y la de detras del mismo
## objeto se mezclan sin orden ninguno.
##
## Que eran recorte y no mezcla no es deduccion: lo dice el pck del mod de PC,
## leido con `tools/probe_pck_house_materials.gd`.
##
##     material               nuestro  cutoff  doble | ORIGINAL (transp, umbral, cull)
##     grars                  MASK     0.214   True  | (2, 0.21, 2)
##     trash                  MASK     0.926   True  | (2, 0.93, 2)
##     props1                 BLEND    -       True  | (2, 0.21, 2)
##     props2                 BLEND    -       False | (2, 0.21, 0)
##     propruhhhhhoneofthem   BLEND    -       False | (2, 0.21, 0)
##     Material.001           BLEND    -       False | (2, 0.21, 0)
##     foliage                BLEND    -       False | (2, 0.21, 0)
##
## `transparencia = 2` es recorte alfa. En el original los siete lo son. Los dos
## que conservaron su `alphaCutoff` al reexportar importaron bien; los cinco que
## lo perdieron cayeron a BLEND, que es lo que hace Godot sin cutoff. Regresion
## del port, con umbral conocido: 0.21.
##
## Se prueba corriendo el `_ready()` de verdad sobre una jerarquia con los
## materiales tal y como los deja el importador, y no leyendo el codigo, porque
## lo que hay que demostrar es que el recorrido LLEGA a un material colgado de
## una malla anidada y que no toca a los que no van en la lista.
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
	for wanted in ["props1", "props2", "propruhhhhhoneofthem", "Material.001", "foliage"]:
		_check(names.has(StringName(wanted)), "%s esta en la lista" % wanted)
	_check(not names.has(&"grars") and not names.has(&"trash"),
		"grars y trash NO estan: conservaron su alphaCutoff e importaron bien")
	_check(is_equal_approx(float(script.get_script_constant_map()["SCISSOR_THRESHOLD"]), 0.21),
		"el umbral es 0.21, el que tienen en el pck del mod de PC")

	# Una casa de mentira con la forma que importa: mallas anidadas, un material
	# de la lista colgando de la mas profunda, y uno que no lo esta.
	var root: Node3D = script.new()
	var deep := Node3D.new()
	root.add_child(deep)

	var prop: MeshInstance3D = _mesh_with("props1")
	deep.add_child(prop)
	var leaves: MeshInstance3D = _mesh_with("wall")
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
	_check(is_equal_approx(prop_mat.alpha_scissor_threshold, 0.21),
		"con el umbral 0.21 del original, no con el 0.5 por defecto")
	_check(prop_mat.alpha_antialiasing_mode == BaseMaterial3D.ALPHA_ANTIALIASING_OFF,
		"y con el antialias de alfa apagado, igual que ese override")

	var leaf_mat: BaseMaterial3D = leaves.mesh.surface_get_material(0)
	_check(leaf_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"un material opaco de la casa (wall) no se toca")
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
