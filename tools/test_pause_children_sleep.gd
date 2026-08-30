extends SceneTree

## Los hijos del menú de pausa duermen mientras está cerrado, y el menú NO.
##
## La instrumentación de regiones lo cazó en el dispositivo:
##
##     ChimeraPause=0.36/0.61  37/37 ocultos
##
## Treinta y siete de treinta y siete nodos procesando con el menú cerrado. No
## por descuido de nadie: el nodo del script lleva `process_mode = ALWAYS` en la
## escena porque `_input()` tiene que oír la tecla de pausa mientras el árbol
## está en `get_tree().paused = true`, y los hijos heredan ese ALWAYS.
##
## Lo que esta prueba protege es la distinción, que es donde está todo el
## riesgo: se duermen los HIJOS y nunca el nodo del script. Apagarlo a él
## ahorraría lo mismo y dejaría el juego sin poder pausarse - un fallo que no da
## ningún error y que solo se descubre pulsando pausa.
##
## Run with:
##   godot --headless --path . --script tools/test_pause_children_sleep.gd

const MENU := "res://lullaby_mod/scripts/lullaby/menus/chimera_pause_menu.gd"
const SCENE := "res://lullaby_mod/resources/funkin/ui/pause/chimera/pause_chimera.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(SCENE) as PackedScene
	if not _check(packed != null, "la escena del menu de pausa carga"):
		_finish()
		return

	var menu: Node = packed.instantiate()
	root.add_child(menu)
	await process_frame

	# El nodo con el script, que es el ColorRect y no el CanvasLayer.
	var script_node: Node = null
	var stack: Array[Node] = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and n.has_method("resume"):
			script_node = n
			break
		for c: Node in n.get_children():
			stack.append(c)

	if not _check(script_node != null, "se encuentra el nodo del script"):
		menu.free()
		_finish()
		return

	_check(script_node.process_mode == Node.PROCESS_MODE_ALWAYS,
		"el menu sigue en ALWAYS, o se queda sordo con el arbol pausado (%d)"
			% script_node.process_mode)

	var kids: Array[Node] = script_node.get_children()
	_check(kids.size() > 0, "tiene hijos que dormir (%d)" % kids.size())

	var dormidos: int = 0
	for c: Node in kids:
		if c.process_mode == Node.PROCESS_MODE_DISABLED:
			dormidos += 1
	_check(dormidos == kids.size(),
		"cerrado: los %d hijos estan dormidos (%d)" % [kids.size(), dormidos])

	# Y al abrirlo vuelven, o el menu sale sin reaccionar a nada.
	script_node.call("_set_children_processing", true)
	var despiertos: int = 0
	for c: Node in kids:
		if c.process_mode != Node.PROCESS_MODE_DISABLED:
			despiertos += 1
	_check(despiertos == kids.size(),
		"abierto: los %d vuelven (%d)" % [kids.size(), despiertos])
	_check(script_node.process_mode == Node.PROCESS_MODE_ALWAYS,
		"y el menu no se toco en ningun momento")

	menu.free()
	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - duermen los hijos, no el menu")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
