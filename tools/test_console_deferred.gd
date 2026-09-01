extends SceneTree

## La tienda no carga la consola, y todo lo que la consola necesitaba sigue
## enganchado.
##
## `console.tscn` eran 102 de los 399 recursos de la tienda y 376ms de los
## 1353ms que sumaban sus dependencias directas, sin que nada de ello estuviera
## en pantalla hasta cruzar la habitacion hasta el televisor. Sacarla dejo la
## escena en 306 recursos y su carga en escritorio en 1258ms contra 2039ms.
##
## Por que eso importa y no importaba el peso en bytes: audit_load_time.gd mide
## la tienda 1,6 veces mas pesada que Safety Lullaby aqui y trece veces mas
## lenta en el telefono, o sea que el coste que domina es POR RECURSO. Bajar la
## escena de 71,5MB a 47,3MB no movio el reloj; quitar 93 recursos es otra cosa.
##
## Lo que esta prueba vigila son las cinco formas en que esto se rompe en
## silencio, porque ninguna da un error:
##
##   - Que alguien vuelva a poner la instancia y la escena cargue console.tscn
##     otra vez, deshaciendo todo sin que se note en nada salvo el reloj.
##   - Que el nodo montado deje de llamarse `Console` o cuelgue de otro sitio.
##     Veintitres pistas de animacion dicen esa ruta literal; con otro nombre
##     resuelven a nada y la consola se queda muda.
##   - Que el .tscn empaquetado desaparezca o adelgace. Son 382 nodos con los
##     dieciseis overrides que el .tscn de la tienda le ponia encima aplanados,
##     y perder una rama son ajustes que vuelven a fabrica sin avisar.
##   - Que el cargador pierda uno de sus seis NodePath. Cada uno rehace un cable
##     que el .tscn ya no puede hacer solo.
##   - Que se cuele un `[connection]` desde la consola, que ya no existe al
##     cargar la escena y no se conectaria.
##
## Run with:
##   godot --headless --path . --script tools/test_console_deferred.gd

const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"
const CONSOLE_SHOP := "res://lullaby_mod/resources/console/console_shop.tscn"
const CONSOLE_SRC := "res://lullaby_mod/resources/console/console.tscn"
const LOADER := "res://lullaby_mod/scripts/lullaby/collectors_shop/console_deferred_loader.gd"

## Los seis cables que el cargador rehace. Ver su cabecera para que hace cada
## uno; aqui solo se comprueba que el .tscn se los da.
const WIRES: Array[String] = [
	"shop", "sequences", "focus_right_area",
	"viewport_gate", "console_sfx", "mixer_root",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var text: String = FileAccess.get_file_as_string(SHOP)
	if not _check(not text.is_empty(), "la tienda se lee"):
		_finish()
		return

	# 1. La tienda ya no depende de console.tscn - ni por ext_resource ni por
	#    ninguna otra via. Esto es lo unico que hace que los 93 recursos no se
	#    carguen; el resto de la prueba solo protege que siga funcionando.
	_check(not text.contains(CONSOLE_SRC),
		"la tienda ya no referencia console.tscn")
	var deps: PackedStringArray = ResourceLoader.get_dependencies(SHOP)
	var still: bool = false
	for dep: String in deps:
		if dep.contains("resources/console/console.tscn"):
			still = true
	_check(not still, "y tampoco sale en sus dependencias")

	# 2. El cargador, con sus seis cables.
	_check(text.contains(LOADER), "el cargador diferido esta en la escena")
	_check(text.contains('[node name="ConsoleLoader" type="Node" parent="Viewports/ConsoleSubViewport"'),
		"colgando de ConsoleSubViewport, que es donde montara la consola")
	for wire: String in WIRES:
		_check(text.contains("%s = NodePath(" % wire),
			"...con %s enganchado" % wire)

	# 3. Nadie puede conectar una senal desde un nodo que ya no esta al cargar.
	_check(not text.contains('from="Viewports/ConsoleSubViewport/Console"'),
		"ninguna conexion sale del Console, que no existe hasta montarse")

	# 4. Las pistas siguen nombrando la ruta literal, que es lo que obliga al
	#    nombre del nodo montado. Si esto llega a cero, o las animaciones se
	#    reescribieron o se perdieron.
	var tracks: int = text.count("Viewports/ConsoleSubViewport/Console")
	_check(tracks > 0,
		"las animaciones siguen nombrando la ruta que el cargador reproduce (%d)" % tracks)

	# 5. La escena empaquetada, entera.
	_check(ResourceLoader.exists(CONSOLE_SHOP), "console_shop.tscn existe")
	var packed: PackedScene = load(CONSOLE_SHOP)
	if _check(packed != null, "y se carga"):
		var node: Node = packed.instantiate()
		var n: int = _count(node)
		# 382 al extraerla. Se comprueba un suelo y no la igualdad: la consola
		# puede crecer legitimamente, pero caer a la mitad es una rama perdida.
		_check(n >= 350, "con la consola entera dentro (%d nodos)" % n)
		_check(node is Control, "y su raiz sigue siendo un Control")
		node.free()

	_kollectadex(text)

	# 6. Y la tienda sigue instanciando.
	var shop_packed: PackedScene = load(SHOP)
	if _check(shop_packed != null, "la tienda se carga"):
		var shop: Node = shop_packed.instantiate()
		_check(shop.get_node_or_null(^"Viewports/ConsoleSubViewport/ConsoleLoader") != null,
			"y trae el cargador de la consola")
		_check(shop.get_node_or_null(^"Viewports/ConsoleSubViewport/Console") == null,
			"pero NO la consola, que es el objetivo")
		_check(shop.get_node_or_null(^"Viewports/KollectadexSubViewport/KollectadexLoader") != null,
			"y el del kollectadex")
		_check(shop.get_node_or_null(^"Viewports/KollectadexSubViewport/Kollectadex") == null,
			"pero NO el kollectadex")
		shop.free()

	_finish()


## El kollectadex, diferido igual pero con dos cables en vez de cinco.
##
## Los dos apuntan al Control de DENTRO, `PanelContainer/Kollectadex`, no al
## nodo que se monta, y uno de ellos es `TouchControls.force_active_source4` -
## la entrada tactil, la unica del dispositivo. Un nulo ahi no da error: deja de
## reconocer que el menu esta abierto y los gestos van al sitio equivocado.
func _kollectadex(text: String) -> void:
	const SRC := "res://lullaby_mod/resources/kollectadex/kollectadex.tscn"
	const PACKED := "res://lullaby_mod/resources/kollectadex/kollectadex_shop.tscn"

	_check(not text.contains(SRC), "la tienda ya no referencia kollectadex.tscn")
	_check(text.contains('[node name="KollectadexLoader" type="Node" parent="Viewports/KollectadexSubViewport"'),
		"su cargador cuelga de KollectadexSubViewport")
	for wire: String in ["focus_area", "touch_controls", "kollectadex_anims"]:
		_check(text.contains("%s = NodePath(" % wire),
			"...con %s enganchado" % wire)
	_check(text.contains("Viewports/KollectadexSubViewport/Kollectadex"),
		"y las pistas siguen nombrando la ruta que reproduce")

	_check(ResourceLoader.exists(PACKED), "kollectadex_shop.tscn existe")
	var packed: PackedScene = load(PACKED)
	if _check(packed != null, "y se carga"):
		var node: Node = packed.instantiate()
		# 70 al extraerlo; suelo por si crece, alarma si pierde una rama.
		_check(_count(node) >= 60, "entero (%d nodos)" % _count(node))
		_check(node.get_node_or_null(^"PanelContainer/Kollectadex") != null,
			"y con el Control interior al que apuntan los dos cables")
		node.free()


func _count(root: Node) -> int:
	var n: int = 1
	for child in root.get_children():
		n += _count(child)
	return n


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - la tienda entra sin la consola y la consola llega despues")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
