@tool
extends EditorScenePostImport

## Quita de los modelos de la tienda los mapas PBR que no se ven en el telefono.
##
## Por que aqui y no en tiempo de ejecucion: un material que REFERENCIA una
## textura la carga, y el coste de la tienda es por recurso. Medido:
##
##     escritorio   Safety Lullaby 1.280ms   tienda 2.039ms   -> 1,6x
##     telefono     Safety Lullaby 2.831ms   tienda 37.790ms  -> 13,3x
##
## El factor ocho que sobra no esta en la escena, es trabajo por recurso que el
## dispositivo hace y el escritorio no. Y por eso recortar bytes no sirvio de
## nada (bajar la tienda de 71,5MB a 47,3MB dejo el reloj igual): lo que hay que
## bajar es el NUMERO de recursos. Anular el slot en el material importado es lo
## unico que consigue que la textura no se cargue - apagarla luego desde un
## preajuste llega tarde, ya esta en memoria.
##
## Que se quita y por que:
##
##   roughness / metallic / ORM - a escala de render 0.5 sobre 1600x720 la
##       diferencia entre una rugosidad por texel y una constante por material
##       no se resuelve. Es el grupo mas numeroso.
##   heightmap - parallax, que ademas es de los efectos mas caros por pixel.
##   ambient occlusion - la tienda lleva un LightmapGI que ya hornea oclusion.
##
## Que se queda: albedo, normal y emision. La normal es la que mas aporta a que
## un objeto se lea como volumen, y la emision es la que enciende las bombillas,
## la caja registradora y los carteles - quitarla apaga la habitacion.
##
## Los valores escalares se conservan tal cual los trajo el .gltf, asi que un
## material metalico sigue siendo metalico; lo que pierde es la variacion dentro
## de la superficie, no el material.
##
## Se aplica por `import_script/path` en el .import de cada modelo, no a todo el
## proyecto: los sprites 2D no pasan por el importador de escenas y los modelos
## de otras canciones se dejan aparte hasta medir si les hace falta.


## Devuelve cuantos slots ha anulado, para que la salida del import lo diga.
func _post_import(scene: Node) -> Object:
	var dropped: int = 0
	var seen: Dictionary = {}

	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is MeshInstance3D):
			continue
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s: int in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s)
			if mat == null:
				continue
			# Un material compartido por varias superficies se toca una vez;
			# tocarlo dos no rompe nada pero falsea el recuento.
			var id: int = mat.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			dropped += _strip(mat)

	print("strip_pbr_maps: %d slots anulados en %d materiales" % [dropped, seen.size()])
	return scene


## Anula los slots en un BaseMaterial3D y apaga las caracteristicas que solo
## existian por ellos.
##
## El orden importa: hay que apagar la caracteristica ADEMAS de anular la
## textura. Un `heightmap_enabled` con textura nula sigue generando el codigo de
## parallax en el shader, asi que dejarlo puesto conservaria la pipeline cara
## que esto existe para quitar - y las familias de material no se fusionarian.
func _strip(mat: Material) -> int:
	var base := mat as BaseMaterial3D
	if base == null:
		return 0

	var n: int = 0

	if base.roughness_texture != null:
		base.roughness_texture = null
		n += 1
	if base.metallic_texture != null:
		base.metallic_texture = null
		n += 1

	if base.heightmap_enabled:
		base.heightmap_texture = null
		base.heightmap_enabled = false
		n += 1

	if base.ao_enabled:
		base.ao_texture = null
		base.ao_enabled = false
		n += 1

	# Y la normal. Es la que mas aporta de las que quedaban, asi que va la
	# ultima y por una razon que no es solo su peso: `normal_enabled` es lo que
	# SEPARA familias de material en el inventario de pipelines.
	#
	#     20 usos  Std[normal_enabled,shading_mode=1,...] | vfmt=34359742519
	#      9 usos  Std[shading_mode=1,...]                | vfmt=34359742519
	#     11 usos  Std[normal_enabled,shading_mode=1,...] | vfmt=34359745559
	#      7 usos  Std[shading_mode=1,...]                | vfmt=34359745559
	#
	# Cada par de esos son dos pipelines donde puede haber una. Apagarla fusiona
	# las familias y ademas deja de hacer falta la tangente, que es un
	# PackedFloat32Array de cuatro flotantes por vertice dentro del buffer y un
	# bit del formato de vertices - o sea otra variante de pipeline menos.
	if base.normal_enabled:
		base.normal_texture = null
		base.normal_enabled = false
		n += 1

	return n
