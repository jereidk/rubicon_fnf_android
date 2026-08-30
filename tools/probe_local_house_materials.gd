extends SceneTree

## Que transparencia tienen los materiales de la casa en el .scn importado que
## este proyecto usa DE VERDAD, sin montar ningun pck.
##
## Existe porque `probe_pck_blend_materials.gd` monta el pck con
## `replace_files = false`, o sea que lo nuestro gana, y resulta que
## `.godot/imported/chimera.gltf-dfd1139a....scn` existe tambien aqui: lo que
## aquella sonda leyo para la casa era este fichero, no el del mod. Esto lo lee
## a las claras para poder separar las dos cosas.
##
## Y contesta algo que importa mas que la comparacion: el motor carga el .scn
## importado, no el .gltf. Si el .scn ya trae recorte, el `alphaMode: BLEND` del
## glTF no es lo que se dibuja hoy - solo lo que se dibujaria tras un reimport.
##
##   godot --headless --path . --script tools/probe_local_house_materials.gd

const SCN := "res://.godot/imported/chimera.gltf-dfd1139a0e272c447253615308e65090.scn"
const MODE := {0: "OPACO", 1: "MEZCLA", 2: "RECORTE", 3: "HASH", 4: "PREPASE"}


func _initialize() -> void:
	print("leyendo %s" % SCN)
	print("(sin montar ningun pck)")
	var packed: PackedScene = ResourceLoader.load(SCN, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		printerr("no carga")
		quit(1)
		return
	var node: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	var seen: Dictionary = {}
	_scan(node, seen)
	node.free()
	quit(0)


func _scan(node: Node, seen: Dictionary) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null or seen.has(mat.resource_name):
				continue
			seen[mat.resource_name] = true
			print("    %-24s %-8s umbral=%.2f cull=%d" % [
				mat.resource_name if not mat.resource_name.is_empty() else "(sin nombre)",
				MODE.get(mat.transparency, str(mat.transparency)),
				mat.alpha_scissor_threshold, mat.cull_mode,
			])
	for child in node.get_children():
		_scan(child, seen)
