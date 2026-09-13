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
##   1. SEIS NodePath exportados que apuntaban al Console. La primera version de
##      este fichero reengancho dos y dio la lista por cerrada; los otros cuatro
##      estan enumerados sobre sus @export mas abajo. Ninguno da error al
##      faltar - la consola simplemente deja de abrirse y el tacto se
##      desorienta. El guard los cuenta ahora sobre el .tscn en vez de fiarse.
##   2. `shop`, `sequences` y `focus_right_area`, exports de la consola que
##      apuntan FUERA de ella. Un NodePath exportado se resuelve al instanciar,
##      cuando el nodo aun no esta en el arbol, asi que llegan nulos siempre.
##   3. `nested_containers` de console_viewport_gate.gd, que viven dentro de la
##      consola y son lo que apaga sus SubViewport anidados.
##   4. La conexion `play_sound` -> ConsoleSFX._on_console_play_sound, la unica
##      de las trece del .tscn que tocaba la consola.
##   5. Las pistas de animacion que la nombran. AnimationMixer cachea rutas y no
##      recachea porque aparezca un nodo, asi que hay que decirselo.

## La consola con los overrides que el .tscn de la tienda le ponia encima.
##
## Es una INSTANCIA de console.tscn con 19 bloques de override, generada por
## tools/gen_deferred_overrides.py desde el .tscn de la tienda de antes de sacar
## la consola. 8 KB.
##
## La primera version era otra cosa - un aplanado de 1,26 MB hecho con
## `PackedScene.pack()` sobre el subarbol vivo - y esta escrito aqui porque el
## razonamiento que lo eligio era plausible y era falso. Decia: los overrides no
## sobreviven a una instancia creada en tiempo de ejecucion, asi que hay que
## aplanar. No hace falta. Un .tscn que instancia otro y le pone propiedades
## encima es exactamente lo que la tienda ya tenia, y Godot lo resuelve solo.
##
## Lo que costo aplanar, medido:
##
##   1. Un NodePath que sale del subarbol no se puede serializar, y `pack()` lo
##      escribe como `NodePath("")` sin avisar. Corto seis cables. Tres se
##      quedaron sin reenganchar y en el dispositivo eso fue el boton Cartuchos
##      sin hacer nada y la cancion sin arrancar.
##   2. El estado EN VIVO se serializa como si fuera autoria: dos
##      `animation = &""` que hacian petar set_animation al instanciar.
##   3. Los hijos de cada subescena instanciada se reescriben SIN `index=`, y sin
##      `index` Godot los anade en vez de sobreescribirlos:
##
##          console.tscn        382 nodos    0 padres con hijos repetidos
##          console_shop.tscn   582 nodos   43 padres,  68 hijos sobrantes
##
##      Dos marcas de verificacion una sobre otra en cada toggle de la consola.
##   4. Y de ahi 200 nodos de mas, que se pagan al montar:
##      `console montada en diferido (515 nodos) proc=1757.82ms`.
##
## Nada de eso daba un error. La equivalencia con la consola inline original la
## comprueba ahora tools/verify_deferred_overrides.gd - mismo arbol, mismas
## propiedades, mismos NodePath internos - que es la comparacion que la
## herramienta anterior no hacia: comparaba el arbol vivo contra si mismo.
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

## Los OTROS cuatro que tenian un NodePath exportado hacia el Console.
##
## La primera version de este fichero reengancho `CollectorShop.console` y el
## gate, y dio por cerrada la lista. Eran seis. Contadas sobre el .tscn con las
## pistas de animacion descartadas, las que faltaban son estas cuatro, y
## ninguna habria dado un error - solo dejan de funcionar:
##
##   FocusConsole.console               el area que ABRE la consola
##   FocusPowerConsole.console          el area del boton de encendido
##   TouchControls.force_active_source  la entrada tactil, la unica que hay
##   SwitchCartridgeButton.visible_source  se muestra segun la consola
##
## Todas apuntan al Console entero y todas guardan la propiedad `console` menos
## la ultima, asi que van con su nombre al lado en vez de asumirlo.
@export var focus_console: Node
@export var focus_power_console: Node
@export var touch_controls: Node
@export var switch_cartridge_button: Node

## Los nodos de la TIENDA que tres @export de DENTRO de la consola necesitan.
##
## Esta es la mitad que la primera version de este fichero no vio, y la que
## rompio la build 10249-e93c8ca2. El comentario de arriba enumera los cables
## que van HACIA la consola; estos van AL CONTRARIO, desde un nodo hondo dentro
## de ella hacia la tienda, y no estaban en console.tscn: eran overrides del
## .tscn de la tienda, que es por donde se colaron.
##
## Los tres, copiados del .tscn de antes de sacar la consola (1dcde58b~1):
##
##   TabContainer/Home/FakeButtons/Cartridges.bag_area
##       -> Environment/Areas/FocusCartridgeBag
##   TabContainer/Home/FakeButtons/Cartridges.handler
##       -> CartridgeBag/CartridgeBagHandler
##   TabContainer/Cartridges/EnterLabel.collector_shop
##       -> la raiz de la tienda (se reusa `shop`)
##
## Como fallan: `cartridges_button.gd` hace `if handler:` y `if bag_area:`, asi
## que el boton Cartuchos de la consola no da ningun error - simplemente no
## hace nada al pulsarlo. Y `cartridges_enter_label.gd:48` no se defiende, asi
## que entrar a una cancion peta con "Invalid access to property or key
## 'sequence_controller' on a base object of type 'Nil'" y la cancion no
## arranca nunca.
##
## Por que `pack()` los perdio en silencio: un NodePath que apunta FUERA del
## subarbol empaquetado no se puede serializar, asi que se escribe como
## `NodePath("")`. No hay aviso. Eso da el detector exacto que
## test_console_deferred.gd usa ahora: cada `NodePath("")` de
## console_shop.tscn tiene que estar reenganchado aqui.
@export var cartridge_bag_area: Node
@export var cartridge_bag_handler: Node

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


## Monta la consola y rehace todos los cables.
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

	# Y los tres de dentro, tambien antes de entrar al arbol: el `_ready()` de
	# EnterLabel no los usa, pero el de un boton futuro si podria, y ponerlos
	# despues seria confiar en que nadie lo haga.
	_assign_inner(console, "TabContainer/Home/FakeButtons/Cartridges",
		"bag_area", cartridge_bag_area)
	_assign_inner(console, "TabContainer/Home/FakeButtons/Cartridges",
		"handler", cartridge_bag_handler)
	_assign_inner(console, "TabContainer/Cartridges/EnterLabel",
		"collector_shop", shop)

	host.add_child(console)

	_assign(shop, "console", console)
	_assign(focus_console, "console", console)
	_assign(focus_power_console, "console", console)
	_assign(touch_controls, "force_active_source", console)
	_assign(switch_cartridge_button, "visible_source", console)

	if console_sfx != null and console_sfx.has_method("_on_console_play_sound") \
			and console.has_signal("play_sound") \
			and not console.is_connected("play_sound", Callable(console_sfx, "_on_console_play_sound")):
		console.connect("play_sound", Callable(console_sfx, "_on_console_play_sound"))

	# `power_console.gd` tiene que volver a aplicar lo que su `_ready()` no pudo:
	# corre mucho antes de que la consola exista, y su primer uso de `console`
	# aborta la funcion, asi que la luz de la TV, el indicador y la musica se
	# quedaron sin poner. Ver apply_console_state() alli.
	if focus_power_console != null and is_instance_valid(focus_power_console) \
			and focus_power_console.has_method("apply_console_state"):
		focus_power_console.call("apply_console_state")

	_rewire_gate(console)

	# Y las caches. Sin esto las ocho pistas siguen apuntando a un nodo que no
	# existia cuando el mixer las resolvio, y la consola se queda sin musica y
	# sin `input_active` sin decir nada.
	_clear_mixer_caches(mixer_root if mixer_root != null else shop)

	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node != null and log_node.has_method("mark"):
		log_node.call("mark", "console montada en diferido (%d nodos)" % _count(console))


## `nested_containers` del gate son SubViewportContainer que viven DENTRO de la
## consola, asi que se resuelven aqui y no en el .tscn. Son TRES y estan
## copiadas del array que el .tscn tenia antes de sacar la consola, no de la
## memoria: la primera version puso `TabContainer/Credits/CreditsSubViewport`
## de cabeza y la real es `TabContainer/Credits/CurrentlySelected/
## SubViewportContainer`, con lo que ese viewport anidado no se habria apagado
## nunca y nadie se habria enterado.
func _rewire_gate(console: Node) -> void:
	if viewport_gate == null or not is_instance_valid(viewport_gate):
		return
	if not ("nested_containers" in viewport_gate):
		return
	var found: Array[Control] = []
	for path: String in [
		"console_bg/Control/SubViewportContainer",
		"TabContainer/Home/IconSubViewport",
		"TabContainer/Credits/CurrentlySelected/SubViewportContainer",
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
	if node != null and is_instance_valid(node) and value != null and prop in node:
		node.set(prop, value)


## Como _assign() pero sobre un descendiente de la consola, buscado por ruta.
##
## Avisa si la ruta no existe, al contrario que _assign(). Un `@export` que se
## queda sin poner es el fallo silencioso de este fichero entero, y estas tres
## rutas son literales escritas a mano: renombrar una pestaña de la consola las
## rompe sin que nada mas se entere.
func _assign_inner(console: Node, path: String, prop: String, value: Node) -> void:
	var node: Node = console.get_node_or_null(NodePath(path))
	if node == null:
		push_warning("console_deferred_loader: no existe %s (para .%s)" % [path, prop])
		return
	if not (prop in node):
		push_warning("console_deferred_loader: %s no tiene .%s" % [path, prop])
		return
	if value == null:
		push_warning("console_deferred_loader: %s.%s se queda sin poner" % [path, prop])
		return
	node.set(prop, value)


func _count(root: Node) -> int:
	var n: int = 1
	for child in root.get_children():
		n += _count(child)
	return n
