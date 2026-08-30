extends SceneTree

## El vídeo no puede corregir la deriva más de una vez por segundo.
##
## El fallo que cubre me lo comí yo entero y salió en el dispositivo, no aquí.
## Para curar una desincronía audible bajé `max_drift` de 0.25 a 0.05, y eso
## cerró un bucle: un seek de Theora retrocede por el fichero en bloques de
## 512 KB buscando el keyframe anterior, el seek alarga el fotograma, el
## fotograma largo genera más deriva, la deriva dispara otro seek. La región del
## componente en el log fue
##
##     PhotoshootVideo=23.31/11.52
##
## 23.31 ms de media sobre 927 fotogramas, contra los ~3.1 ms que cuesta
## decodificar 960x540 según la fórmula medida en el propio componente.
##
## El docstring de `max_drift` ya avisaba - "corregir por fotograma sería peor
## que la deriva" - y aun así el número se podía bajar sin que nada lo frenara.
## Ahora hay un techo que no depende de acertar con el umbral.
##
## Run with:
##   godot --headless --path . --script tools/test_video_seek_ceiling.gd

const VIDEO := "res://lullaby_mod/scripts/lullaby/cutscene/lullaby_cutscene_video.gd"
const SCENE := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var code: String = FileAccess.get_file_as_string(VIDEO)
	_check(not code.is_empty(), "el componente se lee")

	_check(code.contains("@export var min_seek_interval"),
		"existe un techo entre correcciones")
	_check(code.contains("_seek_allowed()"),
		"y el seek pasa por el")
	_check(code.contains("_last_seek_at = here"),
		"y se apunta cuando se corrige, o el techo no baja nunca")

	# El techo se mide con el reloj de la cancion, el mismo que decide la
	# deriva. Con dos relojes distintos el bucle vuelve a poder cerrarse.
	_check(code.contains("clock.current_animation_position - _last_seek_at"),
		"medido con el reloj de la cancion, no con el de pared")

	# Y la escena no vuelve a bajar el umbral por su cuenta.
	var scene: String = FileAccess.get_file_as_string(SCENE)
	_check(not scene.contains("max_drift = 0.05"),
		"Chimera ya no fuerza max_drift = 0.05")

	var block_at: int = scene.find('name="PhotoshootVideo"')
	if block_at >= 0:
		var tail: String = scene.substr(block_at, 400)
		var override: int = tail.find("max_drift = ")
		if override >= 0:
			var value: float = tail.substr(override + 12, 8).strip_edges().to_float()
			_check(value >= 0.2,
				"y si lo sobreescribe, no por debajo de 0.2 (%.2f)" % value)
		else:
			_check(true, "y no sobreescribe max_drift en absoluto")

	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - la correccion de deriva tiene techo")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
