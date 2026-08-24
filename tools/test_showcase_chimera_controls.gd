extends SceneTree

## Showcase Mode has to show Chimera's mechanic controls AND play them.
##
## Two reports, two different failures, both silent.
##
## **The escape D-pad never appeared.** `_mechanic_wants_input()` opened with a
## bare `if crawl_timing.autoplay: return false`. That is right for the debug
## "Autoplay?" toggle, where nobody is watching the controls, and wrong for a
## showcase, where watching them is the point. LullabyShowcase exists precisely
## because that rule is one line and got copied to five call sites; this was the
## fifth, and the one nobody fixed.
##
## **The heartbeat button never lit up.** `flash_control()` handled exactly two
## shapes - something with `_flash()` (RubiconActionButton) and something with
## `_handle_touch()` (RubiconMechanicHitbox) - and its own docstring asserted
## Chimera's heartbeat and picture-taking zones were the first kind. They are
## not: both scenes wire a plain `Button`. So both branches fell through and the
## call did nothing, on every automatic beat of every showcase run, without an
## error. The fallback pulses `modulate`, which every CanvasItem has, so the
## function can no longer be wrong about a class.
##
## Run with:
##   godot --headless --path . --script tools/test_showcase_chimera_controls.gd

const SHOWCASE := "res://lullaby_mod/scripts/lullaby/settings/lullaby_showcase.gd"
const DPAD := "res://lullaby_mod/songs/chimera/scripts/chimera_escape_dpad.gd"
const HEART := "res://lullaby_mod/songs/chimera/scripts/chimera_heartbeat_touch_zone.gd"
const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"

var _failures: int = 0
var _checks: int = 0


## Textual and scene-level, not behavioural, and the reason is worth stating:
## `lullaby_showcase.gd` names the `Settings` autoload directly, and a --script
## SceneTree does not have autoload identifiers bound at compile time - the same
## constraint test_render_scale_report.gd already records. Loading the class to
## call flash_control() on it fails to compile before any assertion runs.
##
## So what is pinned here is the shape of the three lines that were wrong, plus
## the scene facts that falsified the old assumption - which is the half a
## behavioural test could not have caught anyway, since the bug was that
## flash_control did nothing and returned normally.
func _initialize() -> void:
	_source_checks()
	_scene_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _source_checks() -> void:
	var dpad: String = _strip_comments(_read(DPAD))
	_check(dpad.contains("LullabyShowcase.mechanic_controls_visible(crawl_timing.autoplay)"),
		"el D-pad pregunta a LullabyShowcase en vez de rechazar autoplay a secas")
	_check(not dpad.contains("if crawl_timing.autoplay:\n\t\treturn false"),
		"y ya no queda el rechazo directo")

	# Y que se toque solo: el pulso en el flanco de current_input.
	_check(dpad.contains("_last_autoplay_input"),
		"recuerda que input pedia el mecanico, para detectar el flanco")
	_check(dpad.contains("_flash()") and dpad.contains("crawl_timing.current_input"),
		"y pulsa cuando cambia, que es el golpe automatico")

	var heart: String = _strip_comments(_read(HEART))
	_check(heart.contains("LullabyShowcase.mechanic_controls_visible(heartbeat.autoplay)"),
		"el corazon ya usaba la misma regla para mostrarse")
	_check(heart.contains("LullabyShowcase.flash_control("),
		"y pide el destello por el mismo sitio")

	var showcase: String = _strip_comments(_read(SHOWCASE))
	_check(showcase.contains("_pulse(control as CanvasItem, seconds)"),
		"flash_control tiene salida para un CanvasItem cualquiera")
	var body: String = _func_body(showcase, "flash_control")
	var flash_at: int = body.find('has_method("_flash")')
	var touch_at: int = body.find('has_method("_handle_touch")')
	var pulse_at: int = body.find("_pulse(")
	_check(flash_at >= 0 and touch_at > flash_at and pulse_at > touch_at,
		"y lo intenta en orden: _flash, _handle_touch, y el pulso como ultimo recurso")


## La escena, porque la suposicion que fallo era sobre ella y no sobre el codigo.
func _scene_checks() -> void:
	var scene: String = _read(CHIMERA)
	for zone: String in ["HeartbeatTouchZone", "PictureTakingTouchZone"]:
		var at: int = scene.find('[node name="Hitbox" type="Button" parent="UILayer/%s"' % zone)
		_check(at >= 0,
			"%s/Hitbox sigue siendo un Button pelado (por eso hace falta el pulso)" % zone)

	_check(scene.contains("chimera_escape_dpad.gd"), "el D-pad sigue en Chimera")


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


func _strip_comments(source: String) -> String:
	var out: PackedStringArray = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		var hash_at: int = line.find("#")
		out.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	return "\n".join(out)
