extends Node

## Los cables de la consola y el kollectadex diferidos, comprobados EN VIVO.
##
## Por qué hace falta esto y no basta con test_console_deferred.gd: ese guard lee
## texto. Lee el .tscn, lee el script del cargador, y comprueba que el uno
## nombra lo que el otro necesita. Eso habría cogido el fallo de la build
## 10249-e93c8ca2 (y ahora lo coge), pero sigue siendo una prueba sobre ficheros:
## no monta nada, no ejecuta ningún `_ready()`, y no puede ver el orden en que
## las cosas pasan. Y el orden es justo la mitad del problema - que
## `power_console.gd` corriera antes de que la consola existiera no está escrito
## en ningún fichero.
##
## Lo que esta sonda añade es el árbol de verdad: monta la tienda, espera a que
## el cargador termine, y mira cada @export que tenía que quedar reenganchado
## para ver si de verdad tiene algo dentro. Doce cables de la consola, dos del
## kollectadex, la conexión de sonido, y el estado del televisor.
##
## Los tres que llegaron nulos al dispositivo y cómo se notaron:
##
##     Cartridges.bag_area / .handler   el botón Cartuchos no hacía NADA, porque
##                                      cartridges_button.gd hace `if handler:`
##     EnterLabel.collector_shop        cartridges_enter_label.gd:48 petaba y la
##                                      canción no arrancaba nunca
##
## Y el cuarto efecto, que no era un cable sino el orden: la consola nace con
## `modulate = Color(0, 0, 0, 1)` y `power_console.gd` era lo único que la ponía
## en blanco, desde un `_ready()` que aborta en su primer uso del `console` nulo.
## La pantalla del televisor se quedaba negra. Aquí se comprueba que el modulate
## acabó donde el flag `console_on` dice que tiene que acabar.
##
## Necesita la caché de importación (`.godot/imported`). Sin ella la tienda no
## carga y la sonda lo dice en vez de fingir que pasó: un contenedor recién
## hecho no la tiene, y se saca del artifact `godot-import-cache` del workflow.
##
## Uso:
##   godot --headless --path . res://tools/harness/probe_console_deferred.tscn
##   ... -- espera=40

const SHOP := "res://lullaby_mod/rooms/env_collector_shop.tscn"
const CONSOLE_PATH := "Viewports/ConsoleSubViewport/Console"
const KOLLECTADEX_PATH := "Viewports/KollectadexSubViewport/Kollectadex"

var _deadline_msec: int = 0
var _shop: Node = null
var _reported: bool = false

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	# El vigilante lleva ESTE mismo script, así que su `add_child()` vuelve a
	# entrar aquí. Sin esta guarda se clonaba a sí mismo cada fotograma y la
	# sonda nunca llegaba a mirar nada. `_deadline_msec` ya está puesto en él
	# antes del add_child, y en la copia original vale 0.
	if _deadline_msec != 0:
		return

	var wait: float = 90.0
	var force_on: int = -1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("espera="):
			wait = a.trim_prefix("espera=").to_float()
		elif a.begins_with("encendido="):
			force_on = int(a.trim_prefix("encendido="))

	# El flag `console_on` decide si el televisor tiene que acabar en BLANCO o en
	# NEGRO, y una partida recién hecha lo trae en false. Eso deja sin probar
	# justo el camino que fallaba: el modulate empaquetado ya ES negro, así que
	# con el flag apagado la comprobación pasa incluso con `apply_console_state()`
	# sin llamar. Hay que correr la sonda con `encendido=1` para que signifique
	# algo, y con `encendido=0` para el otro lado.
	if force_on >= 0:
		var save: Node = get_node_or_null(^"/root/SaveData")
		if save != null and save.has_method("set_flag"):
			save.call("set_flag", &"console_on", force_on == 1)
			print("OUT console_on forzado a %s" % (force_on == 1))
		else:
			printerr("OUT no encontré SaveData para forzar console_on")

	# Igual que probe_mixer_caches.gd: colgado de root ANTES del cambio de
	# escena, que libera la escena actual - esta sonda - y con ella todo lo que
	# estuviera dentro. Y diferido, porque durante el `_ready()` de la escena
	# principal `root` está montando hijos y `add_child()` falla en el sitio con
	# "Parent node is busy setting up children".
	var watcher := Node.new()
	watcher.name = "ConsoleProbeWatch"
	watcher.set_script(get_script())
	watcher.set("_deadline_msec", Time.get_ticks_msec() + int(wait * 1000.0))
	get_tree().root.add_child.call_deferred(watcher)

	print("OUT sonda de consola diferida, hasta %.0fs" % wait)
	get_tree().change_scene_to_file.call_deferred(SHOP)


func _process(_delta: float) -> void:
	# Sólo el vigilante colgado de root trabaja; la copia que vive en la escena
	# de la sonda se va con el cambio de escena.
	if _deadline_msec == 0 or _reported:
		return

	if _shop == null:
		_shop = _find_shop()
		if _shop == null:
			_give_up_if_late("la tienda no llegó a montarse")
			return

	var console: Node = _shop.get_node_or_null(NodePath(CONSOLE_PATH))
	if console == null:
		_give_up_if_late("el cargador nunca montó la consola en %s" % CONSOLE_PATH)
		return

	# Un par de fotogramas de cortesía: el cargador monta y reengancha en el
	# mismo `_process`, pero `_ready()` de la consola y de sus hijos corre
	# después, y `apply_console_state()` toca cosas que ellos ponen.
	await get_tree().process_frame
	await get_tree().process_frame

	_report(console)


## La tienda, buscada por su script en vez de por nombre.
##
## `change_scene_to_file()` nombra el nodo raíz como el .tscn dice, y fiarse de
## ese nombre es exactamente la clase de suposición que esta sonda existe para
## no hacer. La clase CollectorShop sí es estable.
func _find_shop() -> Node:
	for child in get_tree().root.get_children():
		if child.get_script() != null and child.get("state") != null \
				and child.has_node(NodePath("Viewports/ConsoleSubViewport")):
			return child
	var current: Node = get_tree().current_scene
	if current != null and current.has_node(NodePath("Viewports/ConsoleSubViewport")):
		return current
	return null


func _give_up_if_late(what: String) -> void:
	if Time.get_ticks_msec() < _deadline_msec:
		return
	_reported = true
	_failures += 1
	printerr("  FALLO %s" % what)
	_finish()


func _report(console: Node) -> void:
	_reported = true
	print("OUT consola montada, %d nodos" % _count(console))

	# 1. Los seis que apuntan HACIA la consola.
	_wired(_shop, "console", "CollectorShop.console")
	_wired(_shop.get_node_or_null(^"Environment/Areas/FocusConsole"),
		"console", "FocusConsole.console")
	_wired(_shop.get_node_or_null(^"Environment/Areas/FocusPowerConsole"),
		"console", "FocusPowerConsole.console")
	_wired(_shop.get_node_or_null(^"UI/Control/TouchControls"),
		"force_active_source", "TouchControls.force_active_source")
	_wired(_shop.get_node_or_null(^"UI/Control/TouchControls/SwitchCartridgeButton"),
		"visible_source", "SwitchCartridgeButton.visible_source")

	var gate: Node = _shop.get_node_or_null(^"Environment/Areas/TvViewportDisabler")
	if gate != null:
		var nested: Variant = gate.get("nested_containers")
		_check(nested is Array and (nested as Array).size() == 3,
			"TvViewportDisabler.nested_containers tiene los 3 (%s)"
				% (str((nested as Array).size()) if nested is Array else "no es Array"))

	# 2. Los seis que salen DESDE la consola, que son los que pack() cortó.
	_wired(console, "shop", "Console.shop")
	_wired(console, "sequences", "Console.sequences")
	_wired(console, "focus_right_area", "Console.focus_right_area")

	var cartridges: Node = console.get_node_or_null(
		^"TabContainer/Home/FakeButtons/Cartridges")
	_wired(cartridges, "bag_area", "Cartridges.bag_area")
	_wired(cartridges, "handler", "Cartridges.handler")

	var enter_label: Node = console.get_node_or_null(^"TabContainer/Cartridges/EnterLabel")
	_wired(enter_label, "collector_shop", "EnterLabel.collector_shop")

	# Y que el que petaba de verdad resuelve: el error del dispositivo era
	# `'sequence_controller' on a base object of type 'Nil'`, o sea que lo que
	# hay que ver es que ese camino entero llega a un AnimationPlayer.
	if enter_label != null:
		var cs: Variant = enter_label.get("collector_shop")
		var seq: Variant = (cs as Node).get("sequence_controller") if cs is Node else null
		var player: Variant = (seq as Node).get("animation_player") if seq is Node else null
		_check(player is AnimationPlayer,
			"EnterLabel.collector_shop.sequence_controller.animation_player resuelve")

	# 3. El sonido, que era la única de las trece conexiones del .tscn que tocaba
	#    la consola.
	var sfx: Node = _shop.get_node_or_null(^"Environment/shop_base/prp_console/ConsoleSFX")
	if sfx != null and console.has_signal("play_sound"):
		_check(console.is_connected("play_sound",
				Callable(sfx, "_on_console_play_sound")),
			"la señal play_sound sigue conectada a ConsoleSFX")

	# 4. El televisor. Negro por defecto en el .tscn empaquetado; sólo
	#    power_console.gd lo cambia, y su `_ready()` corre antes de que la
	#    consola exista.
	var power: Node = _shop.get_node_or_null(^"Environment/Areas/FocusPowerConsole")
	if power != null:
		var on: bool = bool(power.get("on"))
		var want: Color = Color.WHITE if on else Color.BLACK
		var got: Color = console.get("modulate")
		_check(got.is_equal_approx(want),
			"modulate del televisor es %s con console_on=%s (es %s)"
				% [want, on, got])
		_check((power.get("indicator") as Node3D).visible == on,
			"y el indicador sigue a console_on")

	# 5. El kollectadex, diferido igual.
	var kol: Node = _shop.get_node_or_null(NodePath(KOLLECTADEX_PATH))
	if _check(kol != null, "el kollectadex también se montó"):
		var inner: Node = kol.get_node_or_null(^"PanelContainer/Kollectadex")
		if _check(inner != null, "y trae su Control interior"):
			_wired(_shop.get_node_or_null(^"Environment/Areas/FocusKollectadex"),
				"kollectadex", "FocusKollectadex.kollectadex")
			_wired(_shop.get_node_or_null(^"UI/Control/TouchControls"),
				"force_active_source4", "TouchControls.force_active_source4")

	_finish()


## Que la propiedad exista Y tenga algo dentro. Las dos cosas: un @export que
## alguien renombra desaparece sin dar error, y comprobar sólo el nulo dejaría
## pasar un nombre que ya no existe como si estuviera bien.
func _wired(node: Node, prop: String, label: String) -> void:
	if not _check(node != null, "existe el nodo de %s" % label):
		return
	if not _check(prop in node, "%s sigue siendo una propiedad" % label):
		return
	var value: Variant = node.get(prop)
	_check(value != null and (not (value is Node) or is_instance_valid(value as Node)),
		"%s está enganchado" % label)


func _count(root: Node) -> int:
	var n: int = 1
	for child in root.get_children():
		n += _count(child)
	return n


func _finish() -> void:
	print("OUT %d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("OUT todo OK - los cables diferidos llegan enteros al árbol")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
