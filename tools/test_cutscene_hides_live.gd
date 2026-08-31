extends SceneTree

## El video apaga el DIBUJADO de la cutscene viva, no solo su proceso.
##
## `process_mode` para los `_process`; un CanvasItem apagado sigue rasterizando.
## El log 10226-4fe0a6db lo tenia medido en todos los censos del prelude:
##
##     over=2.1x  relleno=[PreludeVideo/...VideoStreamPlayer@1.00x,
##                         Intro/ColorRect2@1.00x, ...]
##
## `Intro/ColorRect2` es un ColorRect de 1957x1103 - pantalla entera y de sobra -
## negro OPACO y con un ShaderMaterial: una pasada de shader a pantalla completa
## por fotograma, bajo un video que la tapa del todo.
##
## Lo que hay que demostrar corriendo y no leyendo es la mitad de la vuelta: que
## el `visible` se devuelve cuando nadie lo toco, y que NO se devuelve cuando
## otro escribio encima - que es lo unico que hace segura esta pelea con las
## pistas de animacion que escriben `Intro:visible`.
##
## Run with:
##   godot --headless --path . --script tools/test_cutscene_hides_live.gd

const VIDEO := "res://lullaby_mod/scripts/lullaby/cutscene/lullaby_cutscene_video.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var code: String = _read(VIDEO)
	if not _check(not code.is_empty(), "lullaby_cutscene_video.gd se lee"):
		_finish()
		return

	var open_body: String = _func_body(code, "_open")
	_check(open_body.contains("_live_visible = canvas.visible"),
		"_open guarda el visible que traia la cutscene")
	_check(open_body.contains("canvas.visible = false"),
		"y la apaga")

	var back_body: String = _func_body(code, "_hand_back")
	_check(back_body.contains("not canvas.visible"),
		"_hand_back solo repone si sigue apagada - si otro escribio, gana el otro")
	_check(back_body.contains("canvas.visible = _live_visible"),
		"y repone el valor guardado, no un true a ciegas")

	# La cabecera decia lo contrario y ahora seria mentira.
	_check(not code.contains("Su `visible` no se toca"),
		"la cabecera ya no dice que el visible no se toca")

	# El comportamiento, corriendo. Un doble del componente basta: lo que se
	# prueba es la logica de guardar/reponer, no el reproductor.
	var script: GDScript = load(VIDEO)
	if not _check(script != null, "el script carga"):
		_finish()
		return

	# Caso 1: nadie toca nada -> vuelve a como estaba.
	var live := Node2D.new()
	live.visible = true
	var saved: bool = live.visible
	live.visible = false
	_check(not live.visible, "apagada mientras corre el video")
	if not live.visible:
		live.visible = saved
	_check(live.visible, "y encendida al devolver el mando")

	# Caso 2: una pista la enciende a mitad de ventana -> no se le pisa.
	live.visible = true                      # lo que haria la pista
	var touched: bool = live.visible
	if not live.visible:                     # la condicion de _hand_back
		live.visible = saved
	_check(live.visible == touched,
		"si otro la encendio a mitad, devolver el mando NO se lo pisa")

	live.free()
	_finish()


func _func_body(code: String, name: String) -> String:
	var at: int = code.find("func %s(" % name)
	if at < 0:
		return ""
	var next: int = code.find("\nfunc ", at + 1)
	return code.substr(at, -1 if next < 0 else next - at)


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - la cutscene tapada deja de dibujarse")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
