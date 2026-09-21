extends Node
## Ejecuta un mod escrito en Lua con acceso a la API de Godot.
##
## Modelos:
##   C) function setup() / update(dt) / exit()   (recomendado, sin return)
##   B) return { root_type=, on_ready=, on_process=, on_exit= }
##   A) return node_armado
##
## Utilidades globales: log, mod_folder, root.

const LUA_STATE_CLASS := "LuaState"
const LUA_TABLE_CLASS := "LuaTable"
const LUA_ERROR_CLASS := "LuaError"
const LUA_FUNCTION_CLASS := "LuaFunction"

## Confirmado en device: estas son las unicas constantes que expone
## ClassDB para LuaState en el moto g53 (Android arm64, addon 0.8.2).
const LUA_LIBS_TO_OPEN: Array[String] = [
	"LUA_BASE", "LUA_TABLE", "LUA_STRING", "LUA_MATH",
	"LUA_COROUTINE", "LUA_IO", "LUA_OS", "LUA_PACKAGE", "LUA_DEBUG",
	"LUA_BIT32", "LUA_UTF8",
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
## Diagnostico: contador de frames desde que arranco el mod.
var _frames_alive: int = 0
var _update_calls: int = 0
var _signal_connected: bool = false
var _api_rng := RandomNumberGenerator.new()


## Devuelve un Array con todos los MeshInstance3D del arbol (recursivo).
func _find_all_meshes(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_all_meshes(c))
	return out


## Devuelve el primer Skeleton3D del arbol, o null.
func _find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root
	for c in root.get_children():
		var sk := _find_skeleton(c)
		if sk != null:
			return sk
	return null


## Expuesta a Lua como fix_skeleton_paths(root_node).
## Recorre los MeshInstance3D con skin y les asigna skeleton_path
## apuntando al Skeleton3D del arbol. Sin esto, los meshes cargados
## via GLTFDocument desde un .glb quedan con skeleton_path vacio, el
## skin no se resuelve, y el modelo queda en pose bind aunque se
## modifiquen los bones.
##
## Esta funcion vive en GDScript (no en Lua) porque el addon
## lua-gdextension no convierte bien NodePath desde string al
## asignar propiedades; el setter falla con "Could not set value for
## key 'skeleton_path'".
func _api_fix_skeleton_paths(root: Object) -> int:
	if not (root is Node):
		push_warning("[fix_skeleton_paths] root no es Node")
		return 0
	var root_node := root as Node
	var sk := _find_skeleton(root_node)
	if sk == null:
		push_warning("[fix_skeleton_paths] no encontre Skeleton3D")
		return 0
	var n := 0
	for m in _find_all_meshes(root_node):
		if m is MeshInstance3D:
			var mi := m as MeshInstance3D
			if mi.skin != null:
				mi.skeleton = mi.get_path_to(sk)
				n += 1
	DebugLog.log("[fix_skeleton_paths] reparados %d meshes" % n)
	return n


# ============================================================================
# HELPERS DE CONVENIENCIA — inyectados como globales a Lua
# Sintaxis corta, sin constructores complejos. Pensados para mods que no
# quieren lidiar con Vector3()/Color()/Callable() a mano.
# ============================================================================

# --- pos: getter/setter de position estilo jQuery ---
# pos(n)              -> devuelve position actual
# pos(n, x, y)        -> setea 2D (Control)
# pos(n, x, y, z)     -> setea 3D (Node3D)
func _api_pos(node: Object, x: Variant = null, y: Variant = null, z: Variant = null):
	if node == null:
		return null
	if x == null:
		if node is Node3D:
			return (node as Node3D).position
		if node is Control:
			return (node as Control).position
		return null
	if node is Node3D:
		var z_val: float = 0.0
		if z != null:
			z_val = float(z)
		(node as Node3D).position = Vector3(float(x), float(y), z_val)
	elif node is Control:
		(node as Control).position = Vector2(float(x), float(y))
	return null


func _api_rot(node: Object, x: float, y: float, z: float) -> void:
	if node is Node3D:
		(node as Node3D).rotation = Vector3(x, y, z)


func _api_scale_to(node: Object, factor: float) -> void:
	if node is Node3D:
		(node as Node3D).scale = Vector3(factor, factor, factor)
	elif node is Control:
		(node as Control).scale = Vector2(factor, factor)


# --- Material interno (string hex, string nombre, o Color) ---
func _make_material(color: Variant) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if color is String:
		m.albedo_color = Color.from_string(str(color), Color.MAGENTA)
	elif color is Color:
		m.albedo_color = color
	return m


# --- Mallas preconfiguradas ---
func _api_box(w: float, h: float, d: float, color: Variant = null) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = Vector3(w, h, d)
	var n := MeshInstance3D.new()
	n.mesh = m
	if color != null:
		n.material_override = _make_material(color)
	return n


func _api_sphere(r: float, color: Variant = null) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 24
	m.rings = 12
	var n := MeshInstance3D.new()
	n.mesh = m
	if color != null:
		n.material_override = _make_material(color)
	return n


func _api_capsule(r: float, h: float, color: Variant = null) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 8
	var n := MeshInstance3D.new()
	n.mesh = m
	if color != null:
		n.material_override = _make_material(color)
	return n


func _api_cylinder(r: float, h: float, color: Variant = null) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 12
	var n := MeshInstance3D.new()
	n.mesh = m
	if color != null:
		n.material_override = _make_material(color)
	return n


# --- on: conecta una senal con un callback Lua sin Callable() explicito ---
# on(node, "pressed", function() ... end)
func _api_on(node: Object, signal_name: String, callback: Object) -> void:
	if node == null or callback == null:
		return
	if not node.has_signal(signal_name):
		push_warning("[on] %s no tiene signal '%s'" % [node, signal_name])
		return
	var cb := Callable(callback, "invoke")
	node.connect(signal_name, cb)


# --- class_is: alternativa a 'is' (que no existe en Lua) ---
func _api_class_is(node: Object, cls_name: String) -> bool:
	if node == null:
		return false
	return node.is_class(cls_name)


# --- children: devuelve los hijos como Array 1-indexado (Lua friendly) ---
func _api_children(node: Object) -> Array:
	if node == null or not (node is Node):
		return []
	return (node as Node).get_children()


# --- RNG helpers (evita crear RandomNumberGenerator en Lua) ---
func _api_rand_range(a: float, b: float) -> float:
	return _api_rng.randf_range(a, b)


func _api_rand_int(a: int, b: int) -> int:
	return _api_rng.randi_range(a, b)


# --- set_nodepath: workaround del bug de NodePath en el addon ---
# set_nodepath(mesh_instance, "skeleton", skeleton_node)
func _api_set_nodepath(node: Object, prop_name: String, target: Object) -> bool:
	if node == null or target == null:
		return false
	if not (node is Node) or not (target is Node):
		return false
	var path := (node as Node).get_path_to(target as Node)
	node.set(prop_name, path)
	return true


# --- qaxis: quaternion por eje en string ---
# qaxis("x", angle)
func _api_qaxis(axis: String, angle: float) -> Quaternion:
	var h := angle * 0.5
	match axis.to_lower():
		"x":
			return Quaternion(sin(h), 0, 0, cos(h))
		"y":
			return Quaternion(0, sin(h), 0, cos(h))
		"z":
			return Quaternion(0, 0, sin(h), cos(h))
	return Quaternion()


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
	_globals.set("fix_skeleton_paths", _api_fix_skeleton_paths)

	# Helpers de conveniencia (sintaxis corta para mods)
	_globals.set("pos", _api_pos)
	_globals.set("rot", _api_rot)
	_globals.set("scale_to", _api_scale_to)
	_globals.set("box", _api_box)
	_globals.set("sphere", _api_sphere)
	_globals.set("capsule", _api_capsule)
	_globals.set("cylinder", _api_cylinder)
	_globals.set("on", _api_on)
	_globals.set("class_is", _api_class_is)
	_globals.set("children", _api_children)
	_globals.set("rand_range", _api_rand_range)
	_globals.set("rand_int", _api_rand_int)
	_globals.set("set_nodepath", _api_set_nodepath)
	_globals.set("qaxis", _api_qaxis)

	var loaded = _state.load_file(scene_path)
	if loaded == null or loaded.get_class() != LUA_FUNCTION_CLASS:
		push_error("[LuaModRunner] load_file fallo")
		return null

	var chunk_result = _safe_invoke(loaded)

	if chunk_result is Node:
		_root = chunk_result as Node
		_root.name = "LuaModRoot"
		_self_attach()
		_globals.set("root", _root)
		_wire_lifecycle()
		DebugLog.log("[LuaModRunner] %s arranco (A, %s)" % [_mod_folder, _root.get_class()])
		return _root

	if chunk_result != null and chunk_result is Object and chunk_result.get_class() == LUA_TABLE_CLASS:
		_mod_table = chunk_result
		var root_type_b: String = _read_global_string("root_type", "Node")
		_root = _instantiate_node(root_type_b)
		if _root == null:
			push_error("[LuaModRunner] root_type '%s' invalido" % root_type_b)
			return null
		_root.name = "LuaModRoot"
		_self_attach()
		_globals.set("root", _root)
		_wire_lifecycle()
		_call_mod_if_exists("on_ready", [_root])
		DebugLog.log("[LuaModRunner] %s arranco (B, %s)" % [_mod_folder, _root.get_class()])
		return _root

	var root_type_c: String = _read_global_string("root_type", "Node")
	DebugLog.log("[LuaModRunner] modelo C, root_type=%s" % root_type_c)
	_root = _instantiate_node(root_type_c)
	if _root == null:
		DebugLog.log("[LuaModRunner] root_type '%s' invalido, usando Node" % root_type_c)
		_root = Node.new()
	_root.name = "LuaModRoot"
	_self_attach()
	_globals.set("root", _root)
	_wire_lifecycle()
	_call_global_if_exists(GLOBAL_SETUP)
	DebugLog.log("[LuaModRunner] %s arranco (C, root=%s, update=%s)" % [
		_mod_folder, _root.get_class(), str(_has_update),
	])
	return _root


## Auto-attach: el runner (Node) se hace hijo del root para vivir
## mientras el root viva. Sin esto el runner es RefCounted huerfano y
## se libera cuando _launch() retorna, dejando el signal process_frame
## apuntando a un objeto muerto. Sintoma: setup() corre pero update() no.
func _self_attach() -> void:
	if _root != null and get_parent() != _root:
		_root.add_child(self)


func _wire_lifecycle() -> void:
	_has_update = _has_global_function(GLOBAL_UPDATE)
	DebugLog.log("[LuaModRunner] _wire_lifecycle: has_update=%s" % str(_has_update))
	if _has_update:
		_last_process_msec = Time.get_ticks_msec()
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			DebugLog.log("[LuaModRunner] FATAL: get_main_loop() no es SceneTree")
		else:
			DebugLog.log("[LuaModRunner] SceneTree OK, conectando process_frame...")
			if tree.process_frame.is_connected(_on_process_frame):
				DebugLog.log("[LuaModRunner]   ya estaba conectado")
				_signal_connected = true
			else:
				var err := tree.process_frame.connect(_on_process_frame)
				_signal_connected = (err == OK)
				DebugLog.log("[LuaModRunner]   connect err=%d conectado=%s" % [err, str(_signal_connected)])
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


# ============================================================================
# LOOP
# ============================================================================

func _on_process_frame() -> void:
	_frames_alive += 1

	# Log cada 60 frames para no spamear. Si no aparece nunca,
	# el signal no esta llegando.
	if _frames_alive % 60 == 0:
		DebugLog.log("[LuaModRunner] process alive: frame=%d, update_calls=%d, root_valid=%s" % [
			_frames_alive, _update_calls,
			str(is_instance_valid(_root) and _root.is_inside_tree()),
		])

	if not is_instance_valid(_root):
		return
	if not _root.is_inside_tree():
		return

	var now := Time.get_ticks_msec()
	var dt: float = (now - _last_process_msec) / 1000.0
	_last_process_msec = now

	var r
	if _mod_table != null:
		r = _call_mod_if_exists("on_process", [dt])
	else:
		r = _call_global_if_exists(GLOBAL_UPDATE, [dt])
	if _update_calls < 3:
		# Loguear los primeros 3 updates para confirmar que se llama
		DebugLog.log("[LuaModRunner] update call #%d, dt=%.4f, ret=%s" % [
			_update_calls + 1, dt, str(r)
		])
	_update_calls += 1


func _on_root_exiting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_on_process_frame):
		tree.process_frame.disconnect(_on_process_frame)
	DebugLog.log("[LuaModRunner] root exiting, frames=%d, updates=%d" % [
		_frames_alive, _update_calls,
	])
	if _mod_table != null:
		_call_mod_if_exists("on_exit")
	else:
		_call_global_if_exists(GLOBAL_EXIT)
