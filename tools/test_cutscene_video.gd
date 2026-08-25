extends SceneTree

## LullabyCutsceneVideo: la sustitución de una cutscene viva por su vídeo.
##
## Lo que este fichero defiende, y por qué cada cosa importa
## --------------------------------------------------------
## 1. Se retira en silencio si el preset no lo pide. El vídeo es para gama baja;
##    en un teléfono que aguanta la escena viva, la escena viva es mejor.
##
## 2. Se retira en silencio si el .ogv no existe. Esto NO es defensivo por
##    gusto: el vídeo lo produce CI, así que todo checkout de desarrollo corre
##    sin él y la canción tiene que funcionar igual. Mismo criterio que
##    `trance_shaders.gd` cuando Very Low le quita el material - y ese caso
##    llegó al dispositivo como un error rojo por frame antes de arreglarse.
##
## 3. Apaga el `process_mode` de la cutscene, no su `visible`. Las dos mitades
##    importan:
##    - apagar el proceso es lo ÚNICO que ahorra algo, porque el coste medido
##      son 57 AnimationPlayer y 15 AnimationTree evaluándose, no los 5 draw
##      calls (`draw=3-7 prims=68-76 over=0.6x cpu_render=0.6-1.7ms`);
##    - no tocar `visible` es obligatorio, porque el Timeline de la canción
##      anima `../IntroCutscene:visible` con una pista y escribir la misma
##      propiedad desde fuera pelearía con ella. `settings.gd` ya documenta esa
##      trampa para las Light2D; es la razón de que allí se use `enabled`.
##
## 4. Devuelve el mando restaurando el `process_mode` AUTHOREADO, no INHERIT.
##
## 5. Solo corrige la deriva por encima del umbral. Un seek de Theora retrocede
##    por el fichero en bloques de 512 KB hasta el keyframe anterior; corregir
##    cada frame costaría más que la deriva.
##
## Limitación conocida: en headless el servidor de vídeo no decodifica (medido:
## un reproductor en headless cuesta lo mismo que ninguno), así que aquí no se
## comprueba que salgan píxeles. Se comprueba la lógica de sustitución, que es
## la que puede romper la canción.
##
## Run with:
##   godot --headless --path . --script tools/test_cutscene_video.gd

const COMPONENT := "res://lullaby_mod/scripts/lullaby/cutscene/lullaby_cutscene_video.gd"
const PRESET := "res://lullaby_mod/scripts/lullaby/settings/lullaby_quality_preset.gd"
const SETTINGS := "res://menus/settings.gd"
const FIXTURE := "res://tools/fixtures/tiny_cutscene.ogv"

var _failures: int = 0
var _checks: int = 0


## Cuenta los errores del motor mientras está instalado.
##
## Godot 4.7 trae `OS.add_logger()` y una clase `Logger` instanciable; el
## proyecto ya la usa en `lullaby_error_log.gd`. `_log_error` corre en el hilo
## que levanta el error y `rationale` trae el mensaje del motor.
class _ErrorSink extends Logger:
	var errors: int = 0
	var messages: PackedStringArray = []

	func _log_error(_function: String, _file: String, _line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array) -> void:
		if error_type != 0:  # 0 = error, 1 = warning
			return
		errors += 1
		if messages.size() < 4:
			messages.append(rationale if not rationale.is_empty() else code)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame

	_wiring_checks()
	await _behaviour_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _wiring_checks() -> void:
	var code: String = FileAccess.get_file_as_string(COMPONENT)
	_check(not code.is_empty(), "lullaby_cutscene_video.gd se lee")

	# El ajuste viaja por las tres partes del preset o no viaja.
	var preset: String = FileAccess.get_file_as_string(PRESET)
	_check(preset.contains("@export var prefer_cutscene_video"),
		"el preset declara prefer_cutscene_video")
	_check(preset.contains("settings.graphics_prefer_cutscene_video = prefer_cutscene_video"),
		"...y apply() lo copia a los ajustes")
	_check(preset.contains("settings.graphics_prefer_cutscene_video == prefer_cutscene_video"),
		"...y is_matching() lo compara, si no el preset se ve 'Custom' al tocarlo")

	var settings: String = FileAccess.get_file_as_string(SETTINGS)
	_check(settings.contains("var graphics_prefer_cutscene_video"),
		"los ajustes tienen el campo")
	# El prefijo graphics_ es lo que hace que save()/load_from() lo persistan.
	_check(settings.contains("graphics_prefer_cutscene_video"),
		"...con prefijo graphics_, que es lo que lo persiste")

	# La trampa del `visible`.
	_check(not code.contains("live_cutscene.visible") and not code.contains(".visible = "),
		"el componente NO escribe visible en la cutscene (pelearía con la pista)")
	_check(code.contains("live_cutscene.process_mode = Node.PROCESS_MODE_DISABLED"),
		"...apaga el process_mode, que es donde está el coste medido")


func _behaviour_checks() -> void:
	var script: GDScript = load(COMPONENT)
	_check(script != null, "el componente carga")
	if script == null:
		return
	_check(ResourceLoader.exists(FIXTURE), "existe el .ogv de prueba")

	# --- 1. El preset no lo pide: no se toca nada.
	var off := _mount(script, FIXTURE, false)
	_check(off.live.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"preset apagado: la cutscene conserva su process_mode authoreado")
	_check(_video_players(off.node) == 0, "preset apagado: no se crea reproductor")
	off.node.queue_free()
	await process_frame

	# --- 2. El preset lo pide pero no hay fichero: se retira igual, EN SILENCIO.
	#
	# El silencio es la mitad que importa y la que casi se me escapa. Quitar la
	# guarda `ResourceLoader.exists()` no cambia el comportamiento -`load()`
	# devuelve null y el componente se retira por la rama de abajo- así que una
	# prueba que solo mire el process_mode y el reproductor pasa igual. Lo que
	# sí cambia es que `load()` de un fichero que no existe empuja un error rojo
	# por cada canción cargada. Este proyecto tiene un `.error` entero dedicado a
	# cazar justo eso, así que aquí se cuenta con la misma API: OS.add_logger().
	var sink := _ErrorSink.new()
	OS.add_logger(sink)
	var missing := _mount(script, "res://tools/fixtures/no_existe.ogv", true)
	OS.remove_logger(sink)
	_check(missing.live.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"sin .ogv: la cutscene sigue viva (CI aún no lo produjo)")
	_check(_video_players(missing.node) == 0, "sin .ogv: no se crea reproductor")
	_check(sink.errors == 0,
		"sin .ogv: y sin un solo error rojo (%d capturados: %s)"
			% [sink.errors, ", ".join(sink.messages)])
	missing.node.queue_free()
	await process_frame

	# --- 3. Con preset y fichero: sustituye.
	var on := _mount(script, FIXTURE, true)
	_check(_video_players(on.node) == 1, "con preset y fichero: hay un reproductor")
	_check(on.live.process_mode == Node.PROCESS_MODE_DISABLED,
		"...y la cutscene deja de procesar")
	_check(on.live.visible, "...pero sigue visible: el nodo no le toca esa propiedad")

	# --- 4. Devuelve el mando al pasar el final, restaurando lo authoreado.
	on.clock.play(&"linea")
	on.clock.seek(9.0, true)
	on.node.call("_process", 0.016)
	_check(on.live.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"pasado el final: restaura el process_mode AUTHOREADO, no INHERIT")
	on.node.queue_free()
	await process_frame

	# --- 5. La deriva solo se corrige por encima del umbral.
	var drift := _mount(script, FIXTURE, true)
	drift.clock.play(&"linea")
	drift.node.set("max_drift", 0.25)
	# Dentro del umbral: ni un seek.
	drift.clock.seek(0.1, true)
	drift.node.call("_process", 0.016)
	_check(int(drift.node.call("drift_corrections")) == 0,
		"deriva por debajo del umbral: no se toca el reproductor")
	# Fuera del umbral: uno.
	drift.clock.seek(3.0, true)
	drift.node.call("_process", 0.016)
	_check(int(drift.node.call("drift_corrections")) == 1,
		"deriva por encima del umbral: un seek, no uno por frame")
	drift.node.call("_process", 0.016)
	_check(int(drift.node.call("drift_corrections")) <= 2,
		"...y no se dispara en cascada")
	drift.node.queue_free()
	await process_frame


## Monta el componente con una cutscene falsa y un reloj de verdad.
func _mount(script: GDScript, path: String, wanted: bool) -> Dictionary:
	var host := Node.new()
	root.add_child(host)

	# El singleton que el componente consulta. Un Node en /root con el nombre
	# que busca, para no depender del autoload real.
	var settings: Node = root.get_node_or_null(^"Settings")
	if settings == null:
		settings = Node.new()
		settings.name = "Settings"
		root.add_child(settings)
	settings.set("graphics_prefer_cutscene_video", wanted)

	var live := Node2D.new()
	live.name = "LiveCutscene"
	live.process_mode = Node.PROCESS_MODE_PAUSABLE
	host.add_child(live)

	var clock := AnimationPlayer.new()
	var anim := Animation.new()
	anim.length = 40.0
	var library := AnimationLibrary.new()
	library.add_animation(&"linea", anim)
	clock.add_animation_library(&"", library)
	host.add_child(clock)

	var node: Node = script.new()
	node.set("live_cutscene", live)
	node.set("video_path", path)
	node.set("clock", clock)
	node.set("starts_at", 0.0)
	node.set("ends_at", 8.0)
	host.add_child(node)

	return {"node": node, "live": live, "clock": clock, "host": host}


func _video_players(node: Node) -> int:
	var found: int = 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VideoStreamPlayer:
			found += 1
		for child in n.get_children():
			stack.append(child)
	return found


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
