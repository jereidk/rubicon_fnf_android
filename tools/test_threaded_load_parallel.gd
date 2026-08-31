extends SceneTree

## Las dependencias de una escena se cargan en paralelo, no en serie.
##
## `ResourceLoader.load_threaded_request()` lleva `use_sub_threads` en `false`
## por defecto, asi que las 348 dependencias de Chimera se resolvian una detras
## de otra en un solo hilo del pool, en un telefono de ocho nucleos.
##
## El comentario de `lullaby_scene_changer.gd` ya culpaba del paron al solape
## entre destruir la escena vieja y pedir la nueva, y ese arreglo -los dos
## `process_frame`- bajo el paron de Chimera de 9-11s a 4s. Pero el log
## 10226-4fe0a6db conserva la firma entera:
##
##     50.0% at 11384ms deps=196/348 status=in_progress
##     50.0% at 14407ms deps=196/348 status=in_progress
##     50.0% at 15412ms deps=233/348 +chimera_house.tscn +mdl_chimera_camera.gltf
##
## Cuatro segundos con el contador clavado y 37 dependencias resolviendose una
## detras de otra.
##
## Lo que fija este guard es que la llamada pasa el parametro, que la constante
## existe para poder apagarlo de una linea, y que el unico
## ResourceFormatLoader propio del proyecto sigue siendo stateless - que es lo
## que hace seguro que Godot lo llame desde varios hilos.
##
## Run with:
##   godot --headless --path . --script tools/test_threaded_load_parallel.gd

const CHANGER := "res://lullaby_mod/scripts/lullaby/loading/lullaby_scene_changer.gd"
const CHART_LOADER := "res://addons/rubicon/scripts/data/chart/rubichart_file_loader.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var code: String = _read(CHANGER)
	if not _check(not code.is_empty(), "lullaby_scene_changer.gd se lee"):
		_finish()
		return

	_check(code.contains("const USE_SUB_THREADS"),
		"la constante existe, para poder apagarlo de una linea")
	_check(code.contains('load_threaded_request(_watching_path, "", USE_SUB_THREADS)'),
		"y la peticion la pasa, en vez de heredar el false por defecto")

	var script: GDScript = load(CHANGER)
	if _check(script != null, "el cambiador de escena carga"):
		_check(bool(script.get_script_constant_map().get("USE_SUB_THREADS")),
			"esta encendido")

	# Lo que hace segura la opcion: con sub-hilos Godot puede llamar a un
	# ResourceFormatLoader propio desde varios a la vez. Si este dejara de ser
	# stateless, la opcion dejaria de ser segura y nadie se enteraria.
	var loader: String = _read(CHART_LOADER)
	_check(not loader.is_empty(), "el cargador de charts se lee")
	# Sin sangrar: solo las de nivel de clase. Las `var` de dentro de `_load()`
	# son LOCALES, y son precisamente lo que hace seguro llamarlo desde varios
	# hilos - contarlas fue el primer intento de esta comprobacion y daba un
	# falso positivo con las seis locales del cargador.
	var members: PackedStringArray = []
	for line: String in loader.split("\n"):
		if line.begins_with("var ") or line.begins_with("@export var"):
			members.append(line.strip_edges())
	_check(members.is_empty(),
		"RubiChartFileLoader sigue sin estado propio%s" % [
			"" if members.is_empty() else " (%s)" % ", ".join(members)])

	_finish()


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - las dependencias pueden ir en paralelo")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
