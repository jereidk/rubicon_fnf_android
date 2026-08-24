extends SceneTree

## The scrolling credits play themselves once, and can be skipped by hand.
##
## Two reports, one cause. The credits came back after every clear of the three
## songs, and there was no way off the screen on a phone.
##
## The results screen already gated on `credits_scroll_seen` - but that flag is
## only written when the `angel` animation reaches its very end. Close the app,
## back out, or leave by any other route and it stayed false, so the next clear
## sent the player straight back in. `credits_shown` is written the moment the
## scene is ready instead, which is what "they already appeared" actually means.
##
## And the skip: `ui_accept` is Enter, Space and the gamepad's A, and this
## screen shipped no touch control at all. A button now sits on its own
## CanvasLayer above the art. It is NOT gated on having seen the credits before,
## which the first version of it was - that rule cannot survive the change next
## to it, because a screen that plays exactly once would then offer a skip
## nobody is ever offered.
##
## Run with:
##   godot --headless --path . --script tools/test_credits_once.gd

const SCRIPT_PATH := "res://lullaby_mod/scripts/lullaby/menus/lullaby_credits_scroll.gd"
const SCENE := "res://lullaby_mod/rooms/scn_demo_credits.tscn"
const RESULTS := "res://lullaby_mod/scripts/lullaby/menus/lullaby_results_screen.gd"
const SAVE_DATA := "res://lullaby_mod/scripts/lullaby/lullaby_save_data.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var code: String = _read(SCRIPT_PATH)
	var scene: String = _read(SCENE)
	var results: String = _read(RESULTS)

	# No repetirlos: la marca se pone al aparecer, no al terminar.
	_check(_read(SAVE_DATA).contains('&"credits_shown": false'),
		"credits_shown existe en las banderas de guardado")
	var ready_body: String = _func_body(code, "_ready")
	_check(ready_body.contains('SaveData.set_flag(&"credits_shown", true)'),
		"se marca al aparecer la escena, no al final de la animacion")
	_check(ready_body.contains("SaveData.save()"), "...y se guarda ahi mismo")
	_check(results.contains('not SaveData.get_flag(&"credits_shown")'),
		"la pantalla de resultados decide con credits_shown")
	_check(not results.contains('not SaveData.get_flag(&"credits_scroll_seen")'),
		"y ya no con credits_scroll_seen, que solo se escribia al final del angel")

	# credits_scroll_seen conserva su significado: cuatro sitios mas lo leen.
	_check(code.contains('SaveData.set_flag(&"credits_scroll_seen", true)'),
		"credits_scroll_seen sigue escribiendose cuando el angel termina")
	_check(code.contains('var play_angel: = not SaveData.get_flag(&"credits_scroll_seen")'),
		"y sigue siendo lo que decide si el angel se reproduce")

	# El boton.
	_check(scene.contains('[node name="SkipButton" type="Button"'),
		"la escena tiene un boton de skip")
	_check(scene.contains('[node name="SkipLayer" type="CanvasLayer"'),
		"en su propio CanvasLayer, por encima del arte")
	_check(scene.contains('skip_button = NodePath("SkipLayer/SkipButton")'),
		"cableado al export del script")
	_check(scene.contains('from="SkipLayer/SkipButton" to="." method="_on_skip_pressed"'),
		"y su señal conectada")
	_check(code.contains("func _on_skip_pressed()"), "el manejador existe")

	var pressed: String = _func_body(code, "_on_skip_pressed")
	_check(pressed.contains("_leave()"), "y sale de los creditos")
	_check(not pressed.contains("credits_scroll_seen"),
		"sin exigir haberlos visto antes: solo se reproducen una vez")

	# Y el mismo camino de siempre para el teclado/mando, tambien sin puerta.
	var input_body: String = _func_body(code, "_input")
	_check(input_body.contains('event.is_action(&"ui_accept")'),
		"ui_accept sigue saliendo")
	_check(not input_body.contains("credits_scroll_seen"),
		"y con la misma regla que el boton, no una distinta")

	# _leave sigue siendo reentrante-seguro: un toque son dos eventos en Android.
	_check(_func_body(code, "_leave").contains("if _leaving:"),
		"_leave sigue rechazando la segunda mitad de un mismo toque")

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


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
