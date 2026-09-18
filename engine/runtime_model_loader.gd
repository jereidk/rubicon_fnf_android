extends ResourceFormatLoader

## Paths res:// de todos los mods activos. Compartido por referencia
## con ModLoader. Si el path esta aca, es un archivo crudo de un mod
## y hay que leerlo ignorando su .import hermano (que el editor dejo
## en el mod y que apunta a un .oggstr/.ctex que no existe en el pck).
var mod_all_paths: Dictionary = {}

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

func _recognize_path(path: String, _for_type: StringName) -> bool:
	# Godot llama a recognize_path con el type_hint que el analyzer le
	# pasa al preload(). Para preload("res://x.png") en un script que no
	# lo usa explicitamente como Texture2D, el hint llega como
	# "PackedScene". El filtro por defecto (handles_type) devuelve false
	# para PackedScene, y el loader se descarta ANTES de que _load()
	# corra. _recognize_path se evalua antes de ese filtro, asi que
	# devolviendo true para nuestras extensiones ignoramos el type_hint.
	return path.get_extension().to_lower() in EXTENSIONS

func _handles_type(type: StringName) -> bool:
	return type == &"PackedScene"

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	if not mod_all_paths.has(path) and FileAccess.file_exists(path + ".import"):
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
