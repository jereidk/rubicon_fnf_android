extends Node

## Carga la consola DESPUES de que la tienda este en pantalla, no antes.
##
## `console.tscn` son 102 de los 399 recursos de la tienda y 376ms de los 1353ms
## que suman sus dependencias directas - un 28% - medido con
## tools/audit_load_time.gd. Nada de eso se ve hasta que el jugador camina hasta
## el televisor, que esta al otro lado de la habitacion.
##
## Que eso importe y no importe el peso en bytes viene de la unica medida que
## explica la carga de esta escena. La misma herramienta, dos escenas:
##
##     escritorio   Safety Lullaby 1.280ms   tienda 2.039ms   -> 1,6x
##     telefono     Safety Lullaby 2.831ms   tienda 37.790ms  -> 13,3x
##
## La tienda pesa 1,6 veces mas y el telefono tarda trece. El factor que sobra
## no esta en la escena: es trabajo POR RECURSO que el dispositivo hace y el
## escritorio no. Por eso bajar la tienda de 71,5MB a 47,3MB dejo el reloj
## exactamente igual, y por eso quitar recursos de la cuenta es lo unico que
## queda.
##
## Se carga en segundo plano en cuanto la escena arranca, no al acercarse a la
## TV. Las dos cosas quitan los 102 recursos de la carga inicial, pero esperar
## al area de foco pondria el coste justo cuando el jugador llega - y con un
## `load_threaded_request` desde el primer fotograma la consola esta montada
## mucho antes de que nadie cruce la habitacion, sin un solo tiron.
##
## Lo que este nodo tiene que rehacer a mano, enumerado del .tscn de la tienda
## antes de sacarla, porque cada uno es una forma distinta de romperse en
## silencio:
##
##   1. `console` en el script de la tienda - ya tolera null en sus tres usos,
##      que es lo que hace viable todo esto.
##   2. `shop`, `sequences` y `focus_right_area`, exports de la consola que
##      apuntan FUERA de ella. Un NodePath exportado se resuelve al instanciar,
##      cuando el nodo aun no esta en el arbol, asi que llegan nulos siempre.
##   3. `nested_containers` de console_viewport_gate.gd, que viven dentro de la
##      consola y son lo que apaga sus SubViewport anidados.
##   4. La conexion `play_sound` -> ConsoleSFX._on_console_play_sound, la unica
##      de las trece del .tscn que tocaba la consola.
##   5. Las ocho pistas de animacion que la nombran. AnimationMixer cachea rutas
##      y no recachea porque aparezca un nodo, asi que hay que decirselo.

## La escena empaquetada por tools/extract_console_scene.gd.
##
## Es la consola CON los dieciseis overrides que el .tscn de la tienda le ponia
## encima, aplanados. Deliberadamente no es una instancia de console.tscn: los
## overrides no sobreviven a una instancia creada en tiempo de ejecucion, y
## perderlos habria devuelto los ajustes a fabrica sin dar un error. El precio
## es que un cambio en console.tscn ya no se propaga solo; se regenera con la
## herramienta.
const CONSOLE_SCENE := "res://lullaby_mod/resources/console/console_shop.tscn"

## El nombre importa: las ocho pistas de animacion y el NodePath exportado de la
## tienda dicen `Viewports/ConsoleSubViewport/Console`, asi que el nodo montado
## tiene que llamarse exactamente asi y colgar exactamente de ahi.
const NODE_NAME := &"Console"

@export var shop: Node
@export var sequences: Node
@export var focus_right_area: Node
@export var viewport_gate: Node
@export var console_sfx: Node

## La raiz desde la que buscar AnimationMixer a los que vaciar la cache.
##
## Se buscan en vez de listarse porque las pistas que nombran la consola viven
## dentro de `[sub_resource type="Animation"]`, y remontar de ahi a que
## AnimationPlayer las posee es fragil - una biblioteca de animaciones de por
## medio y el enlace se pierde. Vaciar la cache de un mixer que no la nombra no
## cuesta nada y es idempotente, asi que barrerlos todos es mas barato que
## acertar cuales son y mucho mas dificil de romper al editar la escena.
@export var mixer_root: Node

var _requested: bool = false
var _done: bool = false


func _ready() -> void:
	# PROCESS_MODE_ALWAYS: la tienda arranca con secuencias que pausan el arbol,
	# y una carga a medias que deja de sondearse no termina nunca.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.load_threaded_request(CONSOLE_SCENE) == OK:
		_requested = true
	else:
		push_warning("console_deferred_loader: no pude pedir %s" % CONSOLE_SCENE)
		_done = true


func _process(_delta: float) -> void:
	if _done or not _requested:
		return
	var status: int = ResourceLoader.load_threaded_get_status(CONSOLE_SCENE)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_done = true
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_warning("console_deferred_loader: %s fallo (%d)" % [CONSOLE_SCENE, status])
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(CONSOLE_SCENE)
	if packed != null:
		_mount(packed)


## Monta la consola y rehace los cinco cables.
func _mount(packed: PackedScene) -> void:
	var host: Node = get_parent()
	if host == null or host.has_node(NodePath(NODE_NAME)):
		return

	var console: Node = packed.instantiate()
	console.name = NODE_NAME

	# Los exports de la consola ANTES de meterla en el arbol, para que su
	# `_ready()` los encuentre puestos y no tenga que defenderse de nulos.
	_assign(console, "shop", shop)
	_assign(console, "sequences", sequences)
	_assign(console, "focus_right_area", focus_right_area)

	host.add_child(console)

	if shop != null and "console" in shop:
		shop.set("console", console)

	if console_sfx != null and console_sfx.has_method("_on_console_play_sound") \
			and console.has_signal("play_sound") \
			and not console.is_connected("play_sound", Callable(console_sfx, "_on_console_play_sound")):
		console.connect("play_sound", Callable(console_sfx, "_on_console_play_sound"))

	_rewire_gate(console)

	# Y las caches. Sin esto las ocho pistas siguen apuntando a un nodo que no
	# existia cuando el mixer las resolvio, y la consola se queda sin musica y
	# sin `input_active` sin decir nada.
	_clear_mixer_caches(mixer_root if mixer_root != null else shop)

	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node != null and log_node.has_method("mark"):
		log_node.call("mark", "console montada en diferido (%d nodos)" % _count(console))


## `nested_containers` del gate son SubViewportContainer que viven DENTRO de la
## consola, asi que se resuelven aqui y no en el .tscn. Las rutas son las dos
## que el propio gate documenta: el fondo y los iconos de la pestana Home.
func _rewire_gate(console: Node) -> void:
	if viewport_gate == null or not is_instance_valid(viewport_gate):
		return
	if not ("nested_containers" in viewport_gate):
		return
	var found: Array[Control] = []
	for path: String in [
		"console_bg/Control/SubViewportContainer",
		"TabContainer/Home/IconSubViewport",
		"TabContainer/Credits/CreditsSubViewport",
	]:
		var node: Node = console.get_node_or_null(NodePath(path))
		if node is Control:
			found.append(node as Control)
	viewport_gate.set("nested_containers", found)


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
	if value != null and prop in node:
		node.set(prop, value)


func _count(root: Node) -> int:
	var n: int = 1
	for child in root.get_children():
		n += _count(child)
	return n
