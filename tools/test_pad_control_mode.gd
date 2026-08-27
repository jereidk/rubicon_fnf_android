extends SceneTree

## El tercer modo de control: "Pad", una cruceta de cuatro flechas abajo.
##
## Pedido por su nombre - "el dpad de flechas literal y de esa posición que
## tiene, que se pueda usar como gameplay para acertar notas" - así que no es
## un diseño nuevo: es el aspecto y la posición del pad de escape de Chimera
## conduciendo los cuatro carriles en vez de la mecánica de gateo.
##
## Este guard fija las tres cosas que pueden romperse en silencio.
##
## **El mapa de brazos a carriles.** `RubiconCharacter.mania_directions` es
## `[left, down, up, right]`, o sea que el carril 0 es izquierda y el 2 es
## arriba. Un mapa invertido no da error: da un juego en el que las flechas
## no corresponden, que es indistinguible de "el port está mal cargado".
## Se comprueba contra `ChimeraEscapeDPad.ZONE_ACTIONS`, que ya tiene la
## respuesta, en vez de contra una tabla copiada aquí.
##
## **Que el pad reutilice el overlay táctil.** Todo lo que hace correcto a un
## modo táctil ya está resuelto en `LullabyTouchNoteInput` y nada de ello va
## de dónde están las zonas: el recuento de multitáctil, arrastrar un hold de
## una zona a otra, el despacho por `RubiconTouchInput` (que es lo que hace
## que ventanas de juicio, puntuación, splashes y `lane_state` se comporten
## igual que un teclado), el barrido de botones reservados, esconderse en
## pausa/gameover/HUD desvanecido, el botón rojo del péndulo y su destello de
## Showcase. Reimplementar eso es reintroducir los cuatro bugs que costó.
##
## **Que no se solape con el pad de escape de Chimera.** El de gateo se dibuja
## exactamente en el mismo sitio y es dueño de la pantalla mientras corre.
##
## Correr con:
##   godot --headless --path . --script tools/test_pad_control_mode.gd

const PAD := "res://lullaby_mod/scripts/lullaby/settings/lullaby_pad_note_input.gd"
const TOUCH := "res://lullaby_mod/scripts/lullaby/settings/lullaby_touch_note_input.gd"
const APPLIER := "res://lullaby_mod/scripts/lullaby/settings/lullaby_mobile_controls_applier.gd"
const SETTINGS := "res://menus/settings.gd"
const CONSOLE := "res://lullaby_mod/resources/console/console.tscn"
const ESCAPE := "res://lullaby_mod/songs/chimera/scripts/chimera_escape_dpad.gd"
const VISIBILITY := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/buttons/settings/mobile_section_visibility.gd"
const CHARACTER := "res://addons/rubicon/scripts/scene/game/rubicon_character.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_mode_checks()
	_mapping_checks()
	_reuse_checks()
	_applier_checks()
	_console_checks()

	print("pad control mode: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _mode_checks() -> void:
	var src: String = _read(SETTINGS)
	_check(src != "", "settings.gd se lee")
	_check(_has(src, "enum MobileControlMode { HITBOX = 0, TOUCH = 1, PAD = 2 }"),
		"el modo Pad existe en el enum, sin renumerar los dos anteriores")

	# Y la pregunta compartida, porque Touch y Pad quieren lo mismo del resto
	# del sistema y preguntarlo por separado es como se desincronizan.
	_check(_has(src, "func is_overlay_control_mode() -> bool:"),
		"hay una pregunta compartida para 'el input viene de un overlay'")
	_check(_has(src, "MobileControlMode.TOUCH, MobileControlMode.PAD"),
		"...y cubre los dos modos")

	var visibility: String = _read(VISIBILITY)
	_check(_has(visibility, "Settings.is_overlay_control_mode()"),
		"la consola enseña las opciones de toque tambien en Pad")


## El mapa se comprueba contra el pad que ya existe, no contra una copia.
func _mapping_checks() -> void:
	var pad: Script = load(PAD)
	_check(pad != null, "el script del pad carga")
	if pad == null:
		return

	var constants: Dictionary = pad.get_script_constant_map()
	_check(constants.has("ARM_LANES"), "el pad declara su mapa de brazos")
	if not constants.has("ARM_LANES"):
		return
	var lanes: Dictionary = constants["ARM_LANES"]

	# La verdad de referencia: mania_directions del propio motor.
	var character: String = _read(CHARACTER)
	_check(character.contains('[&"left", &"down", &"up", &"right"]'),
		"mania_directions sigue siendo [left, down, up, right]")

	# Y el pad de escape de Chimera, que ya resolvio esto una vez.
	var escape: Script = load(ESCAPE)
	_check(escape != null, "el pad de escape de Chimera carga")
	if escape == null:
		return
	var zones: Dictionary = escape.get_script_constant_map().get("ZONE_ACTIONS", {})
	_check(not zones.is_empty(), "y declara sus acciones por zona")

	for arm: int in lanes:
		var lane: int = lanes[arm]
		var expected: StringName = zones.get(arm, &"")
		_check(expected == StringName("mania_lane%d" % lane),
			"el brazo %d va al carril %d, igual que el pad de escape (%s)" % [
				arm, lane, expected])


func _reuse_checks() -> void:
	var src: String = _read(PAD)
	_check(_has(src, "extends LullabyTouchNoteInput"),
		"el pad extiende el overlay tactil en vez de reimplementarlo")

	# Lo que NO debe reimplementar. Cada uno de estos es un bug que ya se
	# pago una vez y que vive resuelto en la clase base.
	for forbidden: Array in [
		["func _input(", "el enrutado de eventos"],
		["func _handle_touch(", "el alta/baja de un dedo"],
		["func _press_lane(", "el recuento de multitactil"],
		["func _dispatch(", "el despacho por RubiconTouchInput"],
		["func _update_special_button(", "el boton rojo de la mecanica"],
	]:
		_check(not _has(src, forbidden[0]),
			"y no reimplementa %s" % forbidden[1])

	# Lo que si sobreescribe, que es exactamente lo que cambia.
	_check(_has(src, "func _lane_at(pos: Vector2) -> int:"),
		"solo cambia donde estan las zonas")
	_check(_has(src, "func _draw() -> void:"),
		"...y que se dibuja, porque este modo hay que verlo para usarlo")

	# El hub tiene que estar muerto: el pendulo se juega con el boton rojo en
	# los dos modos de overlay, y un centro activo seria un segundo control
	# para una sola accion.
	_check(_has(src, "if distance <= radius * HUB_RATIO * 1.15:"),
		"el centro del pad no es una zona de carril")

	# Y el pad no puede responder a un toque en cualquier sitio de la
	# pantalla, o deja de ser un pad.
	_check(_has(src, "if distance > radius * REACH_RATIO:"),
		"ni responde fuera de su propio alcance")

	# La exclusion con el gateo de Chimera, que se dibuja en el mismo sitio.
	_check(_has(src, "@export var escape_pad: Control"),
		"conoce el pad de escape de Chimera")
	_check(_has(src, '"mechanic_active" in escape_pad'),
		"...y se aparta mientras la mecanica de gateo esta activa")


func _applier_checks() -> void:
	var src: String = _read(APPLIER)
	_check(_has(src, "Settings.is_overlay_control_mode()"),
		"el applier deja los hitboxes inertes en los dos modos de overlay")
	_check(_has(src, "PAD_OVERLAY_SCRIPT if pad_mode else TOUCH_OVERLAY_SCRIPT"),
		"y elige el overlay por el modo exacto")
	_check(_has(src, "overlay.escape_pad = escape_dpad"),
		"le pasa el pad de escape al overlay del pad")

	# Y ninguno de los dos existe sin pantalla tactil. Los once scripts
	# tactiles del proyecto ya se esconden solos con esta misma pareja; estos
	# dos overlays los crea el applier, asi que la puerta tiene que estar
	# aqui o una build de PC dibujaria una cruceta en un monitor.
	_check(_has(src, "Settings.is_overlay_control_mode() and _has_touchscreen()"),
		"y ningun modo de overlay se enciende sin pantalla tactil")
	_check(_has(src, "DisplayServer.is_touchscreen_available() or OS.has_feature(\"mobile\")"),
		"con la misma prueba que usa el resto de controles tactiles")

	# El mismo grupo, o cambiar de modo dejaria dos overlays vivos a la vez.
	var pad: String = _read(PAD)
	var touch: String = _read(TOUCH)
	_check(not _has(pad, "add_to_group("),
		"el pad hereda el grupo del overlay tactil en vez de declarar otro")
	_check(_has(touch, 'add_to_group("lullaby_touch_note_input")'),
		"...que es el que barre _remove_touch_overlay")


func _console_checks() -> void:
	var scene: String = _read(CONSOLE)
	var at: int = scene.find('property = &"lullaby_mobile_control_mode"')
	_check(at != -1, "la fila de control de juego existe")
	if at == -1:
		return
	var stop: int = scene.find("\n[node ", at)
	var row: String = scene.substr(at, stop - at)
	_check(row.contains('display_list = ["Hitbox", "Touch", "Pad"]'),
		"y ofrece los tres modos")
	_check(row.contains("values_list = [0, 1, 2]"),
		"con los valores del enum")

	# Traducido: el tooltip cambio al añadir el modo, asi que la clave vieja
	# ya no resuelve y hay que haber movido la nueva.
	var csv: String = _read("res://lullaby_mod/resources/localization/ui_strings.csv")
	_check(csv.contains("Pad puts a four arrow d-pad at the bottom of the screen"),
		"el tooltip nuevo esta en el CSV")


func _has(src: String, needle: String) -> bool:
	for line: String in src.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK   %s" % label)
		return
	_failures += 1
	print("  FAIL %s" % label)
