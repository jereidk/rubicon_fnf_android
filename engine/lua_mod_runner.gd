extends RefCounted
## Ejecuta un mod escrito en Lua con acceso a la API de Godot.
##
## Se abren las librerias LUA_* y GODOT_* que existan como constantes
## accesibles desde ClassDB. Los nombres que no existan se saltan con
## warning (ver log del arranque).
##
## Utilidades globales inyectadas (sin namespace):
##   log(msg)    -> DebugLog con prefijo del mod
##   mod_folder  -> carpeta fisica del mod
##   root        -> Node, raiz del mod (seteado despues de crearlo)
##
## Modelo de retorno del chunk:
##   A) Node directo:      return Node3D.new() (con hijos ya agregados)
##   B) Tabla con hooks:   return { root_type=..., on_ready=..., on_process=..., on_exit=... }

const LUA_STATE_CLASS := "LuaState"
const LUA_TABLE_CLASS := "LuaTable"
const LUA_ERROR_CLASS := "LuaError"
const LUA_FUNCTION_CLASS := "LuaFunction"

## Nombres de constantes a chequear. Los que no existan en ClassDB se
## saltan con warning. Orden: Lua stdlib primero, despues Godot API.
const LUA_LIBS_TO_OPEN: Array[String] = [
	# Lua stdlib
	"LUA_BASE", "LUA_TABLE", "LUA_STRING", "LUA_MATH",
	"LUA_COROUTINE", "LUA_IO", "LUA_OS", "LUA_PACKAGE",
	"LUA_DEBUG", "LUA_CPATH", "LUA_PATH", "LUA_NOENV",
	# Godot API
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
	DebugLog.log("[LuaModRunner] run() folder=%s path=%s" % [_mod_folder, scene_path])

	if not ClassDB.class_exists(LUA_STATE_CLASS):
		push_error("[LuaModRunner] %s no registrado" % LUA_STATE_CLASS)
		return null
	DebugLog.log("[LuaModRunner] %s existe" % LUA_STATE_CLASS)

	_state = ClassDB.instantiate(LUA_STATE_CLASS)
	if _state == null:
		push_error("[LuaModRunner] no pude instanciar %s" % LUA_STATE_CLASS)
		return null
	DebugLog.log("[LuaModRunner] instancia OK")

	# Construir lib_mask chequeando existencia primero. class_get_integer_constant
	# con un nombre inexistente tira ERR_FAIL que aborta la funcion (comportamiento
	# de Godot 4.7). class_has_integer_constant devuelve bool sin error.
	var lib_mask: int = 0
	var valid_names: Array[String] = []
	var missing_names: Array[String] = []
	for const_name in LUA_LIBS_TO_OPEN:
		if not ClassDB.class_has_integer_constant(LUA_STATE_CLASS, const_name):
			missing_names.append(const_name)
			continue
		var val = ClassDB.class_get_integer_constant(LUA_STATE_CLASS, const_name)
		lib_mask |= int(val)
		valid_names.append(const_name)

	DebugLog.log("[LuaModRunner] libs OK: %s" % ", ".join(valid_names))
	if not missing_names.is_empty():
		DebugLog.log("[LuaModRunner] libs inexistentes: %s" % ", ".join(missing_names))
	DebugLog.log("[LuaModRunner] lib_mask=%d" % lib_mask)

	_state.open_libraries(lib_mask)
	DebugLog.log("[LuaModRunner] open_libraries OK")

	var globals = _state.globals
	if globals == null:
		push_error("[LuaModRunner] globals null")
		return null
	DebugLog.log("[LuaModRunner] globals OK")

	globals.set("log", _api_log)
	globals.set("mod_folder", _mod_folder)

	var loaded = _state.load_file(scene_path)
	if loaded == null:
		push_error("[LuaModRunner] load_file(%s) devolvio null" % scene_path)
		return null
	DebugLog.log("[LuaModRunner] load_file -> %s" % loaded.get_class())
	if loaded.get_class() == LUA_ERROR_CLASS:
		push_error("[LuaModRunner] load_file fallo: %s" % str(loaded))
		return null
	if loaded.get_class() != LUA_FUNCTION_CLASS:
		push_error("[LuaModRunner] load_file devolvio %s" % loaded.get_class())
		return null

	_mod_table = _safe_invoke(loaded)
	if _mod_table == null:
		push_error("[LuaModRunner] el chunk no devolvio nada (o error de Lua)")
		return null
	DebugLog.log("[LuaModRunner] chunk ejecutado, tipo=%s" % (
		_mod_table.get_class() if _mod_table is Object else typeof(_mod_table)
	))

	# Modelo A: Node directo
	if _mod_table is Node:
		_root = _mod_table as Node
		_root.name = "LuaModRoot"
		globals.set("root", _root)
		DebugLog.log("[LuaModRunner] %s arranco (Node=%s)" % [_mod_folder, _root.get_class()])
		return _root

	# Modelo B: tabla con callbacks
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

	push_error("[LuaModRunner] chunk devolvio %s" % _mod_table.get_class())
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
		push_error("[Lua:%s] error: %s" % [_mod_folder, str(result)])
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
