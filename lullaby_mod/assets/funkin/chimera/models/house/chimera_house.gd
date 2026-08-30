extends Node3D

## Pasa los materiales de props de la casa de mezcla alfa a recorte alfa.
##
## El glTF marca cinco materiales `alphaMode: BLEND`, y para cuatro de ellos es
## un error de exportacion, no una decision. Medido sobre el canal alfa de sus
## texturas (van embebidas en `chimera0.bin`, hay que decodificarlas para verlo):
##
##     material                a=0      a=255   intermedio
##     props1                31.64%    67.98%     0.39%
##     props2                22.55%    77.16%     0.29%
##     propruhhhhhoneofthem  33.64%    64.93%     1.43%
##     Material.001          52.81%    46.35%     0.83%
##
## Alfa binario. Ese resto de entre uno y otro son los bordes antialiaseados del
## recorte y nada mas: no hay una sola superficie semitransparente de verdad en
## los cuatro.
##
## Lo que cuesta tenerlos en BLEND es que un material mezclado **no escribe
## profundidad**, asi que el motor no puede ordenarlos por pixel y los ordena por
## objeto, por distancia del centro. Cuando dos props se solapan en pantalla el
## orden entre ellos cambia segun se mueve la camara, y eso se ve como un
## parpadeo o como que una cosa se mete dentro de otra. `props1` ademas es
## `doubleSided`, asi que la cara de delante y la de detras del MISMO objeto se
## mezclan entre si sin orden: una comoda se pelea con su propio panel trasero.
##
## Reportado desde el dispositivo como "un modelo que tiembla y parece roto" a la
## derecha del encuadre, en la parte 3D en vivo de Chimera, sobre lo que en la
## captura son tres listones paralelos junto al marco de una ventana - los
## frentes de cajon de `dresser`, que es prop.
##
## Y sale gratis en rendimiento, que es la otra mitad: una superficie mezclada no
## puede hacer early-Z, o sea que es sobredibujado puro. El analisis del log ya
## lo tenia contado sin saber que era esto - "37 de 75 superficies 3D de Chimera
## no opacas".
##
## `foliage` NO entra. Es el quinto BLEND y tiene un 4.85% de alfa intermedio -
## hojas de borde suave -, y ademas ya lleva su propio override de recorte en
## `chimera_house.tscn`, que es de donde sale el patron que se usa aqui
## (`transparency = 2`, umbral 0.5, antialias de alfa apagado).
##
## Por nombre de material y no por nodo a proposito: el override por nodo que ya
## usa la escena necesita saber que superficie de que nodo lleva cada material, y
## son 59 nodos, mientras que el nombre viaja con el material desde el glTF y
## cubre a todos los que lo compartan sin enumerarlos. Y por codigo y no editando
## el .gltf porque tocar el glTF obliga a reimportar el modelo, y reimportarlo
## mueve el bake de LightmapGI - que es exactamente el fallo que dejo la casa a
## oscuras once dias.
const ALPHA_SCISSOR_MATERIALS: Array[StringName] = [
	&"props1", &"props2", &"propruhhhhhoneofthem", &"Material.001",
]

## El mismo umbral que el override de `foliage` que ya hay en la escena.
const SCISSOR_THRESHOLD := 0.5


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
