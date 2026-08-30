extends SceneTree

## El barrido del precache no calienta planos que tapa un video.
##
## Chimera dibuja dos de sus cutscenes con video pre-renderizado, y los dos
## nodos llevan `disable_3d_while_playing = true`, asi que durante su ventana el
## pase 3D ni corre. `extra_sweep_animations` seguia listando cinco secuencias
## enteramente dentro de esas ventanas:
##
##     101_prelude          3.00 - 19.92   entera bajo prelude     16 poses
##     102_intro           19.92 - 34.58   entera bajo prelude      2 poses
##     104_photographysesh 53.78 - 62.33   entera bajo photoshoot   4 poses
##     107_turnaround      72.50 - 75.88   entera bajo photoshoot  16 poses
##     114_hexapproach     97.83 - 102.63  entera bajo photoshoot   7 poses
##
## 45 de las 82 poses del barrido, calentando encuadres que el jugador no ve en
## 3D jamas. Dos de ellas - `104_photographysesh` y `114_hexapproach` - estan
## entre los cuatro petardeos que motivaron este export; dejaron de petardear
## porque encima va un video, y el barrido seguia pagandolos igual.
##
## Y al reves: donde un video DEVUELVE el mando a mitad de un clip, ese clip se
## dibuja en 3D en frio. `photoshoot` acaba en 111.0s, dentro de `116_hexstare`
## (107.21 - 113.14), que no estaba en la lista.
##
## Las dos reglas se comprueban DERIVANDOLAS de la escena - las ventanas de cada
## nodo de video contra la pista de clips del reloj - y no contra una lista
## escrita a mano aqui. Mover un `ends_at` cambia lo que este guard exige, que es
## justo lo que hace falta para que el mapeo no se pudra en silencio.
##
## Se asume `graphics_prefer_cutscene_video` encendido: esta a `true` en
## `settings.gd` y en los cuatro presets de calidad, no se expone en ningun menu,
## y los unicos sitios que lo apagan son harnesses offline (`render_cutscene.gd`,
## `probe_mixer_caches.gd`) que renderizan fotograma a fotograma y a los que un
## petardeo les da igual.
##
## Run with:
##   godot --headless --path . --script tools/test_sweep_skips_video_windows.gd

const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"

## Donde acaba el ultimo clip, para poder cerrar su ventana. La cancion dura
## menos, pero cualquier valor mayor que el ultimo `starts_at` sirve: solo se usa
## para dar un final al ultimo clip de la lista.
const AFTER_LAST := 1000.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var scene: String = _read(CHIMERA)
	if not _check(not scene.is_empty(), "sng_chimera.tscn se lee"):
		_finish()
		return

	var windows: Array = _video_windows(scene)
	_check(windows.size() == 2, "se encuentran las dos ventanas de video (%d)" % windows.size())
	for w in windows:
		_check(w["disable_3d"],
			"%s lleva disable_3d_while_playing, o no tapa el pase 3D" % w["name"])
		print("       %s  %.3f - %.3f" % [w["name"], w["from"], w["to"]])

	var clips: Array = _clip_schedule(scene)
	if not _check(clips.size() > 20, "se lee la pista de clips del reloj (%d)" % clips.size()):
		_finish()
		return

	var listed: PackedStringArray = _sweep_list(scene)
	_check(not listed.is_empty(), "extra_sweep_animations tiene algo (%d)" % listed.size())
	print("       lista: %s" % ", ".join(listed))

	# Regla 1: nada de la lista puede estar entero dentro de una ventana.
	for name in listed:
		var span: Dictionary = _span_of(clips, name)
		if not _check(not span.is_empty(), "%s existe en la pista de clips" % name):
			continue
		var covering: String = _fully_inside(span, windows)
		_check(covering.is_empty(),
			"%s NO esta entero bajo un video%s" % [
				name, "" if covering.is_empty() else " (lo tapa %s)" % covering])

	# Regla 2: todo clip en el que un video devuelve el mando a media reproduccion
	# tiene que estar en la lista - es el unico momento en que la escena vuelve a
	# dibujarse en 3D sin aviso.
	for w in windows:
		var handback: String = _clip_at(clips, w["to"])
		if handback.is_empty():
			continue
		_check(Array(listed).has(handback),
			"%s devuelve el mando dentro de %s, que esta en la lista" % [w["name"], handback])

	# Y la comprobacion barata que sostiene a las otras dos: que la poda de
	# verdad ocurrio. Sin esto el guard pasa igual con la lista vieja si alguien
	# moviera las ventanas de video en vez de la lista.
	for gone in ["101_prelude", "102_intro", "104_photographysesh",
			"107_turnaround", "114_hexapproach"]:
		_check(not Array(listed).has(gone),
			"%s ya no se barre: lo tapa un video de principio a fin" % gone)

	_finish()


## Las ventanas `[starts_at, ends_at)` de cada nodo de video de la escena.
##
## Por `video_path` y no por el uid del script: el uid cambia de un import a
## otro y esto solo necesita saber cuales son los nodos de video.
func _video_windows(scene: String) -> Array:
	var out: Array = []
	for block in scene.split("\n[node "):
		if not block.contains("video_path ="):
			continue
		out.append({
			"name": _quoted(block, "name="),
			# `starts_at` puede faltar: Godot no serializa un valor por defecto,
			# y el defecto es 0.0. Leerlo como "no hay ventana" seria un guard
			# que se cae solo el dia que alguien deje el primer video en 0.
			"from": _number(block, "starts_at", 0.0),
			"to": _number(block, "ends_at", -1.0),
			"disable_3d": block.contains("disable_3d_while_playing = true"),
		})
	return out


## La pista de clips del reloj: [{name, from, to}], en orden.
func _clip_schedule(scene: String) -> Array:
	var at: int = scene.find('"clips": PackedStringArray(')
	if at < 0:
		return []
	var names: PackedStringArray = _inside(scene, at, '"clips": PackedStringArray(').split(",")
	var times_at: int = scene.find('"times": PackedFloat32Array(', at)
	if times_at < 0:
		return []
	var times: PackedStringArray = _inside(scene, times_at, '"times": PackedFloat32Array(').split(",")
	if names.size() != times.size():
		return []

	var out: Array = []
	for i in names.size():
		var from: float = float(times[i].strip_edges())
		var to: float = AFTER_LAST if i + 1 >= times.size() else float(times[i + 1].strip_edges())
		out.append({
			"name": names[i].strip_edges().trim_prefix('"').trim_suffix('"'),
			"from": from, "to": to,
		})
	return out


func _sweep_list(scene: String) -> PackedStringArray:
	var at: int = scene.find("extra_sweep_animations = Array[StringName]([")
	if at < 0:
		return PackedStringArray()
	var body: String = _inside(scene, at, "extra_sweep_animations = Array[StringName]([")
	# Lo de dentro de las comillas, y nada mas. Recortar prefijos y sufijos
	# uno a uno dejaba el `"])` final pegado al ultimo nombre.
	var out := PackedStringArray()
	for piece in body.split(","):
		var open: int = piece.find('"')
		if open < 0:
			continue
		var close: int = piece.find('"', open + 1)
		if close < 0:
			continue
		out.append(piece.substr(open + 1, close - open - 1))
	return out


func _span_of(clips: Array, name: String) -> Dictionary:
	for c in clips:
		if c["name"] == name:
			return c
	return {}


## El nombre del video que cubre el clip entero, o "" si ninguno.
func _fully_inside(span: Dictionary, windows: Array) -> String:
	for w in windows:
		if w["to"] <= w["from"]:
			continue
		if span["from"] >= w["from"] and span["to"] <= w["to"]:
			return String(w["name"])
	return ""


## En que clip cae un instante.
func _clip_at(clips: Array, when: float) -> String:
	for c in clips:
		if when > c["from"] and when < c["to"]:
			return String(c["name"])
	return ""


## El texto entre `opener` y su parentesis de cierre.
func _inside(text: String, at: int, opener: String) -> String:
	var start: int = at + opener.length()
	var close: int = text.find(")", start)
	return "" if close < 0 else text.substr(start, close - start)


func _quoted(block: String, key: String) -> String:
	var at: int = block.find(key)
	if at < 0:
		return ""
	var start: int = block.find('"', at) + 1
	var close: int = block.find('"', start)
	return "" if close < 0 else block.substr(start, close - start)


func _number(block: String, key: String, fallback: float) -> float:
	var at: int = block.find("\n%s = " % key)
	if at < 0:
		return fallback
	var start: int = at + key.length() + 4
	var close: int = block.find("\n", start)
	return fallback if close < 0 else float(block.substr(start, close - start).strip_edges())


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - el barrido no calienta lo que tapa un video")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
