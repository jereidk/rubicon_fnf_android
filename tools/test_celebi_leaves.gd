extends SceneTree

## Beating the typing challenge has to let Celebi leave, and take the darkness
## with it.
##
## Reported: "Celebi en la primera vez que aparece con la mecanica y esta es
## superada, el celebi se queda congelada, no hace animacion de irse, se queda
## congelada hasta que desaparece forzosamente", and the same for "un grafico
## oscuro 50 transparente". Two symptoms, and reading the scene says they are
## one bug plus one more that only shows on the same path.
##
## **The ordering.** `_autoplay_process()` is called from inside `_process()`,
## and it types - so the last letter of the word runs `succeed()`, which starts
## `ExportCelebi away`. Execution then returned to `_process` and carried on
## into the tick block, which on any frame where the second boundary had moved
## played `ExportCelebi tick` straight over it. Read off the scene, that
## animation is 1.0417s of frames 0..22 with no loop and holds
## `../Darkness:modulate` at alpha 0.652 for its whole length, where `away`
## would have taken it to 0 in 0.458s. So Celebi stops on a frame and the
## full-screen black rect stays up, both until the song's timeline sets
## `show_celebi = false` - at 84s for a challenge that ends at 82.
##
## Only autoplay reaches it. A human types through `_input`, which Godot
## delivers before `_process`, so the `challenge_over` guard at the top had
## already returned. That is why it survived on PC and shows up in Showcase.
##
## **The tween.** `fail()` has always killed `_celebi_tween`; `succeed()` never
## did. It runs for the challenge's whole window and writes `$Celebi.scale` and
## `$Celebi.modulate` every frame, so beating the word early - the only way to
## succeed - left Celebi being scaled and brightened after its leave animation
## had finished.
##
## Run with:
##   godot --headless --path . --script tools/test_celebi_leaves.gd

const SCRIPT_PATH := "res://lullaby_mod/scripts/lullaby/mechanics/monochrome/typing_challenge.gd"
const SCENE := "res://lullaby_mod/resources/funkin/songs/monochrome/scenes/mch_typing.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var code: String = _read(SCRIPT_PATH)

	# 1. La salida de _process justo despues de que autoplay pueda terminar.
	var body: String = _func_body(code, "_process")
	var autoplay_at: int = body.find("_autoplay_process(delta, time_left)")
	var guard_at: int = body.find("if challenge_over:", autoplay_at if autoplay_at >= 0 else 0)
	var tick_at: int = body.find("celebi_animator.play(celebi_tick_animation")
	_check(autoplay_at >= 0, "_process sigue llamando a _autoplay_process")
	_check(guard_at > autoplay_at,
		"y comprueba challenge_over justo despues, porque escribir puede terminarlo")
	_check(tick_at > guard_at,
		"antes del bloque de ticks, que es lo que pisaba la animacion de salida")

	# 2. succeed() mata el tween, igual que fail().
	var succeed: String = _func_body(code, "succeed")
	var fail: String = _func_body(code, "fail")
	_check(succeed.contains("_celebi_tween.kill()"), "succeed() mata el tween de Celebi")
	_check(fail.contains("_celebi_tween.kill()"), "fail() lo sigue matando")
	_check(succeed.contains("celebi_animator.play(celebi_success_animation)"),
		"y sigue lanzando la animacion de salida")

	# El tween es lo unico que escribe scale/modulate de Celebi por codigo, asi
	# que si dejara de matarse no habria nada mas que lo parase.
	_check(_func_body(code, "_celebi_tween_func").contains("$Celebi.scale"),
		"el tween escribe $Celebi.scale cada frame (por eso hay que matarlo)")

	_scene_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## Las dos animaciones, leidas de la escena en vez de repetidas aqui: si alguien
## reautora `tick` para que suelte la oscuridad, o `away` para que la mantenga,
## este fichero deja de describir el juego y tiene que decirlo.
func _scene_checks() -> void:
	var scene: String = _read(SCENE)

	var tick: String = _animation_named(scene, "ExportCelebi tick")
	var away: String = _animation_named(scene, "ExportCelebi away")
	_check(tick != "", "ExportCelebi tick sigue en la escena")
	_check(away != "", "ExportCelebi away sigue en la escena")

	_check(tick.contains("../Darkness:modulate"),
		"tick sigue tocando la oscuridad")
	_check(tick.contains("0.652") and not tick.contains("Color(1, 1, 1, 0),"),
		"y la mantiene arriba, que es por lo que pisarla con ella dejaba el rect puesto")
	_check(away.contains("../Darkness:modulate") and away.contains("Color(1, 1, 1, 0)"),
		"away es la que la baja a cero")

	# Y que la escena siga apuntando el export a `away`: si volviese al valor
	# por defecto del script - "Celebi return", que no existe en esta libreria -
	# succeed() no reproduciria nada en absoluto.
	_check(scene.contains('celebi_success_animation = &"ExportCelebi away"'),
		"el export apunta a una animacion que existe de verdad")
	_check(scene.contains('&"ExportCelebi away": SubResource'),
		"...y esta en la libreria con ese nombre exacto")


func _animation_named(scene: String, key: String) -> String:
	var lib: int = scene.find('&"%s": SubResource("' % key)
	if lib < 0:
		return ""
	var from: int = lib + ('&"%s": SubResource("' % key).length()
	var sub: String = scene.substr(from, scene.find('"', from) - from)
	var at: int = scene.find('[sub_resource type="Animation" id="%s"]' % sub)
	if at < 0:
		return ""
	var end: int = scene.find("\n[sub_resource", at)
	return scene.substr(at, (end - at) if end > at else -1)


func _func_body(text: String, name: String) -> String:
	var head: int = text.find("func %s(" % name)
	if head < 0:
		_check(false, "%s() existe" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "%s se lee" % path.get_file())
	return text
