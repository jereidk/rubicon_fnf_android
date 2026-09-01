extends Node

## Carga el kollectadex DESPUES de que la tienda este en pantalla.
##
## Mismo motivo y mismo mecanismo que console_deferred_loader.gd: el coste de
## cargar esta escena es POR RECURSO -audit_load_time.gd la mide 1,6 veces mas
## pesada que Safety Lullaby en escritorio y trece veces mas lenta en el
## telefono- asi que quitar recursos de la carga inicial es lo unico que mueve
## el reloj. El kollectadex son 27 recursos y 30,5ms de las dependencias
## directas, dentro de un SubViewport que nadie mira hasta cruzar la habitacion.
##
## Deliberadamente NO se generalizo con el de la consola en un solo script. Los
## dos montan un subarbol empaquetado, pero lo que rehacen despues no se parece:
## la consola reengancha cinco cables incluyendo una senal, este reengancha dos
## que ademas apuntan a un nodo INTERIOR y no a la raiz montada. Un cargador
## generico con listas de propiedades esconderia justo eso, que es la parte que
## se rompe en silencio.
##
## Los cables, enumerados del .tscn antes de cortar:
##
##   1. `FocusKollectadex.kollectadex` - el area que abre el menu.
##   2. `TouchControls.force_active_source4` - la entrada tactil, que es la
##      UNICA entrada del dispositivo. Un nulo aqui no da error: deja de
##      reconocer que el kollectadex esta abierto y los gestos se van al sitio
##      equivocado.
##
## Los dos apuntan a `Kollectadex/PanelContainer/Kollectadex`, el Control de
## dentro, no al nodo que se monta. De ahi INNER_PATH.
##
## Y los tres exports del propio nodo interior -`sequences`, `focus_left_area`,
## `kollectadex_anims`- apuntan fuera de el, asi que se resuelven al instanciar,
## cuando aun no esta en el arbol, y llegan nulos siempre.

const SCENE := "res://lullaby_mod/resources/kollectadex/kollectadex_shop.tscn"

## Las 52 menciones del .tscn dicen esta ruta literal
## (`Viewports/KollectadexSubViewport/Kollectadex/...`), asi que el nodo montado
## tiene que llamarse asi y colgar de donde cuelga este cargador.
const NODE_NAME := &"Kollectadex"

## El Control de dentro al que apuntan los dos cables externos.
const INNER_PATH := "PanelContainer/Kollectadex"

@export var focus_area: Node
@export var touch_controls: Node
@export var sequences: Node
@export var focus_left_area: Node
@export var kollectadex_anims: Node
@export var mixer_root: Node

var _requested: bool = false
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.load_threaded_request(SCENE) == OK:
		_requested = true
	else:
		push_warning("kollectadex_deferred_loader: no pude pedir %s" % SCENE)
		_done = true


func _process(_delta: float) -> void:
	if _done or not _requested:
		return
	var status: int = ResourceLoader.load_threaded_get_status(SCENE)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_done = true
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_warning("kollectadex_deferred_loader: %s fallo (%d)" % [SCENE, status])
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(SCENE)
	if packed != null:
		_mount(packed)


func _mount(packed: PackedScene) -> void:
	var host: Node = get_parent()
	if host == null or host.has_node(NodePath(NODE_NAME)):
		return

	var root: Node = packed.instantiate()
	root.name = NODE_NAME

	var inner: Node = root.get_node_or_null(NodePath(INNER_PATH))
	if inner == null:
		push_warning("kollectadex_deferred_loader: no encuentro %s" % INNER_PATH)

	# Antes de entrar al arbol, para que el `_ready()` del interior los tenga.
	if inner != null:
		_assign(inner, "sequences", sequences)
		_assign(inner, "focus_left_area", focus_left_area)
		_assign(inner, "kollectadex_anims", kollectadex_anims)

	host.add_child(root)

	if inner != null:
		_assign(focus_area, "kollectadex", inner)
		_assign(touch_controls, "force_active_source4", inner)

	_clear_mixer_caches(mixer_root)

	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node != null and log_node.has_method("mark"):
		log_node.call("mark", "kollectadex montado en diferido (%d nodos)" % _count(root))


func _clear_mixer_caches(root: Node) -> void:
	if root == null:
		return
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is AnimationMixer:
			(node as AnimationMixer).clear_caches()


func _assign(node: Node, prop: String, value: Node) -> void:
	if node != null and is_instance_valid(node) and value != null and prop in node:
		node.set(prop, value)


func _count(root: Node) -> int:
	var n: int = 1
	for child in root.get_children():
		n += _count(child)
	return n
