extends SceneTree

## Saca el subarbol `Viewports/ConsoleSubViewport/Console` de la tienda a su
## propio .tscn, para poder cargarlo cuando el jugador se acerca a la TV en vez
## de al entrar a la habitacion.
##
## Por que hace falta empaquetar y no mover a mano: el nodo `Console` de
## `env_collector_shop.tscn` es una INSTANCIA de `resources/console/console.tscn`
## con DIECISEIS nodos de override encima - TabContainer, Home, los iconos 3D,
## Cartridges, SettingsSubmenu, Downscroll, GhostTapping, BabyMode y demas.
## Esos overrides viven en el .tscn de la tienda, no en console.tscn, asi que
## cambiar la instancia por una carga en tiempo de ejecucion los perderia todos
## en silencio: ajustes que vuelven a su valor de fabrica y botones que
## desaparecen, sin un solo error.
##
## `PackedScene.pack()` sobre el nodo YA INSTANCIADO serializa lo que hay
## montado, overrides incluidos, asi que el resultado es equivalente por
## construccion. Lo que se pierde a cambio, y hay que saberlo: la escena
## resultante deja de ser una instancia de console.tscn, o sea que un cambio
## futuro en console.tscn ya no se propaga solo. Es el precio de esta ruta y es
## reversible - borrar el .tscn generado y volver a poner la instancia.
##
## Por que un recurso de 102 dependencias: audit_load_time.gd las cronometra en
## 376ms de los 1353ms que suman todas las dependencias directas de la tienda -
## un 28% - y son 102 de sus 399 recursos. Nada de eso esta en pantalla hasta
## que el jugador camina hasta el televisor.
##
## Verifica antes de escribir: cuenta nodos, clases y rutas del original contra
## el empaquetado, y se niega a guardar si no coinciden. Una extraccion que
## pierde una rama es exactamente el fallo silencioso que esto existe para
## evitar.
##
## Run with:
##   godot --headless --path . --script tools/extract_console_scene.gd

const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"

## Que sacar y adonde. Argumentos por linea de comandos para que el segundo
## subarbol no cueste una copia del fichero: la consola fue el primero, el
## kollectadex el segundo, y el procedimiento es el mismo.
##   godot --headless --path . --script tools/extract_console_scene.gd -- \
##       Viewports/KollectadexSubViewport/Kollectadex \
##       res://lullaby_mod/resources/kollectadex/kollectadex_shop.tscn
const DEFAULT_NODE_PATH := "Viewports/ConsoleSubViewport/Console"
const DEFAULT_OUT := "res://lullaby_mod/resources/console/console_shop.tscn"


func _initialize() -> void:
	var node_path: String = DEFAULT_NODE_PATH
	var out_path: String = DEFAULT_OUT
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 2:
		node_path = args[0]
		out_path = args[1]

	var packed: PackedScene = load(SHOP)
	if packed == null:
		printerr("no se pudo cargar la tienda")
		quit(1)
		return
	var shop: Node = packed.instantiate()

	var console: Node = shop.get_node_or_null(NodePath(node_path))
	if console == null:
		printerr("no existe %s en la tienda" % node_path)
		quit(1)
		return

	var before: Dictionary = _describe(console)
	print("original   : %d nodos" % before["n"])

	# `pack()` solo guarda los nodos cuyo owner es el nodo raiz que se empaqueta.
	# Al venir de otra escena, los hijos tienen como owner a la tienda, asi que
	# hay que reasignarlos - sin esto sale un .tscn con un unico nodo y ningun
	# error.
	console.get_parent().remove_child(console)
	_own(console, console)

	var out := PackedScene.new()
	var err: int = out.pack(console)
	if err != OK:
		printerr("pack() fallo: %d" % err)
		quit(1)
		return

	var rebuilt: Node = out.instantiate()
	var after: Dictionary = _describe(rebuilt)
	print("empaquetado: %d nodos" % after["n"])

	var ok: bool = true
	if before["n"] != after["n"]:
		printerr("FALLO: %d nodos contra %d" % [before["n"], after["n"]])
		ok = false
	for key: String in before["paths"]:
		if not after["paths"].has(key):
			printerr("FALLO: falta %s" % key)
			ok = false
		elif before["paths"][key] != after["paths"][key]:
			printerr("FALLO: %s era %s y ahora %s" % [key, before["paths"][key], after["paths"][key]])
			ok = false
	for key: String in after["paths"]:
		if not before["paths"].has(key):
			printerr("FALLO: sobra %s" % key)
			ok = false

	if not ok:
		printerr("no se escribe nada")
		quit(1)
		return

	err = ResourceSaver.save(out, out_path)
	if err != OK:
		printerr("no se pudo guardar %s: %d" % [out_path, err])
		quit(1)
		return
	print("guardado   : %s" % out_path)
	print("todo OK - mismos nodos, mismas clases, mismas rutas")
	quit(0)


## Reasigna el owner de todo el subarbol, que es lo que decide que guarda pack().
func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)


## Ruta -> clase, para cada nodo del subarbol. Comparar el conjunto entero
## detecta tanto una rama perdida como una que cambia de tipo.
func _describe(root: Node) -> Dictionary:
	var paths: Dictionary = {}
	var stack: Array = [[root, ""]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var prefix: String = item[1]
		var here: String = prefix if prefix.is_empty() else prefix
		for child in node.get_children():
			var p: String = (here + "/" if not here.is_empty() else "") + String(child.name)
			paths[p] = child.get_class()
			stack.append([child, p])
	return {"n": paths.size() + 1, "paths": paths}
