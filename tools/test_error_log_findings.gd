extends SceneTree

## The four bugs the first .error file found, pinned.
##
## Worth one file rather than four, because they are one story: the device had
## been raising all of these for as long as they have existed and nothing could
## see them. The moment OS.add_logger() was wired up, one session named them.
##
## Two of them are the same mistake in two places, and it is a mistake this
## project is set up to keep making: `graphics_disable_shader_effects` strips
## every material whose shader is in EFFECT_SHADER_PATHS, that setting is part
## of Very Low, and Very Low is what a fresh install runs. So any script that
## reads `%Something.material` and uses it without checking is broken on the
## default preset. trance_shaders.gd did it in _process - an error per frame of
## Safety Lullaby, the song already at 30fps.
##
## Run with:
##   godot --headless --path . --script tools/test_error_log_findings.gd

const SFX := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/console_sfx.gd"
const INPUT_BUTTON := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/buttons/settings/input_button.gd"
const TRANCE := "res://lullaby_mod/songs/safety_lullaby/trance_shaders.gd"
const NOTEPAD := "res://lullaby_mod/scripts/lullaby/collectors_shop/props/prp_notepad.gd"
const SETTINGS := "res://menus/settings.gd"
const CONSOLE := "res://lullaby_mod/resources/console/console.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_sound_checks()
	_input_row_checks()
	_stripped_material_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## Every name the console can ask for actually resolves to a file.
##
## The resolver used to try `shop/console/<name>.wav` and then
## `misc/<name>.mp3`, and sfx_soulroom_select is a .res in shop/console/, so
## the select sound was silent and the log said "No loader found". Checked
## against the real filesystem here, so a sound added in a fourth format or a
## fifth folder fails this instead of going quiet on a phone.
func _sound_checks() -> void:
	var code: String = _read(SFX)
	var dirs: PackedStringArray = _string_array(code, "const SOUND_DIRS")
	var extensions: PackedStringArray = _string_array(code, "const SOUND_EXTENSIONS")
	_check(dirs.size() >= 2 and extensions.size() >= 3,
		"el resolutor prueba %d carpetas x %d extensiones" % [dirs.size(), extensions.size()])
	_check(extensions.has(".res"),
		".res entre ellas - sfx_soulroom_select es un .res y por eso no sonaba")

	# Y ahora contra los nombres que el juego emite de verdad.
	var names: Dictionary = {}
	var emit := RegEx.create_from_string('play_sound\\.emit\\("([^"]+)"')
	_walk_scripts("res://lullaby_mod", emit, names)

	_check(not names.is_empty(), "se encuentran los nombres que se emiten (%d)" % names.size())
	var silent: PackedStringArray = []
	for name: String in names:
		var found := false
		for dir: String in dirs:
			for extension: String in extensions:
				if ResourceLoader.exists(dir + name + extension):
					found = true
		if not found:
			silent.append("%s (%s)" % [name, names[name]])
	_check(silent.is_empty(), "y todos resuelven a un fichero%s"
		% ["" if silent.is_empty() else ": " + ", ".join(silent)])


## A keybind row for an action that is deliberately not rebindable.
func _input_row_checks() -> void:
	var code: String = _read(INPUT_BUTTON)
	var ready_body: String = _func_body(code, "_ready")
	_check(not ready_body.contains("Settings.input_map[input][0]"),
		"la fila ya no indexa el diccionario a ciegas")
	_check(ready_body.contains("source.get(input, [])"),
		"...lo consulta, que es lo que permite que falte")
	_check(ready_body.contains("visible = false"),
		"y una accion ausente esconde la fila en vez de reventar _ready")

	# Y la razon por la que faltan: estan excluidas a proposito.
	var settings: String = _read(SETTINGS)
	var exclusions: int = settings.find("INPUT_EXCLUSIONS")
	var block: String = settings.substr(exclusions, 800)
	var excluded: PackedStringArray = []
	for action: String in ["volume_up", "volume_down", "volume_mute"]:
		if block.contains('&"%s"' % action):
			excluded.append(action)
	_check(excluded.size() == 3,
		"las tres de volumen siguen excluidas de input_map (%d)" % excluded.size())

	# Las filas siguen en la escena - se esconden solas, no se borraron.
	var scene: String = _read(CONSOLE)
	var rows: int = 0
	for action: String in excluded:
		if scene.contains('input = &"%s"' % action):
			rows += 1
	_check(rows == 3,
		"y sus %d filas siguen en la consola, escondiendose solas" % rows)


## The two scripts that read a material the default preset strips.
func _stripped_material_checks() -> void:
	var settings: String = _read(SETTINGS)
	var paths: PackedStringArray = _string_array(settings, "const EFFECT_SHADER_PATHS")
	_check(Array(paths).any(func(p: String) -> bool:
			return p.ends_with("shd_trance_water_hsv_contrast.gdshader")),
		"el shader del trance sigue en EFFECT_SHADER_PATHS, o sea que Very Low lo quita")

	var trance: String = _read(TRANCE)
	var ready_body: String = _func_body(trance, "_ready")
	_check(ready_body.contains("water == null") and ready_body.contains("set_process(false)"),
		"trance_shaders se retira cuando no hay material, en vez de fallar por frame")
	var process_at: int = trance.find("\nfunc _process")
	var ready_at: int = trance.find("\nfunc _ready")
	_check(ready_at >= 0 and process_at > ready_at,
		"...y lo decide antes de que _process pueda correr una vez")

	# Y esconde los rects al retirarse. La escena los trae VISIBLES con alpha 0
	# y quien los escondia era _update_rect_visibility(); un return antes de esa
	# llamada deja dos ColorRect a pantalla completa mezclandose cada frame en
	# la cancion que ya esta limitada por relleno. La primera version de este
	# arreglo hacia justo eso.
	var stand_down: String = ready_body.substr(ready_body.find("water == null"))
	stand_down = stand_down.substr(0, stand_down.find("set_process(false)"))
	_check(stand_down.contains("water_rect.visible = false")
			and stand_down.contains("radial_rect.visible = false"),
		"...y esconde los dos rects al retirarse, no los deja dibujando")

	var notepad: String = _read(NOTEPAD)
	_check(notepad.contains("if shader_material != null:"),
		"prp_notepad comprueba el material antes de escribirle")
	var reload: String = _func_body(notepad, "_reload_page")
	var guard_at: int = reload.find("if shader_material != null:")
	var add_at: int = reload.find("sub_viewport.add_child(selector)")
	_check(guard_at >= 0 and add_at > guard_at,
		"...y el selector se añade igual, que es lo que el error se llevaba por delante")


## Collects regex captures across every .gd under `dir`, value = file name.
func _walk_scripts(dir_path: String, re: RegEx, out: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name: String in dir.get_directories():
		_walk_scripts(dir_path.path_join(name), re, out)
	for name: String in dir.get_files():
		if not name.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string(dir_path.path_join(name))
		for m in re.search_all(text):
			if not out.has(m.get_string(1)):
				out[m.get_string(1)] = name


## The quoted strings of an `Array[String]` const, in order.
##
## Anchored on `= [` and not on the const name, because the FIRST `]` after
## the name closes `Array[String]` in the declaration, not the literal - the
## first version of this read zero entries out of a list of four and reported
## the resolver as empty.
func _string_array(code: String, prefix: String) -> PackedStringArray:
	var head: int = code.find(prefix)
	if head < 0:
		_check(false, "%s existe" % prefix)
		return PackedStringArray()
	var open: int = code.find("= [", head)
	if open < 0:
		_check(false, "%s es una lista" % prefix)
		return PackedStringArray()
	var out: PackedStringArray = []
	for m in RegEx.create_from_string('"([^"]+)"').search_all(
			code.substr(open, code.find("]", open) - open)):
		out.append(m.get_string(1))
	return out


func _func_body(text: String, name: String) -> String:
	var head: int = -1
	var from: int = 0
	while true:
		var at: int = text.find("func %s(" % name, from)
		if at < 0:
			break
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
