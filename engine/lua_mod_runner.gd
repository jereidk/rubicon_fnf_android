extends RefCounted
## Ejecuta un mod escrito en Lua como su entry point.
##
## El mod.json declara `"main_scene": "res://main.lua"` y el engine
## detecta la extension .lua en mod_selector._launch(). En vez de
## compilar un GDScript o cargar una escena, crea un LuaState sandboxed,
## inyecta la tabla global `washos` con las APIs disponibles, ejecuta el
## script y usa la tabla que devuelve para armar el nodo raiz.
##
## El mod .lua devuelve una tabla:
##
##   local mod = {}
##   mod.root_type = "Control"  -- opcional, default "Node"
##   function mod.on_ready() ... end
##   return mod
##
## Sandbox: solo se abren las librerias base, table, string, math,
## coroutine y package (esta ultima porque el addon la parchea para
## aceptar paths res:// y user://). NO se abren io, os, debug. Un mod
## no puede leer archivos arbitrarios del sistema ni ejecutar procesos.
##
## API en Lua: la tabla `washos` expuesta como global. Cada funcion
## toma ids numericos para referirse a nodos. Los ids se devuelven al
## crear y se guardan en _nodes_by_id. Esto limita el surface expuesto
## a Lua: no hay forma de acceder a propiedades arbitrarias de un Node
## desde el sandbox.

var _state: LuaState = null
var _root: Node = null
var _mod_table: LuaTable = null
var _mod_folder: String = ""
## Nodos creados por el mod. Lua manipula los nodos indirectamente a
## traves de estos ids.
var _nodes_by_id: Dictionary = {}
var _next_node_id: int = 0
## Callbacks de botones: id de boton -> LuaFunction. Se guardan aca
## para que no se liberen por GC mientras el boton existe.
var _button_callbacks: Dictionary = {}


func run(mod: Dictionary, scene_path: String) -> Node:
	_mod_folder = str(mod.get("folder", "?"))

	_state = LuaState.new()
	# Bitmask de librerias. NO incluye LUA_IO, LUA_OS, LUA_DEBUG.
	_state.open_libraries(
		LuaState.LUA_BASE
		| LuaState.LUA_TABLE
		| LuaState.LUA_STRING
		| LuaState.LUA_MATH
		| LuaState.LUA_COROUTINE
		| LuaState.LUA_PACKAGE
	)

	_state.globals["washos"] = _make_washos_table()

	# Cargar el .lua del pck del mod. load_file devuelve LuaFunction
	# (chunk compilado) o LuaError.
	var loaded = _state.load_file(scene_path)
	if loaded is LuaError:
		push_error("[LuaModRunner] load_file(%s) fallo: %s" % [scene_path, loaded])
		return null
	if not (loaded is LuaFunction):
		push_error("[LuaModRunner] %s no devolvio una funcion" % scene_path)
		return null

	# Ejecutar el chunk. Esperamos que devuelva una tabla (el mod).
	var mod_table = (loaded as LuaFunction).invoke()
	if mod_table == null or not (mod_table is LuaTable):
		push_error("[LuaModRunner] %s no devolvio una tabla" % scene_path)
		return null
	_mod_table = mod_table

	# Leer root_type del mod (default "Node").
	var root_type: String = "Node"
	var rt = _mod_table.get("root_type")
	if rt != null and rt is String:
		root_type = rt

	# Crear el nodo raiz segun root_type.
	_root = _instantiate_node(root_type)
	if _root == null:
		push_error("[LuaModRunner] root_type '%s' no es un Node valido" % root_type)
		return null

	# Exponer el id del nodo raiz al mod.
	_state.globals["washos"].set("root", _register_node(_root))

	# Llamar on_ready si existe.
	var on_ready = _mod_table.get("on_ready")
	if on_ready is LuaFunction:
		(on_ready as LuaFunction).invoke()

	DebugLog.log("[LuaModRunner] %s arranco (root=%s)" % [_mod_folder, root_type])
	return _root


## Crea un nodo por nombre de clase. Acepta "Node", "Control", "Node2D",
## "Node3D", "CanvasLayer", "Node2D" subclass, etc. No acepta clases
## que no sean Node (por ejemplo "RefCounted", "Resource").
func _instantiate_node(type_name: String) -> Node:
	var obj: Object = ClassDB.instantiate(type_name)
	if not (obj is Node):
		return null
	return obj as Node


func _register_node(node: Node) -> int:
	_next_node_id += 1
	_nodes_by_id[_next_node_id] = node
	return _next_node_id


func _get_node_by_id(id: Variant) -> Node:
	if not (id is int) and not (id is float):
		return null
	var key := int(id)
	if _nodes_by_id.has(key):
		return _nodes_by_id[key]
	return null


## Construye la tabla `washos` que se expone como global en el state.
## Todas las funciones tienen args sin tipar para tolerar como Lua pasa
## numeros (LuaJIT los pasa como float si son integrales, como int si
## son enteros puros). Convertimos adentro de cada funcion.
func _make_washos_table() -> LuaTable:
	var t := _state.create_table()
	t.set("log", _api_log)
	t.set("play_confirm", _api_play_confirm)
	t.set("play_scroll", _api_play_scroll)
	t.set("play_cancel", _api_play_cancel)
	t.set("create_node", _api_create_node)
	t.set("create_label", _api_create_label)
	t.set("create_button", _api_create_button)
	t.set("create_color_rect", _api_create_color_rect)
	t.set("add_child", _api_add_child)
	t.set("set_anchors_full", _api_set_anchors_full)
	t.set("set_font_size", _api_set_font_size)
	t.set("set_text", _api_set_text)
	t.set("set_position", _api_set_position)
	t.set("set_size", _api_set_size)
	t.set("set_color", _api_set_color)
	t.set("on_button_pressed", _api_on_button_pressed)
	return t


# ============================================================================
# API expuesta a Lua. Cada funcion recibe args sin tipar y devuelve
# Variant. Los ids de nodos son ints; si Lua pasa float, se trunca con
# int().
# ============================================================================

func _api_log(msg) -> void:
	DebugLog.log("[Lua:%s] %s" % [_mod_folder, str(msg)])


func _api_play_confirm() -> void:
	MenuMusic.play_confirm()


func _api_play_scroll() -> void:
	MenuMusic.play_scroll()


func _api_play_cancel() -> void:
	MenuMusic.play_cancel()


func _api_create_node(type_name) -> int:
	if not (type_name is String):
		push_warning("[Lua] create_node: falta el type_name")
		return -1
	var node := _instantiate_node(type_name)
	if node == null:
		push_warning("[Lua] create_node: '%s' no es Node" % type_name)
		return -1
	return _register_node(node)


func _api_create_label(text) -> int:
	var l := Label.new()
	l.text = str(text) if text != null else ""
	return _register_node(l)


func _api_create_button(text) -> int:
	var b := Button.new()
	b.text = str(text) if text != null else ""
	return _register_node(b)


func _api_create_color_rect(hex) -> int:
	var c := ColorRect.new()
	if hex is String:
		c.color = Color.html(hex)
	return _register_node(c)


func _api_add_child(parent_id, child_id) -> void:
	var parent := _get_node_by_id(parent_id)
	var child := _get_node_by_id(child_id)
	if parent == null or child == null:
		push_warning("[Lua] add_child: ids invalidos (%s, %s)" % [parent_id, child_id])
		return
	parent.add_child(child)


func _api_set_anchors_full(node_id) -> void:
	var n := _get_node_by_id(node_id)
	if n is Control:
		(n as Control).set_anchors_preset(Control.PRESET_FULL_RECT)


func _api_set_font_size(node_id, size) -> void:
	var n := _get_node_by_id(node_id)
	if n is Control:
		(n as Control).add_theme_font_size_override("font_size", int(size))


func _api_set_text(node_id, text) -> void:
	var n := _get_node_by_id(node_id)
	if n is Label:
		(n as Label).text = str(text)
	elif n is Button:
		(n as Button).text = str(text)


func _api_set_position(node_id, x, y) -> void:
	var n := _get_node_by_id(node_id)
	var pos := Vector2(float(x), float(y))
	if n is Control:
		(n as Control).position = pos
	elif n is Node2D:
		(n as Node2D).position = pos


func _api_set_size(node_id, w, h) -> void:
	var n := _get_node_by_id(node_id)
	if n is Control:
		(n as Control).size = Vector2(float(w), float(h))


func _api_set_color(node_id, hex) -> void:
	var n := _get_node_by_id(node_id)
	if not (hex is String):
		return
	var color := Color.html(hex)
	if n is Label:
		(n as Label).add_theme_color_override("font_color", color)
	elif n is ColorRect:
		(n as ColorRect).color = color
	elif n is Button:
		(n as Button).add_theme_color_override("font_color", color)


func _api_on_button_pressed(node_id, callback) -> void:
	var n := _get_node_by_id(node_id)
	if not (n is Button):
		push_warning("[Lua] on_button_pressed: id %s no es Button" % node_id)
		return
	if not (callback is LuaFunction):
		push_warning("[Lua] on_button_pressed: callback no es funcion Lua")
		return
	var btn := n as Button
	# Guardar el callback para que no lo libere el GC antes de tiempo.
	_button_callbacks[node_id] = callback
	var cb := callback as LuaFunction
	btn.pressed.connect(func(): cb.invoke())
