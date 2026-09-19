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
##
## ACCESO DINAMICO A LOS TIPOS DEL ADDON:
##
## El addon lua-gdextension expone las clases LuaState, LuaTable,
## LuaError, LuaFunction. En Android, el .so se carga y las clases
## existen. En el editor headless del CI Linux NO, porque solo
## empaquetamos el .so de Android arm64. Sin las clases registradas,
## mencionar sus nombres como tipos (`var x: LuaState`) hace que el
## parser de GDScript falle con "Identifier not declared".
##
## Solucion: cero referencias a los tipos en el codigo. Todo se hace
## via ClassDB (instanciar, consultar constantes) y via get_class()
## (comparar nombres de clase como strings). El script parsea en
## cualquier plataforma; si el addon no esta cargado, run() sale con
## error en runtime pero no rompe el editor.

const LUA_STATE_CLASS := "LuaState"
const LUA_TABLE_CLASS := "LuaTable"
const LUA_ERROR_CLASS := "LuaError"
const LUA_FUNCTION_CLASS := "LuaFunction"

## Librerias del addon que abrimos en el sandbox. Se consultan sus
## bitmasks via ClassDB.class_get_integer_constant para no hardcodear
## los valores (pueden cambiar si el addon cambia).
const LUA_LIBS_TO_OPEN: Array[String] = [
	"LUA_BASE",
	"LUA_TABLE",
	"LUA_STRING",
	"LUA_MATH",
	"LUA_COROUTINE",
	"LUA_PACKAGE",
]

var _state: Object = null
var _root: Node = null
## LuaTable (sin tipo - la clase puede no existir en CI Linux).
var _mod_table = null
var _mod_folder: String = ""
## Nodos creados por el mod. Lua los manipula indirectamente via ids.
var _nodes_by_id: Dictionary = {}
var _next_node_id: int = 0
## Callbacks de botones: id -> LuaFunction. Guardados para que el GC
## no los libere mientras el boton existe.
var _button_callbacks: Dictionary = {}


func run(mod: Dictionary, scene_path: String) -> Node:
	_mod_folder = str(mod.get("folder", "?"))

	# El addon solo esta cargado si el .so de esta plataforma existe.
	# En Android si, en el CI Linux no. Si no esta, salimos con error
	# limpio en vez de crashear.
	if not ClassDB.class_exists(LUA_STATE_CLASS):
		push_error("[LuaModRunner] %s no esta registrado (addon lua-gdextension no cargado para esta plataforma?)" % LUA_STATE_CLASS)
		return null

	_state = ClassDB.instantiate(LUA_STATE_CLASS)
	if _state == null:
		push_error("[LuaModRunner] no pude instanciar %s" % LUA_STATE_CLASS)
		return null

	# Construir el bitmask de librerias dinamicamente.
	var lib_mask: int = 0
	for const_name in LUA_LIBS_TO_OPEN:
		var val = ClassDB.class_get_integer_constant(LUA_STATE_CLASS, const_name)
		if val == null:
			push_warning("[LuaModRunner] %s.%s no existe" % [LUA_STATE_CLASS, const_name])
			continue
		lib_mask |= int(val)
	_state.open_libraries(lib_mask)

	# Inyectar la tabla washos en globals.
	var globals = _state.globals
	if globals == null:
		push_error("[LuaModRunner] _state.globals es null")
		return null
	globals.set("washos", _make_washos_table())

	# Cargar el chunk del .lua.
	var loaded = _state.load_file(scene_path)
	if loaded == null:
		push_error("[LuaModRunner] load_file(%s) devolvio null" % scene_path)
		return null

	var loaded_class: String = loaded.get_class()
	if loaded_class == LUA_ERROR_CLASS:
		push_error("[LuaModRunner] load_file(%s) fallo: %s" % [scene_path, str(loaded)])
		return null
	if loaded_class != LUA_FUNCTION_CLASS:
		push_error("[LuaModRunner] load_file(%s) devolvio %s, esperaba %s" % [
			scene_path, loaded_class, LUA_FUNCTION_CLASS,
		])
		return null

	# Ejecutar el chunk.
	_mod_table = loaded.invoke()
	if _mod_table == null:
		push_error("[LuaModRunner] el chunk de %s no devolvio nada" % scene_path)
		return null
	if _mod_table.get_class() != LUA_TABLE_CLASS:
		push_error("[LuaModRunner] el chunk devolvio %s, esperaba %s" % [
			_mod_table.get_class(), LUA_TABLE_CLASS,
		])
		return null

	# Leer root_type (default "Node").
	var root_type: String = "Node"
	var rt = _mod_table.get("root_type")
	if rt != null and rt is String:
		root_type = rt

	# Crear nodo raiz.
	_root = _instantiate_node(root_type)
	if _root == null:
		push_error("[LuaModRunner] root_type '%s' no es un Node valido" % root_type)
		return null

	# Exponer el id del nodo raiz al mod.
	var washos_table = globals.get("washos")
	if washos_table != null:
		washos_table.set("root", _register_node(_root))

	# Llamar on_ready si existe.
	var on_ready = _mod_table.get("on_ready")
	if on_ready != null and on_ready.get_class() == LUA_FUNCTION_CLASS:
		on_ready.invoke()

	DebugLog.log("[LuaModRunner] %s arranco (root=%s)" % [_mod_folder, root_type])
	return _root


## Crea un nodo por nombre de clase. Acepta "Node", "Control", "Node2D",
## "Node3D", "CanvasLayer", subclases, etc. No acepta clases que no
## hereden de Node.
func _instantiate_node(type_name: String) -> Node:
	if not ClassDB.class_exists(type_name):
		return null
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


## Construye la tabla `washos` que se expone como global.
## Todas las funciones tienen args sin tipar para tolerar como Lua pasa
## numeros (LuaJIT pasa integrales como float si son grandes). La
## conversion a int/float se hace adentro de cada funcion.
func _make_washos_table():
	var t = _state.create_table()
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
		push_warning("[Lua] create_node: '%s' no es Node valido" % type_name)
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
	if callback == null or callback.get_class() != LUA_FUNCTION_CLASS:
		push_warning("[Lua] on_button_pressed: callback no es funcion Lua")
		return
	var btn := n as Button
	# Guardar el callback para que el GC no lo libere mientras el
	# boton existe.
	_button_callbacks[node_id] = callback
	var cb = callback
	btn.pressed.connect(func(): cb.invoke())
