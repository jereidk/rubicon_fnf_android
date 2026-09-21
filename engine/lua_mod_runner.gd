extends RefCounted
## Ejecuta un mod escrito en Lua con acceso a la API de Godot.
##
## Se abren las librerias LUA_* y GODOT_* que existan como constantes
## accesibles desde ClassDB (confirmadas en el moto g53: todas menos
## LUA_CPATH/PATH/NOENV, que no hacen falta con GODOT_LOCAL_PATHS).
##
## Utilidades globales inyectadas (sin namespace):
##   log(msg)    -> DebugLog con prefijo del mod
##   mod_folder  -> carpeta fisica del mod
##   root        -> Node, raiz del mod (seteado despues de crearlo)
##
## MODELOS DE ENTRY POINT (el runner acepta los tres):
##
##   C) FUNCIONES GLOBALES (recomendado, no-coder):
##        function setup() end          -- una vez, con root ya creado
##        function update(dt) end       -- cada frame (opcional)
##        function exit() end           -- al salir (opcional)
##
##   B) TABLA CON HOOKS (avanzado):
##        return {
##          root_type = "Node3D",
##          on_ready = function(r) end,
##          on_process = function(dt) end,
##          on_exit = function() end,
##        }
##
##   A) NODE DIRECTO (avanzado):
##        local r = Node3D.new()
##        return r

const LUA_STATE_CLASS := "LuaState"
const LUA_TABLE_CLASS := "LuaTable"
const LUA_ERROR_CLASS := "LuaError"
const LUA_FUNCTION_CLASS := "LuaFunction"

## Nombres de constantes. Los inexistentes se saltan sin ruido.
const LUA_LIBS_TO_OPEN: Array[String] = [
	"LUA_BASE", "LUA_TABLE", "LUA_STRING", "LUA_MATH",
	"LUA_COROUTINE", "LUA_IO", "LUA_OS", "LUA_PACKAGE", "LUA_DEBUG",
	"GODOT_VARIANT", "GODOT_CLASSES", "GODOT_SINGLETONS",
	"GODOT_UTILITY_FUNCTIONS", "GODOT_ENUMS", "GODOT_LOCAL_PATHS",
]

## Hooks del modelo C (funciones globales). Si el chunk no devuelve
## nada, el runner busca estas funciones en _G.
const GLOBAL_SETUP := "setup"
const GLOBAL_UPDATE := "update"
const GLOBAL_EXIT := "exit"

var _state: Object = null
var _root: Node = null
var _globals = null
var _mod_table = null              ## Solo modelo B
var _mod_folder: String = ""
var _last_process_msec: int = 0
var _has_update: bool = false


func run(mod: Dictionary, scene_path: String) -> Node:
	_mod_folder = str(mod.get("folder", "?"))

	if not ClassDB.class_exists(LUA_STATE_CLASS):
		push_error("[LuaModRunner] %s no registrado" % LUA_STATE_CLASS)
		return null
	_state = ClassDB.instantiate(LUA_STATE_CLASS)
	if _state == null:
		push_error("[LuaModRunner] no pude instanciar %s" % LUA_STATE_CLASS)
		return null

	var lib_mask: int = 0
	for const_name in LUA_LIBS_TO_OPEN:
		if not ClassDB.class_has_integer_constant(LUA_STATE_CLASS, const_name):
			continue
		var val = ClassDB.class_get_integer_constant(LUA_STATE_CLASS, const_name)
		lib_mask |= int(val)
	_state.open_libraries(lib_mask)

	_globals = _state.globals
	if _globals == null:
		push_error("[LuaModRunner] globals null")
		return null
	_globals.set("log", _api_log)
	_globals.set("mod_folder", _mod_folder)

	var loaded = _state.load_file(scene_path)
	if loaded == null:
		push_error("[LuaModRunner] load_file(%s) null" % scene_path)
		return null
	if loaded.get_class() == LUA_ERROR_CLASS:
		push_error("[LuaModRunner] load_file fallo: %s" % str(loaded))
		return null
	if loaded.get_class() != LUA_FUNCTION_CLASS:
		push_error("[LuaModRunner] load_file devolvio %s" % loaded.get_class())
		return null

	var chunk_result = _safe_invoke(loaded)
	DebugLog.log("[LuaModRunner] chunk devolvio %s" % (
		str(chunk_result.get_class()) if chunk_result is Object else typeof(chunk_result)
	))

	# Modelo A: Node directo
	if chunk_result is Node:
		_root = chunk_result as Node
		_root.name = "LuaModRoot"
		_globals.set("root", _root)
		_wire_process_global()
		_root.tree_exiting.connect(_on_root_exiting)
		DebugLog.log("[LuaModRunner] %s arranco (Node=%s)" % [_mod_folder, _root.get_class()])
		return _root

	# Modelo B: tabla con root_type + on_ready/on_process/on_exit
	if chunk_result != null and chunk_result is Object and chunk_result.get_class() == LUA_TABLE_CLASS:
		_mod_table = chunk_result
		var root_type: String = "Node"
		var rt = _mod_table.get("root_type")
		if rt != null and rt is String:
			root_type = rt
		_root = _instantiate_node(root_type)
		if _root == null:
			push_error("[LuaModRunner] root_type '%s' invalido" % root_type)
			return null
		_root.name = "LuaModRoot"
		_globals.set("root", _root)

		if _has_mod_function("on_process"):
			_has_update = true
			_wire_process_global()
		_root.tree_exiting.connect(_on_root_exiting)
		_call_mod_if_exists("on_ready", [_root])
		DebugLog.log("[LuaModRunner] %s arranco (B, root=%s)" % [_mod_folder, root_type])
		return _root

	# Modelo C: chunk no devolvio nada -> funciones globales setup/update/exit
	_root = Node.new()
	_root.name = "LuaModRoot"
	_globals.set("root", _root)

	# El mod puede querer otro root_type via variable global. Buscamos
	# global `root_type` si existe, si no dejamos Node.
	var grt = _globals.get("root_type")
	if grt != null and grt is String:
		var rtype_node := _instantiate_node(str(grt))
		if rtype_node != null:
			_root = rtype_node
			_root.name = "LuaModRoot"
			_globals.set("root", _root)

	if _has_global_function(GLOBAL_UPDATE):
		_has_update = true
		_wire_process_global()
	_root.tree_exiting.connect(_on_root_exiting)
	_call_global_if_exists(GLOBAL_SETUP)
	DebugLog.log("[LuaModRunner] %s arranco (C, root=%s, update=%s)" % [
		_mod_folder, _root.get_class(), str(_has_update),
	])
	return _root


func _wire_process_global() -> void:
	_last_process_msec = Time.get_ticks_msec()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		if not tree.process_frame.is_connected(_on_process_frame):
			tree.process_frame.connect(_on_process_frame)


# --- API minimas expuestas a Lua ---

func _api_log(msg) -> void:
	DebugLog.log("[Lua:%s] %s" % [_mod_folder, str(msg)])


func _instantiate_node(type_name: String) -> Node:
	if not ClassDB.class_exists(type_name):
		return null
	var obj: Object = ClassDB.instantiate(type_name)
	if not (obj is Node):
		return null
	return obj as Node


# --- Helpers de invocacion protegida (detecta LuaError como valor) ---

func _safe_invoke(fn, args: Array = []) -> Variant:
	if fn == null:
		return null
	var result
	if args.is_empty():
		result = fn.invoke()
	else:
		result = fn.invokev(args)
	if result != null and result is Object and result.get_class() == LUA_ERROR_CLASS:
		push_error("[Lua:%s] error: %s" % [_mod_folder, str(result)])
		return null
	return result


func _has_global_function(fname: String) -> bool:
	if _globals == null:
		return false
	var fn = _globals.get(fname)
	if fn == null or not (fn is Object):
		return false
	return fn.get_class() == LUA_FUNCTION_CLASS


func _call_global_if_exists(fname: String, args: Array = []) -> Variant:
	if not _has_global_function(fname):
		return null
	return _safe_invoke(_globals.get(fname), args)


func _has_mod_function(fname: String) -> bool:
	if _mod_table == null:
		return false
	var fn = _mod_table.get(fname)
	if fn == null or not (fn is Object):
		return false
	return fn.get_class() == LUA_FUNCTION_CLASS


func _call_mod_if_exists(fname: String, args: Array = []) -> Variant:
	if not _has_mod_function(fname):
		return null
	return _safe_invoke(_mod_table.get(fname), args)


# --- Ciclo de vida ---

func _on_process_frame() -> void:
	if not is_instance_valid(_root) or not _root.is_inside_tree():
		return
	var now := Time.get_ticks_msec()
	var dt: float = (now - _last_process_msec) / 1000.0
	_last_process_msec = now
	if _mod_table != null:
		_call_mod_if_exists("on_process", [dt])
	else:
		_call_global_if_exists(GLOBAL_UPDATE, [dt])


func _on_root_exiting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_on_process_frame):
		tree.process_frame.disconnect(_on_process_frame)
	if _mod_table != null:
		_call_mod_if_exists("on_exit")
	else:
		_call_global_if_exists(GLOBAL_EXIT)
