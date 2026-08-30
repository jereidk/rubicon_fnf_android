extends SceneTree

## Que transparencia tenian los materiales de la casa de Chimera en el pck del
## mod de PC.
##
## La pregunta que contesta: los cuatro `alphaMode: BLEND` de props que hacen
## parpadear a `dresser`, venian asi del mod original o los metio el port?
##
## Se monta con `replace_files = false` como el resto de herramientas de pck, asi
## que lo nuestro gana y del pck solo se ve lo que no tenemos. Eso vale porque el
## `.scn` importado del glTF lleva el hash de su ruta y sus ajustes en el nombre,
## y el del mod no es el nuestro: existe solo en el pck y se puede abrir por su
## propio nombre.
##
##   godot --headless --path . --script tools/probe_pck_house_materials.gd

const PCK := "res://lullaby_mod/original_pck/Lullaby.pck"

func _initialize() -> void:
	if not ProjectSettings.load_resource_pack(PCK, false):
		printerr("no se pudo montar ", PCK)
		quit(1)
		return

	var found: Array[String] = []
	_walk("res://.godot/imported", found)
	print("escenas importadas en el pck que suenan a la casa: %d" % found.size())

	for path in found:
		var packed: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if packed == null:
			print("  (no carga) ", path)
			continue
		var node: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
		if node == null:
			continue
		print("--- %s" % path.get_file())
		var seen: Dictionary = {}
		_report(node, seen)
		node.free()

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
		elif name.ends_with(".scn") and name.to_lower().contains("chimera"):
			out.append(full)
		name = d.get_next()


func _report(node: Node, seen: Dictionary) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null:
				continue
			var key: String = mat.resource_name
			if seen.has(key):
				continue
			seen[key] = true
			print("    %-24s transparencia=%d  umbral=%.2f  cull=%d" % [
				key if not key.is_empty() else "(sin nombre)",
				mat.transparency, mat.alpha_scissor_threshold, mat.cull_mode,
			])
	for child in node.get_children():
		_report(child, seen)
