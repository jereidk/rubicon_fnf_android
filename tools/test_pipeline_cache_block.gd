extends SceneTree

## A device that crashes on its own Vulkan pipeline cache stops being given one.
##
## The report: the game opens and plays on a fresh install, and from the second
## launch onward it closes itself the moment the shop finishes loading. Same
## phone, same 6GB, every time. Nothing in this project explains that - but
## Godot writes a pipeline cache to disk on the first run and hands it to the
## driver on the next, and the driver consumes it at bulk pipeline creation,
## which here is the preload sweep at the end of exactly that load.
##
## The mechanism has two halves and only one of them can be tested anywhere:
##
##   * the BOOKKEEPING - count boots that never reached a finished preload,
##     latch after two, clear the latch when the driver UUID moves. Pure logic
##     over saved state, driven here for real.
##   * the BLOCK - leave a plain file where `user://vulkan` should be, so
##     make_dir_recursive() fails and the cache is never written again.
##     Exercised here against the real filesystem.
##
## What no gate in this repo can reach is whether a Vulkan driver then behaves:
## `--script` has no RenderingDevice, and neither does CI. That half is checked
## on the phone or not at all, and this file does not pretend otherwise.
##
## The one thing worth being loud about: this is a mechanism that makes a file
## the player never asked for and never sees, on their storage, forever. So the
## reverse has to work as surely as the forward, and both directions are driven
## below - including the case where the block has to replace a directory that
## already has a cache in it.
##
## Run with:
##   godot --headless --path . --script tools/test_pipeline_cache_block.gd

const SETTINGS := "res://menus/settings.gd"
const CAMERA := "res://lullaby_mod/scripts/lullaby/lullaby_preload_camera.gd"

## The path the engine binary actually uses (`user://vulkan/pipelines.%s.%s`),
## not a path this file decided on.
const CACHE_PATH := "user://vulkan"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var settings: String = _read(SETTINGS)

	_wiring_checks(settings)
	_bookkeeping_checks(settings)
	_override_checks(settings)
	_filesystem_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _wiring_checks(settings: String) -> void:
	_check(settings.contains('const PIPELINE_CACHE_PATH := "%s"' % CACHE_PATH),
		"la ruta es la que usa el binario de Godot, no una inventada")

	# Persistidas o el mecanismo entero no existe: la cuenta que sobrevive en
	# disco ES el parte de defuncion de la sesion anterior.
	for name: String in ["lullaby_unsafe_boots", "lullaby_pipeline_cache_blocked"]:
		_check(settings.contains("var %s" % name), "%s existe" % name)
		_check(name.begins_with("lullaby_"),
			"...y lleva prefijo `lullaby_`, o save() no la guarda")

	var ready_body: String = _func_body(settings, "_ready")
	var guard_at: int = ready_body.find("_guard_pipeline_cache()")
	var check_at: int = ready_body.find("_check_shader_cache()")
	_check(guard_at >= 0 and check_at >= 0 and guard_at > check_at,
		"_ready mira la cache DESPUES de latchear el UUID del driver")

	var guard: String = _func_body(settings, "_guard_pipeline_cache")
	_check(guard.contains("RenderingServer.get_rendering_device() == null"),
		"sin RenderingDevice no se toca nada (GL y headless caen ahi)")
	_check(guard.contains("shader_cache_cold"),
		"un driver nuevo limpia el bloqueo, o un arreglo del fabricante no llegaria nunca")

	# Y el unico sitio que puede declarar sana una sesion.
	var camera: String = _read(CAMERA)
	var finish: String = _func_body(camera, "finish_preload")
	# La LLAMADA, no el nombre. La primera version pedia solo que
	# "mark_boot_safe" apareciese en el cuerpo, y la linea del has_method() ya
	# lo hace - asi que sustituir la llamada por `pass` pasaba en verde.
	_check(finish.contains("settings.mark_boot_safe()"),
		"la camara de precarga marca el arranque como sano al terminar")
	_check(finish.contains("has_method(\"mark_boot_safe\")"),
		"...en blando, que esta camara tambien corre sin autoloads")


## The decision table, driven rather than described.
func _bookkeeping_checks(settings: String) -> void:
	var threshold: int = 0
	var re := RegEx.create_from_string("const UNSAFE_BOOTS_BEFORE_BLOCK := (\\d+)")
	var m: RegExMatch = re.search(settings)
	if m != null:
		threshold = int(m.get_string(1))
	_check(threshold == 2, "hacen falta 2 arranques fallidos seguidos (son %d)" % threshold)

	# El modelo de lo que hace _guard_pipeline_cache, para poder recorrer los
	# arranques sin necesitar el autoload ni un driver.
	var boots: int = 0
	var blocked: bool = false

	# Tres arranques sanos: nunca se bloquea.
	for i in 3:
		var step: Array = _step(boots, blocked, threshold, false, true)
		boots = step[0]
		blocked = step[1]
	_check(not blocked and boots == 0,
		"tres arranques sanos no bloquean nada (boots=%d)" % boots)

	# La secuencia real del telefono que reporto esto, arranque por arranque.
	# Se comprueba entera y no solo el final, porque el detalle que importa es
	# CUANDO empieza a servir: la decision se toma al principio de un arranque,
	# pero el driver ya leyo la cache antes de que corriese ningun script - asi
	# que el arranque que bloquea todavia se cae, y el que se salva es el
	# siguiente. Eso es un crash mas del que parece a primera vista, y es la
	# razon por la que el umbral no puede subirse "por prudencia".
	var one: Array = _step(boots, blocked, threshold, false, false)
	_check(not one[1] and one[0] == 1,
		"1er fallo: no bloquea - cerrar la app durante una carga es normal")

	var two: Array = _step(one[0], one[1], threshold, false, false)
	_check(not two[1] and two[0] == 2,
		"2o fallo: tampoco, la cuenta se toma al ARRANCAR, no al caerse")

	var three: Array = _step(two[0], two[1], threshold, false, false)
	_check(three[1], "3er arranque: ve los dos fallos y bloquea (y aun asi se cae)")

	# Y bloqueado se queda, aunque a partir de aqui vaya bien: es justamente
	# que vaya bien lo que demuestra que el bloqueo hace falta.
	var fourth: Array = _step(three[0], three[1], threshold, false, true)
	_check(fourth[1] and fourth[0] == 0,
		"4o: arranca sin cache, funciona, y el bloqueo NO se levanta por eso")

	var fifth: Array = _step(fourth[0], fourth[1], threshold, false, true)
	_check(fifth[1], "y sigue bloqueado indefinidamente")

	# Hasta que cambia el driver, que es lo unico que puede haberlo arreglado.
	var newdrv: Array = _step(fifth[0], fifth[1], threshold, true, true)
	_check(not newdrv[1], "un driver nuevo lo desbloquea y le da otra oportunidad")


## The row on the first-boot screen, and the thing it must not do.
##
## The override exists because the automatic path takes three launches to heal
## a phone that dies on every one. What it must not do is quietly rearm the
## automatic decision underneath the player: an override that kept counting
## unsafe boots would flip a KEEP back to blocked after two more launches, and
## the player would have no idea why the setting they chose stopped applying.
func _override_checks(settings: String) -> void:
	_check(settings.contains("enum PipelineCacheMode { AUTOMATIC = 0, KEEP = 1, DISCARD = 2 }"),
		"los tres modos existen y AUTOMATIC es el 0, que es el que trae la escena")
	_check(settings.contains("var lullaby_pipeline_cache_mode"),
		"el modo se guarda (prefijo `lullaby_`)")

	var guard: String = _func_body(settings, "_guard_pipeline_cache")
	var override_at: int = guard.find("!= PipelineCacheMode.AUTOMATIC")
	var auto_at: int = guard.find("shader_cache_cold")
	_check(override_at >= 0 and auto_at > override_at,
		"lo que eligio el jugador se mira ANTES que la decision automatica")
	# Dentro de la rama del override y no en toda la funcion: la rama
	# automatica tambien pone la cuenta a cero, asi que buscarlo en el cuerpo
	# entero pasaba en verde con el reseteo del override borrado.
	var branch: String = ""
	if override_at >= 0 and auto_at > override_at:
		branch = guard.substr(override_at, auto_at - override_at)
	_check(branch.contains("lullaby_unsafe_boots = 0"),
		"...y corta la cuenta, o el automatismo rearmaria por debajo")
	_check(branch.contains("return"),
		"...y se va, sin volver a caer en la decision automatica")

	var setter: String = _func_body(settings, "set_pipeline_cache_mode")
	_check(setter.contains("set_pipeline_cache_blocked("),
		"elegir Discard bloquea la escritura YA, no en el arranque siguiente")
	_check(setter.contains("RenderingServer.get_rendering_device() != null"),
		"...salvo sin RenderingDevice, donde no hay nada que bloquear")
	_check(setter.contains("save("), "y se persiste")

	# Volver a Automatic tiene que soltar el pestillo, no solo el override.
	var body_after_match: String = setter.substr(setter.find("match mode:"))
	_check(body_after_match.contains("_:") \
			and body_after_match.contains("lullaby_pipeline_cache_blocked = false"),
		"volver a Automatic suelta el pestillo, no deja al jugador bloqueado por una decision que retiro")


## One boot: returns [unsafe_boots, blocked] after it.
func _step(boots: int, blocked: bool, threshold: int, cold: bool, survives: bool) -> Array:
	if blocked and cold:
		blocked = false
		boots = 0
	if not blocked and boots >= threshold:
		blocked = true
	boots += 1
	if survives:
		boots = 0
	return [boots, blocked]


## The filesystem half, against the real filesystem.
func _filesystem_checks() -> void:
	var settings_script: GDScript = load(SETTINGS)
	_check(settings_script != null, "settings.gd carga")
	if settings_script == null:
		return
	if not settings_script.has_method("set_pipeline_cache_blocked"):
		_check(false, "set_pipeline_cache_blocked es static y alcanzable sin el autoload")
		return
	_check(true, "set_pipeline_cache_blocked es static y alcanzable sin el autoload")

	# Punto de partida realista: el directorio existe y tiene una cache dentro,
	# que es como esta un telefono que ya arranco una vez.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_PATH))
	var planted: FileAccess = FileAccess.open(CACHE_PATH + "/pipelines.test.cache", FileAccess.WRITE)
	if planted != null:
		planted.store_string("no soy una cache de verdad")
		planted.close()
	_check(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CACHE_PATH)),
		"de partida user://vulkan es un directorio con una cache dentro")

	settings_script.set_pipeline_cache_blocked(true)
	_check(FileAccess.file_exists(CACHE_PATH),
		"bloquear deja un FICHERO donde iba el directorio")
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CACHE_PATH)),
		"...y el directorio con su cache ya no esta")

	# Lo que hace que sirva de algo, comprobado por el RESULTADO y no por el
	# mecanismo. La primera version de esta linea exigia que
	# make_dir_recursive() fallase, y no falla: devuelve OK y no crea nada,
	# que es enganoso pero irrelevante. Lo que decide es si Godot puede
	# escribir la cache dentro, y no puede.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_PATH))
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CACHE_PATH)),
		"...y make_dir_recursive() no consigue crear el directorio igualmente")
	var written: FileAccess = FileAccess.open(
		CACHE_PATH + "/pipelines.test.cache", FileAccess.WRITE)
	_check(written == null,
		"y escribir la cache dentro FALLA, que es lo unico que hace falta (err=%d)"
			% FileAccess.get_open_error())
	if written != null:
		written.close()

	# Idempotente: se re-afirma en cada arranque.
	settings_script.set_pipeline_cache_blocked(true)
	_check(FileAccess.file_exists(CACHE_PATH), "bloquear dos veces no rompe nada")

	# Y la vuelta atras, que tiene que funcionar igual de bien que la ida.
	settings_script.set_pipeline_cache_blocked(false)
	_check(not FileAccess.file_exists(CACHE_PATH), "desbloquear retira el fichero")
	_check(DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(CACHE_PATH)) == OK,
		"...y Godot puede volver a crear su directorio")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_PATH))


func _func_body(text: String, name: String) -> String:
	var head: int = -1
	var from: int = 0
	while true:
		var at: int = text.find("func %s(" % name, from)
		if at < 0:
			break
		# Solo el de nivel superior: `static func` y los de clases internas
		# tambien contienen "func x(" y no son este.
		if at == 0 or text[at - 1] == "\n":
			head = at
			break
		from = at + 1
	if head < 0:
		_check(false, "%s() existe al nivel superior" % name)
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
