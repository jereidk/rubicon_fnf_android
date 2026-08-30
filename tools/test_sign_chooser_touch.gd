extends SceneTree

## El selector de comprar/hablar del mostrador se puede usar en tactil.
##
## Tres fallos, los tres en el mismo momento de la tienda: cuando la camara se
## enfoca en el coleccionista y sale el cartel a elegir entre comprar cartuchos
## o hablar con el.
##
## 1. NO SE PODIA CONFIRMAR EN MOVIL. En tactil el unico origen de un confirm es
##    el boton OK del overlay - `MouseController._is_confirm_event()` exige un
##    `InputEventAction` o un boton de mando, a proposito, para que el click de
##    raton emulado que Android produce en CADA toque no confirme cosas solo. Y
##    ese boton toma su visibilidad de `confirm_is_available`
##    (`AcceptButton.visible_source` en `env_collector_shop.tscn`), que
##    respondia mirando el raycast:
##
##        if not _can_ray_cast(): return true
##        return colliding and can_click
##
##    El selector no usa el raycast: se atiende en su propio `_input()` y apaga
##    su area (`focus_area_center.input_ray_pickable = !enabled`). Pero deja la
##    tienda en FOCUSED, no en BUSY, asi que `should_cast_ray` sigue en true y
##    `_can_ray_cast()` dice que si. La respuesta pasaba a ser `colliding`, que
##    ahi es lo que pille el rayo desde el ultimo toque: normalmente nada. Boton
##    escondido, ningun InputEventAction, `_input()` del cartel nunca disparado.
##    En raton no se veia porque un click de verdad ya es un confirm por si solo.
##
## 2. SE ENCENDIA LA OPCION EQUIVOCADA. `options[-1]` en GDScript no es un error:
##    devuelve el ultimo elemento, "talk". `sequence_sign_intro` escribe
##    `current_option_index = -1` en t=0 y `enabled = true` en t=2, y el setter
##    de `enabled` llama a `_update_visual()`, que indexaba sin mirar. Se
##    encendia "talk" con el indice en -1, que es justo lo que `_input()` mira
##    para NO dejar confirmar.
##
## 3. EL BALANCEO DEPENDIA DE LOS FPS. `position.x += sin(...)` cada fotograma,
##    con el lerp del fotograma siguiente partiendo de ese resultado: no era un
##    balanceo sino una acumulacion amortiguada. Con el cartel apagado el
##    coeficiente del lerp es 0.013 a 60fps y 0.027 a 30, o sea el doble de
##    desplazamiento a 60 que a 30. En un movil que no sostiene 60 el cartel
##    flota en otro sitio.
##
## Run with:
##   godot --headless --path . --script tools/test_sign_chooser_touch.gd

const SIGN := "res://lullaby_mod/scripts/lullaby/collectors_shop/props/prp_sign.gd"
const CONTROLLER := "res://lullaby_mod/scripts/lullaby/collectors_shop/controllers/mouse_controller.gd"
const SHOP_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_confirm_button_checks()
	_option_index_checks()
	_sway_checks()
	_wiring_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el selector del mostrador responde en tactil")
	quit(1 if _failures > 0 else 0)


## Fallo 1: el boton OK tiene que estar disponible mientras el cartel manda.
func _confirm_button_checks() -> void:
	var script: GDScript = load(CONTROLLER)
	if not _check(script != null, "mouse_controller.gd carga"):
		return

	# Fuera del arbol: su `_ready()` toca el AnimationTree y la tienda.
	var controller: Node = script.new()

	# Con camara y rayo de verdad. Sin ellos `_can_ray_cast()` dice que no
	# hagas raycast y el getter contesta `true` por la rama de "esto es un fallo
	# de cableado, no un motivo para quitarle el boton al jugador" - o sea que
	# sin esto la prueba nunca llegaria a la rama que importa.
	var camera := Camera3D.new()
	var ray := RayCast3D.new()
	controller.set("camera", camera)
	controller.set("ray_cast", ray)

	controller.set("should_cast_ray", false)

	# Sin raycast ya decia que si, y eso no se toca.
	_check(bool(controller.get("confirm_is_available")),
		"sin raycast el confirm sigue estando disponible")

	# El caso del cartel: hay raycast, no hay colision. Antes: false.
	controller.set("should_cast_ray", true)
	controller.set("colliding", false)
	controller.set("can_click", true)
	_check(not bool(controller.get("confirm_is_available")),
		"con raycast y sin colision sigue diciendo que no, como debe")

	controller.set("confirm_owned_by_prop", true)
	_check(bool(controller.get("confirm_is_available")),
		"...salvo si un prop se adueña del confirm - que es el caso del cartel")

	controller.set("confirm_owned_by_prop", false)
	_check(not bool(controller.get("confirm_is_available")),
		"y al soltarlo vuelve a mandar el raycast")

	controller.free()
	camera.free()
	ray.free()


## Fallo 2: un indice sin elegir no puede encender una opcion.
func _option_index_checks() -> void:
	var script: GDScript = load(SIGN)
	if not _check(script != null, "prp_sign.gd carga"):
		return

	# La trampa, tal cual, para que quede escrita: no es una teoria.
	var options: Array[String] = ["shop", "talk"]
	_check(options[-1] == "talk",
		"options[-1] devuelve el ultimo elemento, no un error - la trampa de fondo")

	var body: String = _func_body(_strip_comments(_read(SIGN)), "_update_visual")
	_check(not body.is_empty(), "se encuentra _update_visual")
	_check(body.contains("current_option_index < 0")
			and body.contains("current_option_index >= options.size()"),
		"_update_visual descarta el indice fuera de rango antes de indexar")

	# Y que el `_input()` siga exigiendo una eleccion de verdad, que es la otra
	# mitad: sin esto el arreglo de arriba solo escondería el sintoma.
	var input_body: String = _func_body(_strip_comments(_read(SIGN)), "_input")
	_check(input_body.contains("current_option_index == -1"),
		"_input sigue negandose a confirmar sin opcion elegida")


## Fallo 3: el balanceo es un desplazamiento, no una acumulacion.
func _sway_checks() -> void:
	var code: String = _strip_comments(_read(SIGN))
	var body: String = _func_body(code, "_process")

	_check(not body.contains("position.x += sin")
			and not body.contains("position.y += cos")
			and not body.contains("selector_model.position.x += sin"),
		"ya no se suma el balanceo encima de la posicion de cada fotograma")
	_check(body.contains("_selector_base = _selector_base.lerp")
			and body.contains("_sign_base = _sign_base.lerp"),
		"el suavizado trabaja sobre una base limpia")
	_check(body.contains("position = _sign_base + _sign_sway"),
		"y la posicion final es base + balanceo, que no depende de los fps")


## Que el cableado de la escena sigue siendo el que hace falta para todo esto.
func _wiring_checks() -> void:
	var scene: String = _read(SHOP_SCENE)
	_check(scene.contains('visible_property = &"confirm_is_available"'),
		"el AcceptButton sigue colgando de confirm_is_available")
	_check(scene.contains('vertical_only_property = &"is_choosing_option"'),
		"y el D-pad sigue silenciado a vertical mientras se elige")

	var sign_code: String = _strip_comments(_read(SIGN))
	_check(sign_code.contains("confirm_owned_by_prop = is_choosing_option"),
		"el cartel se adueña del confirm exactamente mientras elige")
	_check(_func_body(sign_code, "_exit_tree").contains("confirm_owned_by_prop = false"),
		"y lo devuelve al salir de la escena")


func _func_body(code: String, name: String) -> String:
	var at: int = code.find("func %s(" % name)
	if at < 0:
		return ""
	var next: int = code.find("\nfunc ", at + 1)
	return code.substr(at, -1 if next < 0 else next - at)


func _strip_comments(code: String) -> String:
	var out: PackedStringArray = []
	for line in code.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
