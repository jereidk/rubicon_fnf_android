extends SceneTree

## De donde salen las pipelines que una escena compila.
##
## La tienda va de `pipe=58` a `pipe=325` al entrar: 267 pipelines, a ~150ms
## cada una en frio sobre Adreno 619, que son los ~40s que domina el precache.
## Ningun reparto arregla eso - repartir decide en que fotograma se paga, no
## cuantas hay. La unica palanca que queda es crear menos, y para eso hace falta
## saber de que estan hechas.
##
## Una pipeline en Forward Mobile se identifica por el SHADER que la genera
## (para un StandardMaterial3D, por el juego de caracteristicas activas, que es
## lo que decide el codigo generado) por el formato de vertices de la superficie
## que la dibuja, y luego por especializaciones de estado. Aqui se cuentan las
## dos primeras, que son las que se pueden leer sin un dispositivo delante y las
## unicas sobre las que se puede actuar editando la escena.
##
## Lo que este recuento NO es: el numero exacto que el driver creara. Las
## especializaciones dependen del estado de luces en el momento de dibujar y eso
## no esta en el .tscn. Lo que si es: el numero de FAMILIAS distintas, y una
## familia que aparece una sola vez es una pipeline que existe por un material
## que nadie mas usa.
##
## Run with:
##   godot --headless --path . --script tools/audit_pipeline_inventory.gd [ruta.tscn]

const DEFAULT_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"

## Las propiedades de BaseMaterial3D que cambian el shader generado. Una que no
## este aqui puede variar entre dos materiales sin costar una pipeline nueva -
## un color, una textura, un numero.
const SHADER_KEYED: Array[String] = [
	"transparency", "blend_mode", "cull_mode", "depth_draw_mode", "shading_mode",
	"diffuse_mode", "specular_mode", "disable_ambient_light", "disable_fog",
	"vertex_color_use_as_albedo", "vertex_color_is_srgb",
	"normal_enabled", "emission_enabled", "rim_enabled", "clearcoat_enabled",
	"anisotropy_enabled", "ao_enabled", "heightmap_enabled",
	"subsurf_scatter_enabled", "backlight_enabled", "refraction_enabled",
	"detail_enabled", "billboard_mode", "billboard_keep_scale",
	"grow", "use_point_size", "fixed_size", "no_depth_test",
	"uv1_triplanar", "uv2_triplanar", "texture_filter", "texture_repeat",
	"alpha_scissor_threshold", "alpha_hash_scale", "alpha_antialiasing_mode",
	"proximity_fade_enabled", "distance_fade_mode", "msdf",
]


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

	var families_3d: Dictionary = {}   # clave -> [cuantos usos, ejemplos]
	var families_2d: Dictionary = {}
	var meshes: int = 0
	var surfaces: int = 0
	var canvas_items: int = 0

	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)

		if node is MeshInstance3D:
			meshes += 1
			var mi: MeshInstance3D = node
			var mesh: Mesh = mi.mesh
			var count: int = mesh.get_surface_count() if mesh != null else 0
			for s: int in count:
				surfaces += 1
				var mat: Material = mi.get_active_material(s)
				# `surface_get_format()` solo lo tiene ArrayMesh; una QuadMesh o
				# cualquier PrimitiveMesh no responde y tumbaba la herramienta.
				var fmt: int = 0
				if mesh is ArrayMesh:
					fmt = (mesh as ArrayMesh).surface_get_format(s)
				_bump(families_3d, "%s | vfmt=%d" % [_material_key(mat), fmt], mi.name)
		elif node is CanvasItem:
			canvas_items += 1
			var ci: CanvasItem = node
			_bump(families_2d, _canvas_key(ci), ci.name)

	print("escena        : %s" % target)
	print("MeshInstance3D: %d  (superficies: %d)" % [meshes, surfaces])
	print("CanvasItem    : %d" % canvas_items)
	print("")
	print("familias 3D   : %d" % families_3d.size())
	print("familias 2D   : %d" % families_2d.size())
	print("")

	_report("=== FAMILIAS 3D (shader x formato de vertices) ===", families_3d)
	_report("=== FAMILIAS 2D ===", families_2d)

	_singletons("3D", families_3d)
	_singletons("2D", families_2d)

	scene.free()
	quit(0)


func _bump(into: Dictionary, key: String, who: String) -> void:
	if not into.has(key):
		into[key] = {"n": 0, "who": PackedStringArray()}
	into[key]["n"] += 1
	var who_list: PackedStringArray = into[key]["who"]
	if who_list.size() < 4:
		who_list.append(who)
		into[key]["who"] = who_list


func _report(title: String, families: Dictionary) -> void:
	var rows: Array = []
	for key: String in families:
		rows.append([int(families[key]["n"]), key, families[key]["who"]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print(title)
	for row: Array in rows:
		print("  %4d usos  %s" % [row[0], row[1]])
		print("             %s" % ", ".join(row[2]))
	print("")


## Las familias con un solo uso son el objetivo: cada una es una pipeline entera
## por un material que nadie mas comparte.
func _singletons(what: String, families: Dictionary) -> void:
	var alone: int = 0
	for key: String in families:
		if int(families[key]["n"]) == 1:
			alone += 1
	print("%s: %d de %d familias se usan UNA sola vez (%d%% de las pipelines por un solo dibujo)"
		% [what, alone, families.size(),
			0 if families.is_empty() else int(round(100.0 * float(alone) / float(families.size())))])


## La identidad de shader de un material, no su aspecto.
func _material_key(mat: Material) -> String:
	if mat == null:
		return "SIN MATERIAL (default)"
	if mat is ShaderMaterial:
		var sm: ShaderMaterial = mat
		var sh: Shader = sm.shader
		return "ShaderMaterial %s" % ("(sin shader)" if sh == null
			else (sh.resource_path if not sh.resource_path.is_empty() else "incrustado#%d" % sh.get_instance_id()))
	if mat is BaseMaterial3D:
		var parts: PackedStringArray = []
		for prop: String in SHADER_KEYED:
			var v: Variant = mat.get(prop)
			if v == null:
				continue
			# Solo lo que se aparta del defecto, para que la clave se lea.
			if typeof(v) == TYPE_BOOL and not bool(v):
				continue
			if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) == 0.0:
				continue
			parts.append("%s=%s" % [prop, v])
		parts.sort()
		return "Std[%s]" % ",".join(parts)
	return mat.get_class()


## Un CanvasItem sin material propio usa el shader de canvas por defecto; lo que
## lo separa en pipelines distintas es el material y el modo de mezcla.
func _canvas_key(ci: CanvasItem) -> String:
	var mat: Material = ci.material
	if mat == null:
		return "canvas por defecto (sin material)"
	if mat is ShaderMaterial:
		var sm: ShaderMaterial = mat
		var sh: Shader = sm.shader
		return "ShaderMaterial %s" % ("(sin shader)" if sh == null
			else (sh.resource_path if not sh.resource_path.is_empty() else "incrustado#%d" % sh.get_instance_id()))
	if mat is CanvasItemMaterial:
		var cm: CanvasItemMaterial = mat
		return "CanvasItemMaterial[blend=%d, light=%d, particles=%s]" % [
			cm.blend_mode, cm.light_mode, cm.particles_animation]
	return mat.get_class()
