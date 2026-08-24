extends SceneTree

## Monochrome's note lanes survive its typing bouts.
##
## The bug this pins, in the player's words: "cuando estas tocando flechas se
## te va el tapping [...] y no me dejo tocar las flechas, perdiendo en el
## proceso". The hitbox was hidden outright while a keyboard was on screen,
## and the chart puts player notes INSIDE both typing bouts - so those notes
## were not missed, they were unreachable. Losing to a mechanic you were never
## allowed to play is the worst kind of difficulty.
##
## The overlap is the fact everything else rests on, so it is measured from
## the chart here rather than trusted from a comment. Both halves are read
## from the real files: the bouts out of the song scene's animation, the notes
## out of chart_monochrome_ply.tres, converted through the meta's own BPM and
## time signature. If the chart is ever edited so the notes no longer land
## inside a bout, this says so instead of silently guarding nothing.
##
## What it cannot check is how it looks on a phone - whether the strip left
## above the keyboard is comfortable to play, and whether the strumline is
## still visible under it. That is a device question and this file does not
## pretend to answer it.
##
## Run with:
##   godot --headless --path . --script tools/test_typing_lane_overlap.gd

const SCENE := "res://lullaby_mod/songs/monochrome/sng_monochrome.tscn"
const CHART := "res://lullaby_mod/songs/monochrome/data/chart_monochrome_ply.tres"
const META := "res://lullaby_mod/songs/monochrome/data/meta_monochrome.tres"
const TOUCH := "res://lullaby_mod/songs/monochrome/scripts/monochrome_typing_touch_controls.gd"
const CONTROLS := "res://addons/rubicon_mobile_controls/rubicon_mobile_controls.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var scene: String = _read(SCENE)

	_wiring_checks(scene, _read(TOUCH), _read(CONTROLS))
	_overlap_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _wiring_checks(scene: String, touch: String, controls: String) -> void:
	# La sustitucion en si: encoger, no esconder.
	_check(not scene.contains('hide_properties = Array[StringName]([&"keyboard_showing"])'),
		"la escena ya no esconde el hitbox entero cuando hay teclado")
	_check(scene.contains('occlusion_sources = [NodePath("../TypingTouchControls")]'),
		"lo apunta al productor de la ocupacion")
	_check(scene.contains('occlusion_properties = Array[StringName]([&"keyboard_occlusion"])'),
		"...por la propiedad que la publica")
	_check(scene.contains('node_paths=PackedStringArray("reserved_controls", "default_hud", "gameover_source", "occlusion_sources")'),
		"y occlusion_sources esta en node_paths, o el export llega vacio")

	_check(touch.contains("var keyboard_occlusion: float"),
		"los controles de tipeo publican la ocupacion")
	var raise: String = _func_body(touch, "_apply_raise")
	_check(raise.contains("keyboard_occlusion ="),
		"...calculada donde se mide el teclado, no en un segundo sitio que pueda discrepar")

	# Y puesta a cero ANTES de la condicion, no solo dentro de ella. Sin el
	# reset, un teclado que se va deja el ultimo valor pegado y el hitbox se
	# queda encogido para siempre - que es este mismo bug otra vez, por la
	# puerta de atras. La primera version de esta comprobacion se conformaba
	# con que apareciese "keyboard_occlusion =" en algun sitio, y borrar el
	# reset pasaba en verde.
	var reset_at: int = raise.find("keyboard_occlusion = 0.0")
	var computed_at: int = raise.find("keyboard_occlusion = clampf")
	_check(reset_at >= 0 and computed_at > reset_at,
		"...y a cero antes de calcularla, o un teclado que se va la deja pegada")

	# Y el consumidor, por las DOS rutas. Solo el dibujo seria una linea
	# pintada que no cambia donde se puede tocar.
	_check(controls.contains("func _effective_bottom_percent()"),
		"el hitbox suma la ocupacion a su zona muerta autorada")
	_check(controls.count("_effective_bottom_percent()") >= 3,
		"y la usan el dibujo Y el input (%d usos)"
			% controls.count("_effective_bottom_percent()"))
	_check(_func_body(controls, "_get_lane_for_position").contains("_effective_bottom_percent()"),
		"...incluido _get_lane_for_position, que es el que decide si un toque cuenta")
	_check(_func_body(controls, "_track_occlusion").contains("_end_touch("),
		"un dedo que el teclado acaba de tapar se suelta")
	# Sobre el codigo y no sobre el texto: el propio comentario de
	# _track_occlusion explica por que NO llama a _release_all(), asi que
	# buscarlo en crudo fallaba contra una implementacion correcta.
	_check(not _code_only(_func_body(controls, "_track_occlusion")).contains("_release_all()"),
		"...solo ese, no todos: una nota sostenida arriba sigue siendo valida")


## The fact the whole change rests on, taken from the files.
func _overlap_checks() -> void:
	var bpm: float = _float_in(_read(META), "bpm")
	var numerator: float = _float_in(_read(META), "time_signature_numerator")
	_check(bpm > 0.0 and numerator > 0.0,
		"el meta da bpm=%.0f y compas de %.0f" % [bpm, numerator])
	if bpm <= 0.0 or numerator <= 0.0:
		return
	var seconds_per_measure: float = numerator * 60.0 / bpm

	var bouts: Array = _typing_bouts()
	_check(bouts.size() >= 2, "la cancion tiene al menos dos tandas de tipeo (%d)" % bouts.size())

	var notes: PackedFloat32Array = _player_note_seconds(seconds_per_measure)
	_check(notes.size() > 0, "el chart del jugador se lee (%d filas)" % notes.size())

	var total: int = 0
	for bout: Array in bouts:
		var inside: int = 0
		var last: float = -1.0
		for t: float in notes:
			if t >= bout[0] and t <= bout[1]:
				inside += 1
				last = t
		total += inside
		_check(inside > 0,
			"tanda %.0f-%.0fs: %d notas del jugador dentro, la ultima a %.1fs"
				% [bout[0], bout[1], inside, last])

	_check(total > 0,
		"o sea que esconder el hitbox durante el teclado quitaba %d notas jugables" % total)


## The bouts, from the animation track that drives TypingChallenge.active.
func _typing_bouts() -> Array:
	var scene: String = FileAccess.get_file_as_string(SCENE)
	var out: Array = []
	# Las pistas guardan "times" y "values" en PackedFloat32Array/Array
	# paralelos; se buscan las que mueven `active` y se emparejan los
	# true/false en orden.
	var re := RegEx.create_from_string(
		'tracks/\\d+/path = NodePath\\("[^"]*:active"\\)[\\s\\S]{0,600}?"times": PackedFloat32Array\\(([^)]*)\\)[\\s\\S]{0,600}?"values": \\[([^\\]]*)\\]')
	for m in re.search_all(scene):
		var times: PackedStringArray = m.get_string(1).split(",", false)
		var values: PackedStringArray = m.get_string(2).split(",", false)
		var open_at: float = -1.0
		for i in mini(times.size(), values.size()):
			var on: bool = values[i].strip_edges() == "true"
			var at: float = float(times[i].strip_edges())
			if on and open_at < 0.0:
				open_at = at
			elif not on and open_at >= 0.0:
				out.append([open_at, at])
				open_at = -1.0
	return out


## Every player row's time in seconds, resolved through section + offset/quant
## the same way RubiChartRow.measure_time does.
func _player_note_seconds(seconds_per_measure: float) -> PackedFloat32Array:
	var text: String = FileAccess.get_file_as_string(CHART)
	var rows: Dictionary = {}
	var blocks := RegEx.create_from_string(
		'\\[sub_resource type="Resource" id="([^"]+)"\\]\\n([\\s\\S]*?)(?=\\n\\[sub_resource|\\n\\[resource|$)')
	var found: Array = []
	for m in blocks.search_all(text):
		found.append([m.get_string(1), m.get_string(2)])

	for pair: Array in found:
		var body: String = pair[1]
		if not body.contains('ExtResource("3")'):
			continue
		rows[pair[0]] = Vector2(_float_in(body, "offset"), maxf(_float_in(body, "quant"), 1.0))

	var out: PackedFloat32Array = []
	var ref := RegEx.create_from_string('SubResource\\("([^"]+)"\\)')
	for pair: Array in found:
		var body: String = pair[1]
		if not body.contains('ExtResource("5")'):
			continue
		var measure: float = _float_in(body, "measure")
		for r in ref.search_all(body):
			var id: String = r.get_string(1)
			if rows.has(id):
				var row: Vector2 = rows[id]
				out.append((measure + row.x / row.y) * seconds_per_measure)
	return out


func _float_in(text: String, key: String) -> float:
	var m: RegExMatch = RegEx.create_from_string(
		'(?m)^%s = (-?[\\d.eE+]+)$' % key).search(text)
	return float(m.get_string(1)) if m != null else 0.0


## `body` with comment lines removed, for checks about what the code DOES.
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


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "%s se lee" % path.get_file())
	return text
