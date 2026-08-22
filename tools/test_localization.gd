extends SceneTree

## Sanity check for the UI localization added in this session:
## lullaby_mod/resources/localization/ui_strings.csv (source) and the
## generated ui_strings.es.translation it produces. Verifies the plumbing
## that lets `tr()` and Godot's own auto-translate actually find "es" and
## fall back to the authored English text otherwise.
##
## Does NOT touch Settings.lullaby_language or Settings.apply_settings() -
## this workspace cannot load the project's autoloads under --script (see
## CLAUDE.md: "most resources are not imported... anything touching them
## fails to compile - pre-existing limitation"), so a script that referenced
## Settings would fail here for reasons unrelated to what it is checking.
## That half is a two-line diff (`if lullaby_language != TranslationServer
## .get_locale(): TranslationServer.set_locale(lullaby_language)`) verified
## by reading and by --check-only instead.
##
## Run with:
##   godot --headless --path . --script tools/test_localization.gd

const SAMPLE_KEYS: Dictionary[String, String] = {
	"Quality Preset: ": "Preajuste de calidad: ",
	"Play": "Jugar",
	"Invalid code.": "Código no válido.",
	"Code accepted - \"%s\" unlocked!": "Código aceptado - ¡\"%s\" desbloqueado!",
	"Never Played": "Nunca jugada",
}

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_check("es" in TranslationServer.get_loaded_locales(),
		"\"es\" loaded via project.godot's locale/translations")

	TranslationServer.set_locale("es")
	for en: String in SAMPLE_KEYS:
		var got: String = tr(en)
		_check(got == SAMPLE_KEYS[en],
			"tr(%s) == %s (got %s)" % [en, SAMPLE_KEYS[en], got])

	TranslationServer.set_locale("en")
	for en: String in SAMPLE_KEYS:
		var got: String = tr(en)
		_check(got == en, "locale en falls back to the source text for %s (got %s)" % [en, got])

	# Static context can't call tr() (needs an instance) - the fix in
	# lullaby_song_grader.gd uses TranslationServer.translate() directly.
	# Confirm that path resolves too, not just tr() on an instance.
	TranslationServer.set_locale("es")
	_check(TranslationServer.translate("Never Played") == "Nunca jugada",
		"TranslationServer.translate() (the static-context path) also resolves \"es\"")

	print("localization: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
