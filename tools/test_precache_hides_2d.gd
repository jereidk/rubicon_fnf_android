extends SceneTree

## El precache esconde tambien el 2D, y lo reparte como el 3D.
##
## `_hide_everything()` fue durante un mes una pasada solo de VisualInstance3D.
## El log del dispositivo 10232-4a0da0d1 (moto g53, instalacion en frio) mide lo
## que quedaba fuera, en el fotograma que va desde que esa funcion termina hasta
## el primer _process de la camara:
##
##     [66.35s] precache started   pipe=58    2d=8/270/73     3d=0/0/0
##     [77.24s] ready+drawn        pipe=149   2d=31/2398/110  3d=0/0/0
##
## 10,9 segundos y +91 pipelines, con el pase 3D dibujando CERO objetos las dos
## veces: los 116 nodos 3D estaban escondidos y esa mitad funcionaba. Las 89
## pipelines `surf` son de los 37 canvas items nuevos - la UI - compiladas todas
## en el unico fotograma que nadie reparte, el primer dibujo de la escena.
##
## Y que el coste sea compilar y no dibujar lo cierra el log dos fotogramas mas
## tarde: `cpu_render=9371.44ms` con `gpu=8.01ms`. Es el driver compilando
## SPIR-V en la CPU, a ~110ms por `surf` en frio contra los ~11ms en caliente.
##
## Se comprueba contra la ESCENA DE VERDAD y no contra un arbol de mentira,
## porque lo que hay que demostrar es que la tienda concreta que se colgaba
## entrega sus canvas items al reparto. Un arbol inventado demuestra que el
## `if` funciona, que no es lo que fallaba.
##
## Run with:
##   godot --headless --path . --script tools/test_precache_hides_2d.gd

const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"
const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"

## La unica pista `:visible` 2D de la tienda. Las otras cinco de la escena son
## 3D y llevan desde siempre pisadas por esta pasada; ver
## `_nodes_with_animated_visibility()` para por que la exencion es solo del 2D.
const ANIMATED_2D := "UI/CameraShader"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var script: GDScript = load(CAMERA)
	if not _check(script != null, "el script de la camara se carga"):
		_finish()
		return

	var packed: PackedScene = load(SHOP)
	if not _check(packed != null, "env_collector_shop.tscn se carga"):
		_finish()
		return

	# Sin meterla en el arbol: sus `_ready()` van a buscar Settings, SaveData y
	# LullabyGameoverModule, y bajo `--script` no hay autoloads (ver CLAUDE.md).
	# Esconder no necesita ninguno de los tres.
	var scene: Node = packed.instantiate()

	var cam: Node = script.new()
	cam.call("_hide_everything", scene)

	var hidden: Array = cam.get("_hidden")
	var kept_lit: Array = cam.get("_kept_lit")

	var canvas: Array[Node] = []
	var visuals: Array[Node] = []
	for node: Node in hidden:
		if node is CanvasItem:
			canvas.append(node)
		elif node is VisualInstance3D:
			visuals.append(node)

	# El 3D sigue entero: esto AÑADE el 2D, no lo cambia por el.
	_check(visuals.size() > 50,
		"los VisualInstance3D siguen entrando (%d)" % visuals.size())
	_check(kept_lit.size() > 0,
		"y las luces/bakes siguen exentos (%d)" % kept_lit.size())

	# Lo nuevo. El log cuenta 110 canvas items dibujados contra 73 antes de la
	# escena, y no todos son de este .tscn - los hay en subescenas y en los
	# SubViewports - asi que el numero que se fija aqui es "muchos", no uno
	# exacto que se rompa al mover un boton.
	_check(canvas.size() >= 20,
		"los CanvasItem entran al reparto (%d)" % canvas.size())

	# Y de verdad quedaron apagados, que es lo que evita el fotograma gordo.
	var still_on: int = 0
	for node: Node in canvas:
		if node.visible:
			still_on += 1
	_check(still_on == 0,
		"y quedan apagados de verdad (%d encendidos)" % still_on)

	_parents_before_children(canvas)
	_animated_is_exempt(scene, hidden)
	_reveal_restores(cam, canvas)

	scene.free()
	cam.free()
	_finish()


## Padre antes que hijo en `_hidden`, que es el orden en que `_reveal()` los
## enciende.
##
## Un hijo revelado antes que su padre no se dibuja, no compila nada, y aparece
## de golpe cuando el padre se enciende - o sea el vertido otra vez, en 2D. Sale
## gratis porque la pila de `_hide_everything()` es DFS y visita al padre antes
## que a sus hijos, pero es una propiedad de la que depende el reparto entero y
## que un `for` reescrito rompe sin dar ningun error.
func _parents_before_children(canvas: Array[Node]) -> void:
	var seen: Dictionary = {}
	var inverted: int = 0
	for node: Node in canvas:
		seen[node] = true
		var parent: Node = node.get_parent()
		while parent != null:
			if parent is CanvasItem and canvas.has(parent) and not seen.has(parent):
				inverted += 1
				break
			parent = parent.get_parent()
	_check(inverted == 0,
		"cada CanvasItem va despues de su padre (%d invertidos)" % inverted)


## El nodo cuya visibilidad conduce una animacion se queda fuera.
func _animated_is_exempt(scene: Node, hidden: Array) -> void:
	var target: Node = scene.get_node_or_null(NodePath(ANIMATED_2D))
	if not _check(target != null, "la tienda sigue teniendo %s" % ANIMATED_2D):
		return
	_check(not hidden.has(target),
		"y no se esconde, porque una animacion conduce su visible")


## Revelar deja la escena como estaba. El reparto no puede ser un cambio de
## estado permanente: todo lo que entra en `_hidden` entro estando visible.
func _reveal_restores(cam: Node, canvas: Array[Node]) -> void:
	var hidden: Array = cam.get("_hidden")
	cam.call("_reveal", hidden.size())
	var still_off: int = 0
	for node: Node in canvas:
		if not node.visible:
			still_off += 1
	_check(still_off == 0,
		"revelar del todo los devuelve a visible (%d apagados)" % still_off)


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el 2D tambien se reparte")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
