extends RefCounted
## Ejecuta un mod escrito en Lua.
##
## Modelo: Lua con acceso TOTAL a la API de Godot, sin wrapper ni namespace.
## Se abren las librerias LUA_* (todas menos FFI) y GODOT_* (VARIANT, CLASSES,
## SINGLETONS, UTILITY_FUNCTIONS, ENUMS, LOCAL_PATHS). Un mod puede hacer
## cualquier cosa que haria un script GDScript: instanciar Node3D, conectar
## senales, leer archivos, usar Input/Time/OS/ProjectSettings, etc.
##
## Utilidades inyectadas en el scope global (sin prefijo, sin namespace):
##   log(msg)      -> escribe al DebugLog con prefijo del mod
##   mod_folder    -> string, carpeta del mod (para leer sus assets)
##   root          -> Node, el nodo raiz del mod (se setea despues de crearlo)
##
## Todo lo demas es API de Godot directa. Sin wrapper.
##
## El mod puede devolver:
##   A) Un Node ya armado:
##        local r = Node3D.new()
##        ...
##        return r
##   B) Una tabla con metadatos y callbacks:
##        local mod = {}
##        mod.root_type = "Node3D"          -- opcional, default "Node"
##        function mod.on_ready(root) end
##        function mod.on_process(dt) end
##        function mod.on_exit() end
##        return mod
##
## Errores: cada invoke() pasa por _safe_invoke(), que detecta LuaError y
## lo reporta sin crashear el engine.

const LUA_STATE_CLASS := "LuaState"
const LUA_TABLE_CLASS := "LuaTable"
const LUA_ERROR_CLASS := "LuaError"
const LUA_FUNCTION_CLASS := "LuaFunction"

## Librerias del sandbox. Todo abierto excepto FFI (acceso a memoria C cruda,
## puede crashear el proceso) y JIT (control del compilador, no aporta).
const LUA_LIBS_TO_OPEN: Array[String] = [
	"LUA_BASE", "LUA_TABLE", "LUA_STRING", "LUA_MATH",
	"LUA_COROUTINE", "LUA_IO", "LUA_OS", "LUA_PACKAGE",
	"LUA_DEBUG", "LUA_CPATH", "LUA_PATH", "LUA_NOENV",
	"GODOT_VARIANT", "GODOT_CLASSES", "GODOT_SINGLETONS",
	"GODOT_UTILITY_FUNCTIONS", "GODOT_ENUMS", "GODOT_LOCAL_PATHS",
]

var _state: Object = null
var _root: Node = null
var _mod_table = null
var _mod_folder: String = ""
var _last_process_msec: int = 0
var _has_on_process: bool = false


func run(mod: Dictionary, scene_path: String) -> Node:
	_mod_folder = str(mod.get("folder", "?"))

	if not ClassDB.class_exists(LUA_STATE_CLASS):
		push_error("[LuaModRunner] %s no registrado (addon no cargado)" % LUA_STATE_CLASS)
		return null

	_state = ClassDB.instantiate(LUA_STATE_CLASS)
	if _state == null:
		push_error("[LuaModRunner] no pude instanciar %s" % LUA_STATE_CLASS)
		return null

	var lib_mask: int = 0
	for const_name in LUA_LIBS_TO_OPEN:
		var val = ClassDB.class_get_integer_constant(LUA_STATE_CLASS, const_name)
		if val != null:
			lib_mask |= int(val)
	_state.open_libraries(lib_mask)

	var globals = _state.globals
	if globals == null:
		push_error("[LuaModRunner] _state.globals es null")
		return null

	# Utilidades del engine en scope global. Tres, sin namespace. Si en el
	# futuro hace falta mas azucar (box, sphere, move_to...), va aca como
	# global directo tambien.
	globals.set("log", _api_log)
	globals.set("mod_folder", _mod_folder)

	var loaded = _state.load_file(scene_path)
	if loaded == null:
		push_error("[LuaModRunner] load_file(%s) devolvio null" % scene_path)
		return null
	if loaded.get_class() == LUA_ERROR_CLASS:
		push_error("[LuaModRunner] load_file(%s) fallo: %s" % [scene_path, str(loaded)])
		return null
	if loaded.get_class() != LUA_FUNCTION_CLASS:
		push_error("[LuaModRunner] load_file(%s) devolvio %s" % [scene_path, loaded.get_class()])
		return null

	_mod_table = _safe_invoke(loaded)
	if _mod_table == null:
		return null

	# Modelo A: el chunk devolvio un Node directo
	if _mod_table is Node:
		_root = _mod_table as Node
		_root.name = "LuaModRoot"
		globals.set("root", _root)
		DebugLog.log("[LuaModRunner] %s arranco (Node=%s)" % [_mod_folder, _root.get_class()])
		return _root

	# Modelo B: tabla con root_type + callbacks
	if _mod_table.get_class() == LUA_TABLE_CLASS:
		var root_type: String = "Node"
		var rt = _mod_table.get("root_type")
		if rt != null and rt is String:
			root_type = rt
		_root = _instantiate_node(root_type)
		if _root == null:
			push_error("[LuaModRunner] root_type '%s' invalido" % root_type)
			return null
		_root.name = "LuaModRoot"
		globals.set("root", _root)

		_has_on_process = _has_function("on_process")
		if _has_on_process:
			_last_process_msec = Time.get_ticks_msec()
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null:
				tree.process_frame.connect(_on_process_frame)
		_root.tree_exiting.connect(_on_root_exiting)
		_call_if_exists("on_ready", [_root])
		DebugLog.log("[LuaModRunner] %s arranco (root=%s, process=%s)" % [_mod_folder, root_type, str(_has_on_process)])
		return _root

	push_error("[LuaModRunner] el chunk devolvio %s, esperaba Node o LuaTable" % _mod_table.get_class())
	return null


func _api_log(msg) -> void:
	DebugLog.log("[Lua:%s] %s" % [_mod_folder, str(msg)])


func _instantiate_node(type_name: String) -> Node:
	if not ClassDB.class_exists(type_name):
		return null
	var obj: Object = ClassDB.instantiate(type_name)
	if not (obj is Node):
		return null
	return obj as Node


func _has_function(fname: String) -> bool:
	if _mod_table == null:
		return false
	var fn = _mod_table.get(fname)
	if fn == null:
		return false
	return fn.get_class() == LUA_FUNCTION_CLASS


func _call_if_exists(fname: String, args: Array = []) -> Variant:
	if not _has_function(fname):
		return null
	return _safe_invoke(_mod_table.get(fname), args)


func _safe_invoke(fn, args: Array = []) -> Variant:
	if fn == null:
		return null
	var result
	if args.is_empty():
		result = fn.invoke()
	else:
		result = fn.invokev(args)
	if result != null and result.get_class() == LUA_ERROR_CLASS:
		push_error("[Lua:%s] error en callback: %s" % [_mod_folder, str(result)])
		return null
	return result


func _on_process_frame() -> void:
	if not is_instance_valid(_root):
		return
	if not _root.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	var dt: float = (now - _last_process_msec) / 1000.0
	_last_process_msec = now
	_call_if_exists("on_process", [dt])


func _on_root_exiting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_on_process_frame):
		tree.process_frame.disconnect(_on_process_frame)
	_call_if_exists("on_exit")
