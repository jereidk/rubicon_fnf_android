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

func _init() -> void:
	# Log de creacion de instancia. Si _register_runtime_loaders
	# crashea en script.new(), el _init del loader no va a aparecer
	# en el log y sabemos exactamente cual fallo.
	var dl := get_node_or_null("/root/DebugLog")
	if dl != null:
		dl.log("[runtime_model_loader] _init OK")


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

func _exists(path: String) -> bool:
	# Godot llama a exists() al resolver un preload() y al consultar
	# ResourceLoader.exists(). Sin pck, res:// no ve el filesystem del
	# mod, asi que el default (FileAccess::exists) daria false. Este
	# override le dice que si, y el analyzer procede a _load().
	return mod_all_paths.has(path)


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	# Si el path es de un mod, leer del archivo fisico. Sin pck, res://
	# no ve el filesystem del mod - el mapeo res:// -> path fisico vive
	# en mod_all_paths (Dictionary compartido por referencia con
	# ModLoader). Si no es de un mod, es un archivo del APK: si tiene
	# .import hermano, delegar al loader nativo.
	var src: String = path
	if mod_all_paths.has(path):
		src = String(mod_all_paths[path])
	elif FileAccess.file_exists(path + ".import"):
		return null
	if not FileAccess.file_exists(src):
		return null

	var bytes := FileAccess.get_file_as_bytes(src)
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
