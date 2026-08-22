extends SceneTree

## The three rows added to the first-boot screen: language, "skip the
## Collector's introduction", and "always play the Collector's introduction".
##
## Every one of them is a runtime write - a Setting or a SaveData flag - so
## none of it is visible to a parse check, to the authored-property sweep or
## to the animation-track sweep. Pinned here, each rule next to the thing
## that makes it necessary.
##
## Run with:
##   godot --headless --path . --script tools/test_first_boot_options.gd

const SCENE := "res://menus/first_boot/first_boot_settings.tscn"
const SCRIPT := "res://menus/first_boot/first_boot_settings.gd"
const SHOP := "res://lullaby_mod/scripts/lullaby/collectors_shop/env_collector_shop.gd"
const SETTINGS := "res://menus/settings.gd"
const CONSOLE := "res://lullaby_mod/resources/console/console.tscn"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	var scene: String = FileAccess.get_file_as_string(SCENE)
	var script: String = FileAccess.get_file_as_string(SCRIPT)
	_check(not scene.is_empty(), "the first-boot scene is readable")
	_check(not script.is_empty(), "the first-boot script is readable")

	_check_wiring(scene)
	_check_language(script)
	_check_skip(script)
	_check_force(script)

	print("first boot options: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

## An export left unset resolves to null and every handler here guards on
## null, so a broken NodePath would show up as a screen that silently does
## nothing rather than as an error.
func _check_wiring(scene: String) -> void:
	for export_name: String in ["language_button", "skip_intro_check", "force_intro_check"]:
		_check(scene.contains("%s = NodePath(\"" % export_name),
			"%s is wired in the scene" % export_name)

	for method: String in ["_on_language_changed", "_on_skip_intro_toggled", "_on_force_intro_toggled"]:
		_check(scene.contains('method="%s"' % method), "%s is connected" % method)

	_check(scene.count("type=\"CheckBox\"") >= 2,
		"both intro options are CheckBoxes, as asked")

	# Godot's default `unchecked` icon is a near-black square at half alpha
	# (measured off ThemeDB: mean RGB 0.10, max alpha 0.50) and this panel is
	# dark, so an unticked box was invisible - a checkbox that only looks like
	# a checkbox once ticked. Tinting cannot fix it, the icon is replaced.
	_check(scene.contains("checkbox_unchecked_color") or scene.contains("checkbox_checked_color"),
		"the checkboxes carry their dark-panel colour overrides")

func _check_language(script: String) -> void:
	_check(script.contains("LANGUAGE_VALUES"), "the language row has a value list")

	# The console's Misc tab drives the same Setting through list_button.gd's
	# values_list. If the two ever disagree, one of the two rows silently
	# writes a locale the other cannot show.
	var console: String = FileAccess.get_file_as_string(CONSOLE)
	_check(console.contains('values_list = ["en", "es"]'),
		"the console's Language row still offers the same values")
	_check(script.contains('["en", "es"]'),
		"...and the first-boot row matches it")

	# apply_settings() is what calls TranslationServer.set_locale(); writing
	# the var alone changes nothing on screen.
	var body: String = _func_body(script, "_on_language_changed")
	_check(_has_statement(body, "Settings\\.apply_settings\\(\\)"),
		"choosing a language applies it rather than only storing it")
	_check(_has_statement(body, "Settings\\.save\\(\\)"),
		"...and persists it")

	var settings: String = FileAccess.get_file_as_string(SETTINGS)
	_check(settings.contains("TranslationServer.set_locale(lullaby_language)"),
		"apply_settings() is still the thing that sets the locale")

## Only shown while the Collector's welcome has never played - "el omitir la
## primera vez solamente aparece".
func _check_skip(script: String) -> void:
	var ready: String = _func_body(script, "_ready")
	_check(_has_statement(ready, "skip_intro_check\\.visible = not SaveData\\.get_flag\\(&\"intro_seen\"\\)"),
		"the skip row only appears while the intro has never been seen")

	var body: String = _func_body(script, "_on_skip_intro_toggled")
	_check(_has_statement(body, "set_flag\\(&\"intro_seen\", pressed\\)"),
		"ticking skip marks the intro as already seen")
	_check(_has_statement(body, "SaveData\\.save\\(\\)"), "...and saves")

	# The flag is what the shop actually reads. If that condition is ever
	# rewritten to something else, ticking skip stops doing anything.
	var shop: String = FileAccess.get_file_as_string(SHOP)
	_check(shop.contains('SaveData.get_flag("intro_seen")'),
		"the shop still gates the Collector's intro on that flag")

## Always shown - "y la de forzar siempre".
func _check_force(script: String) -> void:
	var ready: String = _func_body(script, "_ready")
	_check(not ready.contains("force_intro_check.visible"),
		"the force row is never hidden")

	var body: String = _func_body(script, "_on_force_intro_toggled")
	_check(_has_statement(body, "Settings\\.lullaby_force_shop_intro = pressed"),
		"ticking force writes the Setting")

	# A Setting rather than clearing intro_seen, because that flag also tells
	# EntryVoicelines whether you are a returning visitor - clearing it to
	# re-watch the tour would mute the entry voicelines from then on.
	var settings: String = FileAccess.get_file_as_string(SETTINGS)
	_check(settings.contains("var lullaby_force_shop_intro"),
		"the Setting exists (and persists, being lullaby_-prefixed)")

	var shop: String = FileAccess.get_file_as_string(SHOP)
	_check(shop.contains("Settings.lullaby_force_shop_intro or not SaveData.get_flag(\"intro_seen\")"),
		"the shop honours it alongside the flag")

	var voicelines: String = FileAccess.get_file_as_string(
		"res://lullaby_mod/scripts/lullaby/collectors_shop/dialogue/EntryVoicelines.gd")
	_check(voicelines.contains("intro_seen"),
		"EntryVoicelines still reads intro_seen (why forcing is not just clearing it)")

func _has_statement(body: String, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[\\t ]*[^#\\n]*" + pattern)
	return re.search(body) != null

func _func_body(text: String, name: String) -> String:
	var head: int = text.find("func %s(" % name)
	if head < 0:
		_check(false, "%s() exists" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
