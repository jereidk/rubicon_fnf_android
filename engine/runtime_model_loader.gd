extends ResourceFormatLoader
# Carga .glb/.gltf crudos en runtime, para mods.
#
# Godot 4 registra GLTFDocument y GLTFState en MODULE_INITIALIZATION_LEVEL_SCENE
# sin guard de TOOLS_ENABLED (modules/gltf/register_types.cpp), asi que la
# API esta disponible en builds exportadas. Verificado en 4.7.1-stable.
#
# El mod puede traer un .glb o .gltf directo y cargarlo con
# load("res://models/mimodelo.glb"). Devuelve un PackedScene listo para
# instanciar. El camino del archivo se usa como base para resolver las
# texturas y buffers externos de un .gltf; un .glb empaqueta todo adentro
# y no depende de eso.

const EXTENSIONS: PackedStringArray = ["glb", "gltf"]

func _get_recognized_extensions() -> PackedStringArray:
	return EXTENSIONS

func _get_resource_type(_path: String) -> String:
	return "PackedScene"

func _handles_type(type: StringName) -> bool:
	return type == &"PackedScene"

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(path):
		return null

	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, path.get_base_dir(), state)
	if err != OK:
		push_warning("[RuntimeModelLoader] append_from_buffer fallo en %s (err %d)" % [path, err])
		return null

	var scene := doc.generate_scene(state)
	if scene == null:
		push_warning("[RuntimeModelLoader] generate_scene devolvio null para %s" % path)
		return null

	var packed := PackedScene.new()
	if packed.pack(scene) != OK:
		scene.free()
		return null
	return packed
