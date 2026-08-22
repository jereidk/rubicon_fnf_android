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
	"Buy": "Comprar",
	"The Husked One": "El Vaciado",
	"Seen On: %s\nCollected: %03d / %03d": "Visto en: %s\nColección: %03d / %03d",
	"RESUME": "REANUDAR",
	"Leave the shop?": "¿Salir de la tienda?",
	"Score: %d %s Accuracy: %.2f%% %s Misses: %d": "Puntuación: %d %s Precisión: %.2f%% %s Fallos: %d",
	"Hello and Welcome to the Cabinet of Novelties!": "¡Hola y bienvenido al Gabinete de las Novedades!",
	"*COUGHS*": "*TOSE*",
	"WELCOME BACK, COLLECTOREE!": "¡BIENVENIDO DE VUELTA, COLECCIONISTOIDE!",
	"HELLO!": "¡HOLA!",
	# The Training overlay builds every string it shows in code, so all of
	# these are tr()'d explicitly rather than reaching Godot's auto-translate
	# - a dropped key here shows English on a Spanish save with nothing to
	# say so.
	"PENDULUM": "PÉNDULO",
	"DRILL OVER": "FIN DEL ENTRENAMIENTO",
	"TAP ON THE BEAT": "TOCA AL LATIDO",
	"HITS  %d\nMISSES  %d\nTIME  %d:%02d": "ACIERTOS  %d\nFALLOS  %d\nTIEMPO  %d:%02d",
}

## Safety Lullaby's on-screen lyric lines carry BBCode, and two of them
## switch [color=...] mid-sentence to highlight one word. The CSV key is the
## whole authored string, tags included, so a translation that drops or
## reorders a tag still "resolves" - it just renders wrong. These pin the
## tag sequence, not only that a translation exists.
const LYRIC_SAMPLES: Array[String] = [
	"[wave amp=70.0 freq=3.5][shake rate=20.0 level=10][pulse freq=1.1 color=#ffffff5a ease=1.0][color=#ffffff7f]Come little Girlfriend",
	"[wave amp=70.0 freq=3.5][shake rate=20.0 level=10][pulse freq=1.1 color=#ffffff5a ease=1.0][color=#ffffff7f]Your [color=#4f426b]friend[color=#ffffff7f] is waiting",
	"[shake rate=35.0 level=15][color=#ff00657f]DREAMS...",
]

## The shop tour's lines carry [pause] (pacing, consumed by
## CollectorDialogue's typing walk) and custom effect tags. show_line() now
## tr()s BEFORE stripping [pause], so the key keeps them - a translation
## that drops them still resolves and just types at the wrong rhythm.
const DIALOGUE_SAMPLES: Array[String] = [
	"HELLO AND WELCOME![pause] TO THE CABINET OF NOVELTIES!",
	"I’M [pause][collector]THE COLLECTOR[/collector].",
	"WHAT YOU SEE IN FRONT OF YOU IS ME, [pause][collector]THE COLLECTOR[/collector] [pause]AND MY [pause][table]TABLE[/table].",
]

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

	var tags := RegEx.new()
	tags.compile("\\[/?[^\\]]*\\]")
	for en: String in LYRIC_SAMPLES:
		var es: String = tr(en)
		_check(es != en, "lyric line is translated, not passed through: %s" % _plain(tags, en))
		var en_tags: Array[String] = []
		var es_tags: Array[String] = []
		for m: RegExMatch in tags.search_all(en):
			en_tags.append(m.get_string())
		for m: RegExMatch in tags.search_all(es):
			es_tags.append(m.get_string())
		_check(en_tags == es_tags,
			"lyric BBCode survives translation intact: %s" % _plain(tags, en))

	for en: String in DIALOGUE_SAMPLES:
		var es: String = tr(en)
		_check(es != en, "shop dialogue line is translated: %s" % _plain(tags, en))
		_check(en.count("[pause]") == es.count("[pause]"),
			"[pause] count preserved (%d): %s" % [en.count("[pause]"), _plain(tags, en)])
		for tag: String in ["[collector]", "[/collector]", "[table]", "[/table]"]:
			_check(en.count(tag) == es.count(tag),
				"%s count preserved: %s" % [tag, _plain(tags, en)])

	print("localization: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

func _plain(tags: RegEx, s: String) -> String:
	return tags.sub(s, "", true)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
