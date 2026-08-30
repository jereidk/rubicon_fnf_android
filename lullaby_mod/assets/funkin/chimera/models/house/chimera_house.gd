extends Node3D

## Red de seguridad por si alguien reimporta el modelo de la casa.
##
## NO arregla nada que este roto hoy, y el comentario que decia lo contrario
## estaba mal. El motor carga el `.scn` importado, no el `.gltf`, y leyendo
## nuestro propio `.godot/imported/chimera.gltf-dfd1139a....scn`
## (`probe_local_house_materials.gd`) los cinco materiales de props ya salen en
## recorte alfa con umbral 0.21, que es lo correcto:
##
##     grars RECORTE 0.21 | trash RECORTE 0.93 | props1 RECORTE 0.21 cull=2
##     props2 RECORTE 0.21 | propruhhhhhoneofthem RECORTE 0.21
##     Material.001 RECORTE 0.21 | foliage RECORTE 0.21
##
## Lo que si es cierto es que la FUENTE y el IMPORTADO no dicen lo mismo. El
## `chimera.gltf` de este repo marca esos cinco como `alphaMode: BLEND` y sin
## `alphaCutoff`; los dos que si lo conservaron (`grars` 0.214, `trash` 0.926)
## entraron como MASK. O sea que el glTF que hay en disco es posterior o distinto
## al que produjo el `.scn`, y perdio los cutoffs por el camino.
##
## Un reimport - cualquier cosa que invalide `.godot/imported/`, desde borrar la
## carpeta hasta cambiar un ajuste de importacion - convertiria esos cinco a
## mezcla alfa, porque es lo que hace Godot con un material que tiene alfa y no
## tiene umbral. Y un material mezclado no escribe profundidad: no se puede
## ordenar por pixel, se ordena por objeto, y dos props que se solapan cambian de
## orden segun se mueve la camara. `props1` ademas es `doubleSided`.
##
## Esto lo deja sin importancia: al cargar, cualquiera de esos cinco que venga en
## mezcla pasa a recorte con el umbral que tiene el .scn de hoy. Mientras nadie
## reimporte no hace absolutamente nada, y esa es la idea.
##
## Por nombre de material y no por nodo porque el override por nodo que usa
## `chimera_house.tscn` necesita saber que superficie de que nodo lleva cada
## material, y son 59 nodos; el nombre viaja con el material desde el glTF.
##
## Lo que NO se hace es arreglar el glTF, que seria lo de fondo: tocarlo obliga a
## reimportar, y reimportar mueve el bake de LightmapGI - el fallo que dejo esta
## casa a oscuras once dias. Queda anotado como deuda, no como emergencia.
const ALPHA_SCISSOR_MATERIALS: Array[StringName] = [
	&"props1", &"props2", &"propruhhhhhoneofthem", &"Material.001", &"foliage",
]

## El umbral que ya tienen los cinco en el `.scn` importado. Importa cual es:
## subirlo se come el borde del recorte, y a 0.5 - el defecto de Godot, y lo que
## este fichero puso primero por error - la vegetacion y los detalles finos
## saldrian mas delgados de lo que su autor los dejo.
const SCISSOR_THRESHOLD := 0.21


func _ready() -> void:
	_scissor_blended_props(self)


## Recorre las superficies una vez y arregla las que estan en la lista.
##
## Idempotente: si ya esta en recorte no se toca, asi que una segunda entrada a
## la cancion no repite el trabajo. Escribe sobre el material importado, que es
## compartido - eso es lo que se quiere, y solo Chimera usa esta casa.
func _scissor_blended_props(node: Node) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null:
				continue
			if not ALPHA_SCISSOR_MATERIALS.has(StringName(mat.resource_name)):
				continue
			if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				continue
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = SCISSOR_THRESHOLD
			mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF

	for child in node.get_children():
		_scissor_blended_props(child)
