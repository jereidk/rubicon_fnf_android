extends SceneTree

## Que transparencia tenian en el pck del mod de PC los materiales que en este
## port han quedado en `alphaMode: BLEND` sin `alphaCutoff`.
##
## Generaliza `probe_pck_house_materials.gd`, que contesto lo mismo para la casa
## de Chimera y encontro una regresion del port: los materiales que perdieron su
## `alphaCutoff` al reexportar el glTF caen a BLEND, porque es lo que hace Godot
## con un material que tiene alfa y no tiene umbral. En la casa fueron cinco de
## siete; barriendo todos los .gltf del proyecto salen quince en total.
##
## Un material mezclado no escribe profundidad: no se puede ordenar por pixel, se
## ordena por objeto, y dos superficies que se solapan cambian de orden segun se
## mueve la camara. Tampoco escribe bien en el mapa de sombras.
##
## OJO CON ESTO, que ya engaño una vez. Se monta con `replace_files = false`
## como el resto de herramientas de pck, o sea que si un `.scn` existe TAMBIEN en
## `.godot/imported/` de este proyecto, lo que se lee es el NUESTRO y no el del
## mod. Y para la casa de Chimera pasa exactamente eso: el hash del importado
## coincide, existe local, y una lectura de esta sonda se dio por buena como "asi
## estaba en el original" cuando era nuestro propio fichero.
##
## Por eso cada linea dice ahora de donde sale. `[pck]` es del mod; `[LOCAL]` es
## de aqui y no prueba nada sobre el original.
##
##   godot --headless --path . --script tools/probe_pck_blend_materials.gd

const PCK := "res://lullaby_mod/original_pck/Lullaby.pck"

## Los quince, por material. El valor es de donde salen, solo para el informe.
const WANTED: Dictionary = {
	"HexBroeknArms": "hex.gltf",
	"mono_jar": "prp_mono_jar.gltf",
	"Fog": "prp_mono_jar.gltf",
	"gigi": "mdl_shop_base.gltf",
	"UIMat": "ui_*.gltf (6 iconos de menu)",
	"props1": "chimera.gltf (ya arreglado)",
	"props2": "chimera.gltf (ya arreglado)",
	"propruhhhhhoneofthem": "chimera.gltf (ya arreglado)",
	"Material.001": "chimera.gltf (ya arreglado)",
	"foliage": "chimera.gltf (ya arreglado)",
}

const MODE := {
	0: "OPACO", 1: "MEZCLA", 2: "RECORTE", 3: "HASH", 4: "PREPASE",
}

var _hits: Dictionary = {}


func _initialize() -> void:
	if not ProjectSettings.load_resource_pack(PCK, false):
		printerr("no se pudo montar ", PCK)
		quit(1)
		return

	var scenes: Array[String] = []
	_walk("res://.godot/imported", scenes)
	print("escenas importadas en el pck: %d" % scenes.size())

	for path in scenes:
		var packed: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if packed == null:
			continue
		var node: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		if node == null:
			continue
		_scan(node, path.get_file())
		node.free()

	print("")
	print("%-24s %-30s %s" % ["material", "de donde (nuestro)", "en el pck"])
	for name: String in WANTED:
		var found: Variant = _hits.get(name)
		print("%-24s %-30s %s" % [
			name, WANTED[name],
			"NO APARECE" if found == null else String(found),
		])
	quit(0)


func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while not name.is_empty():
		var full: String = "%s/%s" % [dir, name]
		if d.current_is_dir():
			_walk(full, out)
		elif name.ends_with(".scn"):
			out.append(full)
		name = d.get_next()


## Si el mismo `.scn` existe en este proyecto, la sonda leyo el nuestro.
func _is_ours(file_name: String) -> bool:
	return FileAccess.file_exists("res://.godot/imported/%s" % file_name)


func _scan(node: Node, origin: String) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null or not WANTED.has(mat.resource_name):
				continue
			# El sufijo es la mitad del dato: ver la cabecera.
			var line: String = "%s umbral=%.2f cull=%d   [%s %s]" % [
				MODE.get(mat.transparency, str(mat.transparency)),
				mat.alpha_scissor_threshold, mat.cull_mode,
				"LOCAL" if _is_ours(origin) else "pck", origin,
			]
			var prev: Variant = _hits.get(mat.resource_name)
			if prev == null:
				_hits[mat.resource_name] = line
			elif not String(prev).begins_with(line.split("   [")[0]):
				# Dos copias del mismo material que NO coinciden: hay que verlo.
				_hits[mat.resource_name] = "%s  ||  %s" % [prev, line]
	for child in node.get_children():
		_scan(child, origin)
