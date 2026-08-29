extends SceneTree

## El resincronizado de audio tiene que medir el audio, no su propio error.
##
## RubiconLevelSong.check_for_desync() corre en cada compas y, si cree ver mas
## de `sync_desync_threshold` de diferencia entre la cancion y el reloj de la
## animacion, HACE UN SEEK de todos los reproductores a la vez - en Chimera son
## tres: instrumental, voces y efectos. Eso es un salto audible.
##
## Lo que leia para decidirlo era `get_playback_position()` a secas, y eso no
## es donde esta el audio. Le faltan las dos correcciones que documenta el
## propio Godot, y van en sentidos contrarios:
##
##   + get_time_since_last_mix()   la posicion se refresca una vez por bloque
##                                 de mezcla y entre bloque y bloque se queda
##                                 quieta, o sea que se lee ATRASADA;
##   - get_output_latency()        lo mezclado todavia no ha sonado, pasa por
##                                 el buffer de salida, o sea que se lee
##                                 ADELANTADA.
##
## Los dos terminos son de decenas de milisegundos y el umbral son 45, asi que
## sin corregir el ruido de medicion entra y sale solo del umbral que decide si
## hay desincronizacion. En PC la latencia de salida es pequena y estable y no
## se nota; en Android no lo es. Es la firma exacta de lo que reportaron de
## Chimera - fallos de ambiente y notas desincronizadas A RATOS - porque a
## ratos es lo que hace un umbral rozado, mientras que una deriva de verdad
## creceria en vez de ir y venir.
##
## La guarda es textual porque nada de esto se puede montar sin dispositivo de
## audio ni sin el nivel entero, pero la propiedad es textual igualmente: los
## dos terminos tienen que estar, y con el signo correcto.
##
## Run with:
##   godot --headless --path . --script tools/test_audio_resync_reading.gd

const SONG := "res://addons/rubicon/scripts/scene/game/rubicon_level_song.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var text: String = FileAccess.get_file_as_string(SONG)
	_check(not text.is_empty(), "rubicon_level_song.gd se lee")
	if text.is_empty():
		_finish()
		return

	var reader: String = _code_only(_func_body(text, "_reference_time"))
	_check(reader.contains("get_playback_position()"),
		"la lectura parte de la posicion del reproductor")
	_check(reader.contains("+ AudioServer.get_time_since_last_mix()"),
		"...le SUMA lo que lleva sin mezclar (se lee atrasada)")
	_check(reader.contains("- AudioServer.get_output_latency()"),
		"...y le RESTA la latencia de salida (se lee adelantada)")

	# Y que la comparacion use esa lectura, no la cruda otra vez.
	var check: String = _code_only(_func_body(text, "check_for_desync"))
	_check(check.contains("_reference_time()"),
		"check_for_desync compara contra la lectura corregida")
	_check(not check.contains("sync_reference_player.get_playback_position()"),
		"...y ya no contra la cruda")

	# El seek de la cancion entera deja rastro. Era un print comentado, asi que
	# hasta ahora no habia forma de saber si disparaba nunca ni cuanto - y es el
	# dato que decide si esto era todo el problema o solo la mitad.
	_check(check.contains("_report_resync("),
		"cada resync queda registrado, con signo y magnitud")
	var report: String = _code_only(_func_body(text, "_report_resync"))
	_check(report.contains("/root/DiagnosticsLog") and report.contains('has_method("mark")'),
		"...sin depender en duro del autoload, que este addon no tiene por que conocer")

	# Los tres nombres que usa la lectura existen de verdad en este motor. Es
	# barato y ya ha pescado una constante inventada en otra guarda.
	for method: String in ["get_time_since_last_mix", "get_output_latency"]:
		_check(AudioServer.has_method(method),
			"AudioServer.%s() existe en este motor" % method)
	_check(ClassDB.class_has_method("AudioStreamPlayer", "get_playback_position"),
		"AudioStreamPlayer.get_playback_position() existe en este motor")

	_finish()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _code_only(body: String) -> String:
	var out: PackedStringArray = []
	for line: String in body.split("\n"):
		var code: String = line
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		out.append(code)
	return "\n".join(out)


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
