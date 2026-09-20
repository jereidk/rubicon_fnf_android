extends SceneTree

## Runner de tests de addons/gdanimate/. Sin dependencias externas (no GUT):
## descubre test_*.gd en este mismo directorio, llama a su run(tree: SceneTree)
## -> Dictionary, imprime PASS/FAIL, sale con exit code 0 (todo paso) o 1.
##
## Uso:
##   xvfb-run -a <Godot> --rendering-driver opengl3 --path <repo> \
##     -s res://addons/gdanimate/tests/run_tests.gd
##
## --headless NO sirve para esto: el rendering server no llega a dibujar nada
## y las capturas de Viewport quedan vacias. Hace falta xvfb-run + un driver de
## render real (Mesa software alcanza, confirmado en Etapa 0).
##
## Contrato de cada test_*.gd: una clase con `func run(tree: SceneTree) ->
## Dictionary`, que devuelve al menos {"name": String, "passed": bool,
## "failures": Array[String]}, y opcionalmente {"png": String} si genero una
## captura en tests/visual/output/.

const TESTS_DIR := "res://addons/gdanimate/tests/"

var _started: bool = false


func _process(_delta: float) -> bool:
	# _run_all() usa `await` (para dejar frames correr entre tests), asi que
	# es una coroutine: llamarla sin await no la espera, solo la arranca y
	# vuelve enseguida. Si este _process devolviera true despues de eso, el
	# SceneTree se cierra en el frame siguiente y mata la coroutine a mitad
	# de camino - antes de que run_tests corriera un solo test. _run_all()
	# llama a quit() ella misma cuando termina de verdad; aca siempre
	# devolvemos false y dejamos que sea quit() quien corte el loop.
	if not _started:
		_started = true
		_run_all()
	return false


func _run_all() -> void:
	var dir: DirAccess = DirAccess.open(TESTS_DIR)
	if dir == null:
		printerr("No se pudo abrir %s" % TESTS_DIR)
		quit(1)
		return

	var test_files: PackedStringArray = []
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			test_files.push_back(f)
		f = dir.get_next()
	dir.list_dir_end()
	test_files.sort()

	var total: int = 0
	var passed: int = 0
	var failed_names: Array[String] = []

	for file_name: String in test_files:
		var script: GDScript = load(TESTS_DIR + file_name)
		var instance: Object = script.new()
		if not instance.has_method("run"):
			continue

		total += 1
		print("--- %s ---" % file_name)
		var result: Dictionary = await instance.run(self)
		var ok: bool = result.get("passed", false)
		var test_name: String = result.get("name", file_name)

		if ok:
			passed += 1
			print("PASS: %s" % test_name)
		else:
			print("FAIL: %s" % test_name)
			for msg: String in result.get("failures", []):
				print("  - %s" % msg)
			failed_names.push_back(file_name)

		var png: String = result.get("png", "")
		if not png.is_empty():
			print("  png: %s" % png)

	print("")
	print("%d/%d tests passed" % [passed, total])
	if not failed_names.is_empty():
		print("Fallaron: %s" % ", ".join(failed_names))

	quit(0 if failed_names.is_empty() else 1)
