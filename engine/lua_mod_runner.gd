extends RefCounted
## Ejecuta un mod escrito en Lua con acceso a la API de Godot.
##
## Modelos:
##   C) function setup() end / function update(dt) end / function exit() end
##      (sin return; el runner crea el root automaticamente)
##   B) return { root_type=, on_ready=, on_process=, on_exit= }
##   A) return node_armado
##
## Utilidades globales (sin namespace): log, mod_folder, root.

const LUA_STATE_CLASS := "LuaState"
const LUA_TABLE_CLASS := "LuaTable"
const LUA_ERROR_CLASS := "LuaError"
const LUA_FUNCTION_CLASS := "LuaFunction"

const LUA_LIBS_TO_OPEN: Array[String] = [
	"LUA_BASE", "LUA_TABLE", "LUA_STRING", "LUA_MATH",
	"LUA_COROUTINE", "LUA_IO", "LUA_OS", "LUA_PACKAGE", "LUA_DEBUG",
	"GODOT_VARIANT", "GODOT_CLASSES", "GODOT_SINGLETONS",
	"GODOT_UTILITY_FUNCTIONS", "GODOT_ENUMS", "GODOT_LOCAL_PATHS",
]

const GLOBAL_SETUP := "setup"
const GLOBAL_UPDATE := "update"
const GLOBAL_EXIT := "exit"

var _state: Object = null
var _root: Node = null
var _globals = null
var _mod_table = null
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
		push_error("[LuaModRunner] instancia fallo")
		return null

	var lib_mask: int = 0
	for const_name in LUA_LIBS_TO_OPEN:
		if not ClassDB.class_has_integer_constant(LUA_STATE_CLASS, const_name):
			continue
		lib_mask |= int(ClassDB.class_get_integer_constant(LUA_STATE_CLASS, const_name))
	_state.open_libraries(lib_mask)

	_globals = _state.globals
	if _globals == null:
		push_error("[LuaModRunner] globals null")
		return null
	_globals.set("log", _api_log)
	_globals.set("mod_folder", _mod_folder)

	var loaded = _state.load_file(scene_path)
	if loaded == null or loaded.get_class() != LUA_FUNCTION_CLASS:
		push_error("[LuaModRunner] load_file fallo")
		return null

	var chunk_result = _safe_invoke(loaded)

	# DIAGNOSTICO: listar todos los globals del state despues del chunk
	_dump_globals()

	# Modelo A: Node directo
	if chunk_result is Node:
		_root = chunk_result as Node
		_root.name = "LuaModRoot"
		_globals.set("root", _root)
		_wire_lifecycle()
		DebugLog.log("[LuaModRunner] %s arranco (A, %s)" % [_mod_folder, _root.get_class()])
		return _root

	# Modelo B: tabla
	if chunk_result != null and chunk_result is Object and chunk_result.get_class() == LUA_TABLE_CLASS:
		_mod_table = chunk_result
		var root_type_b: String = _read_global_string("root_type", "Node")
		_root = _instantiate_node(root_type_b)
		if _root == null:
			push_error("[LuaModRunner] root_type '%s' invalido" % root_type_b)
			return null
		_root.name = "LuaModRoot"
		_globals.set("root", _root)
		_wire_lifecycle()
		_call_mod_if_exists("on_ready", [_root])
		DebugLog.log("[LuaModRunner] %s arranco (B, %s)" % [_mod_folder, _root.get_class()])
		return _root

	# Modelo C: funciones globales
	var root_type_c: String = _read_global_string("root_type", "Node")
	DebugLog.log("[LuaModRunner] modelo C, root_type=%s" % root_type_c)
	_root = _instantiate_node(root_type_c)
	if _root == null:
		DebugLog.log("[LuaModRunner] root_type '%s' invalido, usando Node" % root_type_c)
		_root = Node.new()
	_root.name = "LuaModRoot"
	_globals.set("root", _root)
	_wire_lifecycle()
	_call_global_if_exists(GLOBAL_SETUP)
	DebugLog.log("[LuaModRunner] %s arranco (C, root=%s, update=%s)" % [
		_mod_folder, _root.get_class(), str(_has_update),
	])
	return _root


func _dump_globals() -> void:
	# LuaTable no expone keys() directo. Pero podemos probar si nombres
	# conocidos estan presentes. Con esto sabemos si el chunk asigno
	# globales donde esperamos.
	var names := [GLOBAL_SETUP, GLOBAL_UPDATE, GLOBAL_EXIT, "root_type", "root", "log", "mod_folder"]
	var found: Array[String] = []
	var types: Array[String] = []
	for n in names:
		var v = _globals.get(n)
		if v != null:
			var t: String = typeof(v) if not (v is Object) else v.get_class()
			found.append(n)
			types.append("%s=%s" % [n, t])
	DebugLog.log("[LuaModRunner] globals presentes: %s" % ", ".join(types))


func _read_global_string(gname: String, default_val: String) -> String:
	var v = _globals.get(gname)
	if v == null:
		return default_val
	# El addon puede devolver String o StringName. Convertimos siempre.
	var s := str(v)
	if s.is_empty():
		return default_val
	return s


func _wire_lifecycle() -> void:
	_has_update = _has_global_function(GLOBAL_UPDATE)
	if _has_update:
		_last_process_msec = Time.get_ticks_msec()
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and not tree.process_frame.is_connected(_on_process_frame):
			tree.process_frame.connect(_on_process_frame)
	_root.tree_exiting.connect(_on_root_exiting)


func _api_log(msg) -> void:
	DebugLog.log("[Lua:%s] %s" % [_mod_folder, str(msg)])


func _instantiate_node(type_name: String) -> Node:
	if not ClassDB.class_exists(type_name):
		return null
	var obj: Object = ClassDB.instantiate(type_name)
	if not (obj is Node):
		return null
	return obj as Node


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
