extends SceneTree

## `is_touch_controls_active()` se resuelve una vez, no una vez por llamada.
##
## Por que existe
## -------------
## Siete sitios la llaman, y varios lo hacen POR FOTOGRAMA: `_process` y
## `_physics_process` de mouse_controller.gd, touch_aim_reticle.gd, y los
## `_process` de prp_notepad.gd, prp_sign.gd y prp_briefcase.gd, mas el log de
## diagnostico. Sin cache cada una de esas llamadas hace tres consultas al
## motor -`ProjectSettings.get_setting()` resolviendo una ruta por CADENA,
## `DisplayServer.is_touchscreen_available()` cruzando al servidor, y
## `OS.has_feature()` comparando contra el conjunto de features- para una
## respuesta que se decide al arrancar y no puede cambiar.
##
## Lo que hace peligroso volver atras es que no se nota: quitar la cache no
## rompe nada, no da ningun error, y el coste se reparte entre siete nodos de
## forma que ningun perfil lo señala. Y la tienda es donde duele, porque es la
## escena que va justo en el limite de los 16,67ms.
##
## Ademas comprueba que la premisa sigue siendo cierta. La cache SOLO es valida
## mientras nadie escriba `rubicon_mobile_controls/enabled` en tiempo de
## ejecucion. Hoy lo declara el plugin del editor y los demas solo lo leen; el
## dia que alguien lo haga configurable, esta prueba falla y dice por que, en
## vez de dejar un ajuste que no surte efecto hasta reiniciar.
##
## Run with:
##   godot --headless --path . --script tools/test_touch_check_cached.gd

const MOUSE := "res://lullaby_mod/scripts/lullaby/collectors_shop/controllers/mouse_controller.gd"
const SETTING := "rubicon_mobile_controls/enabled"

## Donde SI vale escribirlo: el plugin lo declara, no lo cambia.
const DECLARES := "res://addons/rubicon_mobile_controls/plugin.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var src: String = FileAccess.get_file_as_string(MOUSE)
	if not _check(not src.is_empty(), "mouse_controller.gd se lee"):
		_finish()
		return

	_check(src.contains("static var _touch_controls_cache: int = -1"),
		"la respuesta se guarda, y en estatico para compartirla entre instancias")

	# El cuerpo tiene que salir por la cache. Si las tres consultas quedaran
	# fuera del `if`, la cache existiria y no ahorraria nada.
	var at: int = src.find("func is_touch_controls_active")
	if _check(at > 0, "existe is_touch_controls_active()"):
		var body: String = src.substr(at, 500)
		_check(body.contains("if _touch_controls_cache < 0:"),
			"y solo consulta al motor cuando no esta resuelta")
		var guard_at: int = body.find("if _touch_controls_cache < 0:")
		for what: String in ["ProjectSettings.get_setting", "OS.has_feature",
				"DisplayServer.is_touchscreen_available"]:
			var where: int = body.find(what)
			_check(where > guard_at,
				"`%s` queda dentro de la rama de resolucion" % what)

	# Un `bool` no tiene "sin resolver", asi que el centinela tiene que ser el
	# tercer estado de un entero y no un booleano con bandera aparte.
	_check(not src.contains("static var _touch_controls_cache: bool"),
		"el centinela no es un bool disfrazado")

	# --- La premisa: nadie escribe el ajuste en caliente --------------------
	var writers: PackedStringArray = []
	_scan("res://", writers)
	_check(writers.is_empty(),
		"nadie escribe %s en tiempo de ejecucion%s" % [SETTING,
			"" if writers.is_empty() else " (%s)" % ", ".join(writers)])

	_finish()


## Busca `set_setting`/asignaciones sobre el ajuste fuera del plugin del editor.
func _scan(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			# `tools/` fuera: esta prueba nombra el ajuste Y la palabra
			# `set_setting` para poder describir lo que busca, asi que
			# escaneandose a si misma se declara rota. Los guards no corren en
			# el juego, de todas formas.
			if not name.begins_with(".") and name != "precompiled_astc_imports" \
					and not (dir_path == "res://" and name == "tools"):
				_scan(full, out)
		elif name.ends_with(".gd") and full != DECLARES:
			var text: String = FileAccess.get_file_as_string(full)
			if text.contains(SETTING) and text.contains("set_setting"):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - la consulta de tactil se resuelve una vez por sesion")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
