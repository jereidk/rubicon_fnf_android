extends SceneTree

## Cuanta geometria carga una escena, en vertices y en bytes de buffer.
##
## La comparacion que obliga a mirar esto, del log 10235-2bb423f2 y del auditor
## de dependencias:
##
##     Safety Lullaby   203 recursos   39.8 MB    2.831 ms de carga
##     tienda           460 recursos   47.3 MB   37.790 ms de carga
##
## El 84% de los bytes y trece veces mas rapido. Ni los bytes ni el numero de
## recursos explican la diferencia, asi que hay algo que la tienda carga y
## Safety Lullaby no. La diferencia estructural obvia es la geometria: 113
## MeshInstance3D y quince .gltf contra una escena de sprites. Cargar una malla
## no es leer bytes, es deserializar buffers y subirlos a la GPU, y eso no
## aparece en ningun recuento de texturas.
##
## Cuenta lo que se puede contar sin dispositivo: vertices, indices, superficies
## y el tamaño real de los arrays de cada superficie. Los bytes de buffer son la
## suma de los PackedByteArray que devuelve surface_get_array, que es
## exactamente lo que viaja al driver.
##
## Run with:
##   godot --headless --path . --script tools/audit_mesh_weight.gd [ruta.tscn]

const DEFAULT_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"


func _initialize() -> void:
	var target: String = DEFAULT_SCENE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = args[0]

	var packed: PackedScene = load(target)
	if packed == null:
		printerr("no se pudo cargar %s" % target)
		quit(1)
		return
	var scene: Node = packed.instantiate()

	var rows: Array = []
	var total_v: int = 0
	var total_i: int = 0
	var total_b: int = 0
	var surfaces: int = 0
	var instances: int = 0
	var seen_mesh: Dictionary = {}

	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is MeshInstance3D):
			continue
		instances += 1
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		# Una malla compartida por varias instancias se carga UNA vez. Contarla
		# por instancia inflaria el total con geometria que no existe.
		var id: int = mesh.get_instance_id()
		if seen_mesh.has(id):
			continue
		seen_mesh[id] = true

		var v: int = 0
		var idx: int = 0
		var bytes: int = 0
		for s: int in mesh.get_surface_count():
			surfaces += 1
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts is PackedVector3Array:
				v += (verts as PackedVector3Array).size()
			var ind: Variant = arrays[Mesh.ARRAY_INDEX]
			if ind is PackedInt32Array:
				idx += (ind as PackedInt32Array).size()
			for a: Variant in arrays:
				bytes += _array_bytes(a)

		total_v += v
		total_i += idx
		total_b += bytes
		rows.append([bytes, v, idx, mesh.get_surface_count(), _name_of(mesh, node)])

	rows.sort_custom(func(a, b): return a[0] > b[0])

	print("escena       : %s" % target)
	print("instancias   : %d   mallas distintas: %d   superficies: %d" % [instances, seen_mesh.size(), surfaces])
	print("vertices     : %s" % _thousands(total_v))
	print("indices      : %s" % _thousands(total_i))
	print("buffers      : %.1f MB" % (float(total_b) / 1048576.0))
	print("")
	print("--- las 20 mallas mas pesadas ---")
	for i: int in mini(20, rows.size()):
		print("  %8.2f MB  %8s verts  %8s idx  %2d sup  %s" % [
			float(rows[i][0]) / 1048576.0, _thousands(rows[i][1]),
			_thousands(rows[i][2]), rows[i][3], rows[i][4]])

	scene.free()
	quit(0)


func _array_bytes(a: Variant) -> int:
	match typeof(a):
		TYPE_PACKED_VECTOR3_ARRAY: return (a as PackedVector3Array).size() * 12
		TYPE_PACKED_VECTOR2_ARRAY: return (a as PackedVector2Array).size() * 8
		TYPE_PACKED_FLOAT32_ARRAY: return (a as PackedFloat32Array).size() * 4
		TYPE_PACKED_INT32_ARRAY: return (a as PackedInt32Array).size() * 4
		TYPE_PACKED_COLOR_ARRAY: return (a as PackedColorArray).size() * 16
		TYPE_PACKED_BYTE_ARRAY: return (a as PackedByteArray).size()
	return 0


## El nombre util es el del recurso si lo tiene, y si no el del nodo que la
## lleva - una malla incrustada en un .gltf no trae ruta.
func _name_of(mesh: Mesh, node: Node) -> String:
	if not mesh.resource_path.is_empty():
		return mesh.resource_path.get_file()
	if not mesh.resource_name.is_empty():
		return "%s (en %s)" % [mesh.resource_name, node.name]
	return "(sin nombre) en %s" % node.name


func _thousands(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	var c: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "." + out
	return out
