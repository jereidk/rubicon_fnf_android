extends SceneTree

## The SKILLISSUE code and the "No Mechanics" setting it unlocks, end to end.
##
## This feature is six pieces in six files and every joint between them fails
## silently. The code can be missing from CODES, it can point at a flag name
## SaveData does not default, the setting can be absent from Settings (which
## makes it un-persisted rather than broken - `save()` picks members up off the
## `lullaby_` prefix, so a typo means the checkbox forgets itself every
## launch), the console row can name a property that does not exist, its
## unlock gate can name the wrong flag and leave the row visible to everyone,
## and - the one that matters most - a mechanic can simply never ask.
##
## That last one is why this file is not just a spelling test. If
## HeartbeatController never consults the setting, everything above still
## lines up: the code works, the checkbox appears, it saves, it loads, and the
## heartbeat starts anyway. Nothing anywhere reports a problem. So each of the
## three mechanics is checked at the exact entry point its song's timeline
## calls, by source, and named individually so a red line says which song lost
## its opt-out.
##
## Run with:
##   godot --headless --path . --script tools/test_no_mechanics.gd

const CODE := "SKILLISSUE"
const KEY := &"no_mechanics"
const FLAG := &"no_mechanics_unlocked"
const SETTING := &"lullaby_no_mechanics"

const CONSOLE := "res://lullaby_mod/resources/console/console.tscn"
const HACKS := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/hacks_tab.gd"
const SAVE := "res://lullaby_mod/scripts/lullaby/lullaby_save_data.gd"
const SETTINGS := "res://menus/settings.gd"
const HELPER := "res://lullaby_mod/scripts/lullaby/mechanics/lullaby_no_mechanics.gd"

## Each song's mechanic, and the entry point its timeline drives. The check is
## that the guard sits in THAT function - a call somewhere else in the file
## would pass a naive grep and still let the mechanic start.
const MECHANICS := {
	"safety lullaby (pendulo)": [
		"res://lullaby_mod/scripts/lullaby/mechanics/safety_lullaby/lullaby_pendulum_server.gd",
		"@export var started",
	],
	"monochrome (escritura)": [
		"res://lullaby_mod/scripts/lullaby/mechanics/monochrome/typing_challenge.gd",
		"@export var active",
	],
	"chimera (latido)": [
		"res://lullaby_mod/scripts/lullaby/mechanics/chimera/heartbeat_controller.gd",
		"func initialize(",
	],
}

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame

	_code_checks()
	_setting_checks()
	_mechanic_checks()
	_console_checks()

	print("")
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - SKILLISSUE apaga las tres mecanicas")
	quit(1 if _failures > 0 else 0)


func _code_checks() -> void:
	var hacks: GDScript = load(HACKS)
	_check("hacks_tab.gd carga", hacks != null)
	if hacks == null:
		return

	var codes: Dictionary = hacks.CODES
	_check("existe el codigo %s" % CODE, codes.has(CODE),
		"codigos: %s" % ", ".join(codes.keys()))
	if codes.has(CODE):
		_check("%s apunta a '%s'" % [CODE, KEY], StringName(codes[CODE]) == KEY,
			"-> %s" % codes[CODE])

	# El codigo se teclea en mayusculas (_on_code_submitted hace to_upper), asi
	# que una entrada en minusculas del diccionario seria inalcanzable.
	_check("%s esta escrito en mayusculas" % CODE, CODE == CODE.to_upper())


func _setting_checks() -> void:
	var save: String = FileAccess.get_file_as_string(SAVE)
	_check("el flag %s tiene valor por defecto" % FLAG, save.contains('&"%s"' % FLAG))

	var settings: String = FileAccess.get_file_as_string(SETTINGS)
	_check("Settings declara %s" % SETTING, settings.contains("var %s" % SETTING))
	# El prefijo es lo que hace que se guarde; sin el, la casilla se olvida en
	# cada arranque y no lo dice nadie.
	_check("y lo hace con el prefijo lullaby_ que lo persiste",
		String(SETTING).begins_with("lullaby_"))

	# Y que el ayudante responda, sin explotar, y que su respuesta por defecto
	# sea "mecanicas encendidas".
	#
	# Por defecto false y no true a proposito: el juego tal y como esta
	# authoreado es lo seguro, asi que una consulta que falle -sin autoload, en
	# un banco, en una escena suelta- nunca puede quitarle contenido a nadie
	# por accidente. Aqui el autoload SI existe (godot --script los carga), asi
	# que lo que se comprueba es el valor por defecto del ajuste.
	var helper: GDScript = load(HELPER)
	_check("LullabyNoMechanics carga", helper != null)
	if helper != null:
		_check("wanted() responde false por defecto - mecanicas encendidas",
			helper.wanted() == false)


func _mechanic_checks() -> void:
	for label: String in MECHANICS:
		var path: String = MECHANICS[label][0]
		var anchor: String = MECHANICS[label][1]
		var code: String = FileAccess.get_file_as_string(path)
		_check("[%s] %s se lee" % [label, path.get_file()], not code.is_empty())
		if code.is_empty():
			continue

		var start: int = code.find(anchor)
		_check("[%s] sigue existiendo `%s`" % [label, anchor], start >= 0)
		if start < 0:
			continue

		# Hasta la siguiente declaracion al margen izquierdo, que es donde
		# acaba la funcion o el setter.
		var end: int = code.find("\nfunc ", start + 1)
		var next_export: int = code.find("\n@export", start + 1)
		if next_export >= 0 and (end < 0 or next_export < end):
			end = next_export
		var body: String = code.substr(start, (end - start) if end > start else -1)

		_check("[%s] su punto de entrada consulta LullabyNoMechanics" % label,
			body.contains("LullabyNoMechanics.wanted()"))


func _console_checks() -> void:
	var scene: String = FileAccess.get_file_as_string(CONSOLE)
	_check("console.tscn se lee", not scene.is_empty())
	if scene.is_empty():
		return

	var head: int = scene.find('[node name="NoMechanics"')
	_check("la fila NoMechanics esta en la consola", head >= 0)
	if head < 0:
		return

	var tail: int = scene.find("\n[node ", head + 1)
	var block: String = scene.substr(head, (tail - head) if tail > head else -1)

	_check("cuelga de Gameplay",
		block.contains("SettingsSubmenu/Gameplay"))
	_check("mueve la propiedad %s" % SETTING,
		block.contains("property = &\"%s\"" % SETTING))
	_check("y arranca oculta, como las demas desbloqueables",
		block.contains("visible = false"))

	# El gate es un hijo, asi que va en el bloque SIGUIENTE, no en este.
	var gate: int = scene.find(
		'[node name="LullabyHideIfLocked" type="Node" parent="'
		+ 'TabContainer/Settings/PortraitBox/SettingsSubmenu/Gameplay/NoMechanics"')
	_check("tiene su LullabyHideIfLocked", gate >= 0)
	if gate >= 0:
		var gate_tail: int = scene.find("\n[node ", gate + 1)
		var gate_block: String = scene.substr(
			gate, (gate_tail - gate) if gate_tail > gate else -1)
		_check("que mira el flag %s" % FLAG,
			gate_block.contains('unlock_flag = &"%s"' % FLAG))


func _check(what: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-56s%s" % [what, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		printerr("  FALLO %-56s%s" % [what, "  (%s)" % detail if detail else ""])
