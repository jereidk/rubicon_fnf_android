extends RefCounted
## Ejecuta un mod escrito en Lua con acceso a la API de Godot.
##
## Modelos:
##   C) setup() / update(dt) / exit()  (sin return)
##   B) return { root_type=, on_ready=, on_process=, on_exit= }
##   A) return node_armado
##
## Esta version tiene diagnosticos pesados para debuggear el addon
## lua-gdextension: logs de su API, test round-trip de globals, dumps
## ANTES y DESPUES del chunk, y prueba de acceso a globales por String
## y StringName.

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

	_dump_luastate_api()

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
	DebugLog.log("[LuaModRunner] _globals class = %s" % _globals.get_class())

	# TEST DE ROUND-TRIP GDScript -> Lua -> GDScript
	_test_globals_roundtrip()

	_globals.set("log", _api_log)
	_globals.set("mod_folder", _mod_folder)

	var loaded = _state.load_file(scene_path)
	if loaded == null or loaded.get_class() != LUA_FUNCTION_CLASS:
		push_error("[LuaModRunner] load_file fallo")
		return null

	DebugLog.log("[LuaModRunner] ===== ANTES del chunk =====")
	_dump_globals()

	var chunk_result = _safe_invoke(loaded)
	var kind: String = "?"
	if chunk_result == null:
		kind = "NULL"
	elif chunk_result is Object:
		kind = "Object(%s)" % chunk_result.get_class()
	else:
		kind = "prim(%s)" % type_string(typeof(chunk_result))
	DebugLog.log("[LuaModRunner] chunk devolvio [%s]" % kind)

	DebugLog.log("[LuaModRunner] ===== DESPUES del chunk =====")
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


# ============================================================================
# DIAGNOSTICO
# ============================================================================

func _dump_luastate_api() -> void:
	# Lista los metodos de LuaState para ver exactamente que expone.
	var methods: Array = ClassDB.class_get_method_list(LUA_STATE_CLASS, true)
	var names: Array[String] = []
	for m in methods:
		var n: String = str(m.get("name", "?"))
		# Filtrar los que vienen de Object base para reducir ruido
		if n.begins_with("_") or n in ["free", "get_class", "get_meta", "set_meta",
			"has_meta", "get_instance_id", "get_script", "set_script",
			"is_blocking_signals", "set_block_signals", "notification",
			"to_string", "reference", "unreference", "get_reference_count",
			"get_signal_connection_list", "get_incoming_connections",
			"is_connected", "has_signal", "get_signal_list", "emit_signal",
			"connect", "disconnect", "is_class", "set", "get", "set_indexed",
			"get_indexed", "get_property_list", "property_can_revert",
			"property_get_revert", "get_method_list", "has_method",
			"call", "callv", "call_deferred", "call_thread_safe",
			"can_translate_messages", "tr", "tr_n", "is_queued_for_deletion"]:
			continue
		names.append(n)
	names.sort()
	DebugLog.log("[LuaModRunner] LuaState metodos (%d): %s" % [names.size(), ", ".join(names)])

	# Propiedades
	var props: Array = ClassDB.class_get_property_list(LUA_STATE_CLASS, true)
	var pnames: Array[String] = []
	for p in props:
		var pn: String = str(p.get("name", "?"))
		# Filtrar props internas tipo _class_name, _class_id, etc
		if not pn.begins_with("_") and pn != "":
			pnames.append(pn)
	DebugLog.log("[LuaModRunner] LuaState props: %s" % ", ".join(pnames))

	# Constantes integer
	var consts: Array = ClassDB.class_get_integer_constant_list(LUA_STATE_CLASS, true)
	var cnames: Array[String] = []
	for c in consts:
		cnames.append(str(c))
	cnames.sort()
	DebugLog.log("[LuaModRunner] LuaState constants (%d): %s" % [cnames.size(), ", ".join(cnames)])


func _test_globals_roundtrip() -> void:
	# Test 1: GDScript escribe, Lua lee, Lua escribe, GDScript lee.
	_globals.set("__test_val", "hola_desde_gd")
	DebugLog.log("[LuaModRunner] [test] GDScript seteo __test_val = hola_desde_gd")

	# Verificar que GDScript lo lee de vuelta (trivial, pero confirma)
	var direct_read = _globals.get("__test_val")
	DebugLog.log("[LuaModRunner] [test] lectura directa: %s (tipo %s)" % [
		str(direct_read), type_string(typeof(direct_read)),
	])

	# Test 2: ejecutar Lua que lee y escribe
	var test_code := '''
		__test_from_lua = "hola_desde_lua"
		local leido = __test_val
		__test_leido_desde_lua = tostring(leido)
		return leido
	'''
	var result = _state.do_string(test_code)
	if result == null:
		DebugLog.log("[LuaModRunner] [test] do_string devolvio null")
	elif result is Object and result.get_class() == LUA_ERROR_CLASS:
		DebugLog.log("[LuaModRunner] [test] do_string ERROR: %s" % str(result))
	else:
		DebugLog.log("[LuaModRunner] [test] do_string devolvio (%s) %s" % [
			result.get_class() if result is Object else type_string(typeof(result)),
			str(result),
		])

	# Test 3: GDScript lee lo que Lua escribio
	var from_lua = _globals.get("__test_from_lua")
	var read_lua = _globals.get("__test_leido_desde_lua")
	DebugLog.log("[LuaModRunner] [test] __test_from_lua = %s (tipo %s)" % [
		str(from_lua), type_string(typeof(from_lua)),
	])
	DebugLog.log("[LuaModRunner] [test] __test_leido_desde_lua = %s (tipo %s)" % [
		str(read_lua), type_string(typeof(read_lua)),
	])

	# Test 4: probar acceso via StringName
	var via_sn = _globals.get(StringName("__test_from_lua"))
	DebugLog.log("[LuaModRunner] [test] __test_from_lua via StringName = %s" % str(via_sn))


func _dump_globals() -> void:
	var names := [
		GLOBAL_SETUP, GLOBAL_UPDATE, GLOBAL_EXIT, "root_type", "root", "log", "mod_folder",
		"__test_val", "__test_from_lua", "__test_leido_desde_lua",
	]
	var lines: Array[String] = []
	for n in names:
		var v = _globals.get(n)
		var sn_v = _globals.get(StringName(n))
		var main_repr: String
		if v == null:
			main_repr = "<null>"
		elif v is Object:
			main_repr = "Object(%s)" % v.get_class()
		else:
			main_repr = "%s(%s)" % [type_string(typeof(v)), str(v)]
		var sn_repr: String
		if sn_v == null:
			sn_repr = "<null>"
		elif sn_v is Object:
			sn_repr = "Object(%s)" % sn_v.get_class()
		else:
			sn_repr = "%s(%s)" % [type_string(typeof(sn_v)), str(sn_v)]
		lines.append("%s: get(String)=%s | get(SN)=%s" % [n, main_repr, sn_repr])
	DebugLog.log("[LuaModRunner] globals (%d nombres):" % names.size())
	for l in lines:
		DebugLog.log("[LuaModRunner]   %s" % l)


func _read_global_string(gname: String, default_val: String) -> String:
	var v = _globals.get(gname)
	if v == null:
		v = _globals.get(StringName(gname))
	if v == null:
		return default_val
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
	if fn == null:
		fn = _globals.get(StringName(fname))
	if fn == null or not (fn is Object):
		return false
	return fn.get_class() == LUA_FUNCTION_CLASS


func _call_global_if_exists(fname: String, args: Array = []) -> Variant:
	if not _has_global_function(fname):
		return null
	var fn = _globals.get(fname)
	if fn == null:
		fn = _globals.get(StringName(fname))
	return _safe_invoke(fn, args)


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
