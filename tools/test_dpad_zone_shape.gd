extends SceneTree

## A direction the D-pad ignores is not drawn at all, and the pad's outline
## closes over the gap.
##
## It used to draw the disabled arms at a quarter alpha. A greyed-out control
## reads as one that is temporarily unavailable, and these are not: nothing
## makes left/right mean something while the notepad or the SHOP/TALK sign is
## up, so the arrow was never coming back and the player was being shown a
## control that does not exist.
##
## Hiding the arm is the easy half. The outline is the half that would look
## broken if it were missed - it was a hardcoded twelve-point plus, so with
## two arms gone it would have gone on tracing four of them around empty
## space, which is worse than the dim arrow was. That shape is what this
## measures, because it is the only part of the drawing a headless run can
## see at all.
##
## Run with:
##   godot --headless --path . --script tools/test_dpad_zone_shape.gd

const DPAD := "res://addons/rubicon_mobile_controls/virtual_dpad.gd"

## Hub half-width and arm length. Round numbers so a failure prints something
## readable; the real pad computes them from radius.
const W := 38.0
const L := 100.0

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var dpad: Control = Control.new()
	dpad.set_script(load(DPAD))
	root.add_child(dpad)

	_shape_checks(dpad)
	_input_checks(dpad)
	_stuck_action_check(dpad)

	dpad.queue_free()

	print("")
	if _checks < 14:
		print("FALLO: solo %d de 14 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el D-pad solo dibuja las direcciones que sirven")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _shape_checks(dpad: Control) -> void:
	# All four: the exact twelve-point plus the scene has always drawn. Locked
	# as a literal on purpose - the whole promise of this change is that a pad
	# with every direction available looks like it always did.
	dpad.enabled_zones = _zones([0, 1, 2, 3])
	var full: PackedVector2Array = dpad.outline_points(Vector2.ZERO, W, L)
	var expected := PackedVector2Array([
		Vector2(-W, -L), Vector2(W, -L), Vector2(W, -W),
		Vector2(L, -W), Vector2(L, W), Vector2(W, W),
		Vector2(W, L), Vector2(-W, L), Vector2(-W, W),
		Vector2(-L, W), Vector2(-L, -W), Vector2(-W, -W),
	])
	_check("las cuatro direcciones dan la cruz de siempre", full == expected,
		"%d puntos" % full.size())

	# Vertical only: a bar. No point may reach out to the arm length
	# sideways, which is exactly what a leftover left/right arm would do.
	dpad.enabled_zones = _zones([0, 2])
	var vertical: PackedVector2Array = dpad.outline_points(Vector2.ZERO, W, L)
	_check("vertical: ocho puntos", vertical.size() == 8, "%d" % vertical.size())
	_check("vertical: nada sobresale a los lados", _max_abs(vertical, true) == W,
		"x max %.0f" % _max_abs(vertical, true))
	_check("vertical: sigue llegando arriba y abajo", _max_abs(vertical, false) == L,
		"y max %.0f" % _max_abs(vertical, false))

	dpad.enabled_zones = _zones([1, 3])
	var horizontal: PackedVector2Array = dpad.outline_points(Vector2.ZERO, W, L)
	_check("horizontal: ocho puntos", horizontal.size() == 8, "%d" % horizontal.size())
	_check("horizontal: nada sobresale arriba ni abajo",
		_max_abs(horizontal, false) == W, "y max %.0f" % _max_abs(horizontal, false))

	# One direction: a stub. Three points for the arm plus the three hub
	# corners the other zones contribute.
	dpad.enabled_zones = _zones([0])
	var one: PackedVector2Array = dpad.outline_points(Vector2.ZERO, W, L)
	_check("una sola direccion: seis puntos", one.size() == 6, "%d" % one.size())

	# None: the bare hub square, which _draw() never gets far enough to ask
	# for - it returns before this. Checked anyway because the shape has to
	# stay well-formed for the day something does ask.
	dpad.enabled_zones = _zones([])
	var none: PackedVector2Array = dpad.outline_points(Vector2.ZERO, W, L)
	_check("ninguna: solo el cuadrado del centro", none.size() == 4
		and _max_abs(none, true) == W and _max_abs(none, false) == W)

	# The origin is not the centre of the Control - the pad is anchored into a
	# corner of it - so every point has to be offset by it, not just some.
	dpad.enabled_zones = _zones([0, 1, 2, 3])
	var moved: PackedVector2Array = dpad.outline_points(Vector2(195, 195), W, L)
	var shifted: bool = true
	for i in full.size():
		if not moved[i].is_equal_approx(full[i] + Vector2(195, 195)):
			shifted = false
	_check("el contorno se dibuja alrededor del origen del pad", shifted)

func _input_checks(dpad: Control) -> void:
	# A pad with nothing enabled draws nothing, so it must not take a touch
	# either - the knob would otherwise track a finger across blank screen.
	dpad.enabled_zones = _zones([])
	dpad._touch_index = -1
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = dpad._get_origin()
	dpad._input(touch)
	_check("sin direcciones no acepta el toque", dpad._touch_index == -1,
		"index %d" % dpad._touch_index)

	dpad.enabled_zones = _zones([0, 1, 2, 3])
	dpad._input(touch)
	_check("con direcciones si lo acepta", dpad._touch_index == 0,
		"index %d" % dpad._touch_index)
	dpad._release()

## A zone that stops being enabled while it is held has to be released.
##
## Same failure _release() exists for and reached the other way round: not the
## finger leaving the pad, but the pad changing under the finger. No touch
## event is ever coming to clear it, so the action would stay pressed for good
## - which on this project read as the camera spinning by itself.
func _stuck_action_check(dpad: Control) -> void:
	dpad.enabled_zones = _zones([0, 1, 2, 3])
	dpad._active_zone = 1
	dpad._touch_index = 0
	dpad.enabled_zones = _zones([0, 2])
	_check("apagar una direccion sujeta la suelta", dpad._active_zone == -1,
		"zona %d" % dpad._active_zone)
	_check("y suelta el toque con ella", dpad._touch_index == -1)

	# The reverse must not happen: a zone still enabled keeps its press.
	dpad._active_zone = 0
	dpad._touch_index = 0
	dpad.enabled_zones = _zones([0, 2])
	_check("una direccion que sigue activa no se interrumpe", dpad._active_zone == 0)
	dpad._release()

## enabled_zones is Array[int]; a bare literal is a plain Array and will not
## assign to it.
func _zones(values: Array) -> Array[int]:
	var typed: Array[int] = []
	for value in values:
		typed.append(int(value))
	return typed

func _max_abs(points: PackedVector2Array, use_x: bool) -> float:
	var most: float = 0.0
	for point in points:
		most = maxf(most, absf(point.x if use_x else point.y))
	return most

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
