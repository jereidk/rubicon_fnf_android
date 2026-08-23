extends SceneTree

## Safety Lullaby's pendulum hitbox has to be up whenever the pendulum is
## running, and the song's own Timeline is what decides when that is.
##
## The bug this pins: `hitbox.visible = mechanic_active and hud_visible`, where
## `hud_visible` polled `DefaultHUD`'s modulate. Sensible for a HUD element,
## wrong for the only input a touch device has. Reading the two tracks out of
## the scene's `play` animation:
##
##     LullabyPendulumServer:started  0.00 off  33.73 ON  159.08 off  160.04 ON  194.37 off
##     DefaultHUD:modulate.a          0.00 0    31.53 0   33.73 1     158.00 1   159.03 0
##
## the HUD has no key after 159.03, so the last third of the song runs the
## pendulum with the HUD at zero - **160.04 to 194.37, thirty-four seconds** -
## and the old rule deleted the hitbox for all of it. The pendulum went on
## asking for `lullaby_special` every half measure and went on taking
## `retention_loss` (-15 of 100) per miss, so seven measures reached zero and
## fired `mechanic_failed`. On desktop the key still works and the pendulum is
## scene geometry still swinging on screen; on Android there was no way in.
##
## Two halves, and the second is the one that matters. Asserting the script no
## longer reads the HUD is easy to satisfy and easy to lose meaning for. So this
## also reads the scene and recomputes the overlap: if a future edit moves the
## HUD fade or the `started` keys so that the two no longer overlap, the check
## says so out loud rather than quietly passing on a song it no longer describes.
##
## Run with:
##   godot --headless --path . --script tools/test_pendulum_hitbox_window.gd

const SCRIPT_PATH := "res://lullaby_mod/songs/safety_lullaby/scripts/safety_lullaby_touch_controls.gd"
const SCENE_PATH := "res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn"
const TIMELINE := "play"
const STARTED_TRACK := "LullabyPendulumServer:started"
const HUD_TRACK := "DefaultHUD:modulate"

var _failures: int = 0
var _checks: int = 0


## The behavioural half has to wait for a real tree.
##
## `_update_visibility()` reads `get_tree().paused`, and under `--script` the
## SceneTree is not wired until `_initialize()` returns - `root` exists, but a
## node added to it reports `is_inside_tree() == false` and `get_tree() == null`.
## Run there, every call errored out on its first line and left `hitbox.visible`
## at whatever it already was, which passed two of these checks by accident.
var _frames: int = 0


func _initialize() -> void:
	_script_checks()
	_timeline_checks()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_behavioural_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)
	return true


func _script_checks() -> void:
	var code: String = _strip_comments(_read(SCRIPT_PATH))
	_check(code.contains("hitbox.visible = mechanic_active"),
		"la visibilidad del hitbox la decide el mecanico")
	_check(not code.contains("hud_visible"),
		"y no el HUD: eso borraba la entrada durante 34s de canción")
	_check(not code.contains("default_hud.modulate"),
		"...ni leyendo su modulate por otra vía")

	# Los dos casos que SI deben apagarlo siguen ahí, y son los que hacían
	# innecesario el acoplamiento al HUD.
	_check(code.contains("get_tree().paused"), "la pausa lo sigue apagando")
	_check(code.contains("gameover_module.is_game_over"), "y el gameover también")
	_check(code.contains("pendulum_server.started"),
		"y `started` es lo que cubre las cutscenes, que es donde estaba false igual")

	# Los botones de pausa/reinicio SI son HUD y deben seguir desapareciendo
	# con él - la regla no es que el acoplamiento esté mal, es dónde se aplica.
	var generic: String = _read("res://addons/rubicon_mobile_controls/song_touch_controls.gd")
	_check(generic.contains("default_hud"),
		"song_touch_controls conserva el acoplamiento: sus botones sí son HUD")


## Recomputes the overlap from the scene, so this file cannot go on describing
## a song that has changed underneath it.
func _timeline_checks() -> void:
	var scene: String = _read(SCENE_PATH)
	var started: Array = _track_keys(scene, STARTED_TRACK)
	var hud: Array = _track_keys(scene, HUD_TRACK)
	_check(started.size() >= 2, "la pista `started` sigue en la animación `%s` (%d claves)"
		% [TIMELINE, started.size()])
	_check(hud.size() >= 2, "y la del modulate del HUD (%d claves)" % hud.size())
	if started.is_empty() or hud.is_empty():
		return

	# La ventana: pendulo encendido y HUD a cero.
	var worst: float = 0.0
	var worst_from: float = -1.0
	var edges: Array[float] = []
	for pair in started:
		edges.append(float(pair[0]))
	for pair in hud:
		edges.append(float(pair[0]))
	edges.append(float(started[started.size() - 1][0]) + 1.0)
	edges.sort()

	for i in edges.size() - 1:
		var from: float = edges[i]
		if not bool(_value_at(started, from, false)):
			continue
		if float(_value_at(hud, from, 1.0)) > 0.01:
			continue
		var span: float = edges[i + 1] - from
		if span > worst:
			worst = span
			worst_from = from

	_check(worst > 1.0,
		"la canción sigue teniendo la ventana ciega que motivó esto: %.2fs desde %.2fs"
			% [worst, worst_from])


func _behavioural_checks() -> void:
	var script: GDScript = load(SCRIPT_PATH)
	if script == null:
		_check(false, "el script carga")
		return

	var controls := Control.new()
	controls.set_script(script)
	var hitbox := Control.new()
	var hud := Control.new()
	controls.add_child(hitbox)
	controls.add_child(hud)
	root.add_child(controls)

	controls.hitbox = hitbox
	controls.default_hud = hud
	controls.pendulum_server = _stub_server(true, false)

	# El caso exacto de 160.04s: mecánico corriendo, HUD desvanecido.
	hud.modulate.a = 0.0
	controls.call("_update_visibility")
	_check(hitbox.visible,
		"con el pendulo corriendo y el HUD a cero, el hitbox está (era el bug)")

	hud.modulate.a = 1.0
	controls.call("_update_visibility")
	_check(hitbox.visible, "y con el HUD visible, también")

	# Y sigue apagándose cuando debe.
	controls.pendulum_server.started = false
	controls.call("_update_visibility")
	_check(not hitbox.visible, "parado el pendulo, se apaga")

	controls.pendulum_server.started = true
	controls.pendulum_server.autoplay = true
	controls.call("_update_visibility")
	_check(not hitbox.visible, "en autoplay normal, se apaga")

	controls.queue_free()


func _stub_server(started: bool, autoplay: bool) -> LullabyPendulumServer:
	var server := LullabyPendulumServer.new()
	server.started = started
	server.autoplay = autoplay
	return server


## `[[time, value], ...]` for the track whose path ends with `suffix`, inside
## the animation named TIMELINE. Bools come back as bool, a Color track comes
## back as its alpha - which is the only component either caller needs.
func _track_keys(scene: String, suffix: String) -> Array:
	var head: int = 0
	while true:
		var path_at: int = scene.find("/path = NodePath(\"", head)
		if path_at < 0:
			return []
		var line_start: int = scene.rfind("tracks/", path_at)
		var quote: int = path_at + "/path = NodePath(\"".length()
		var path: String = scene.substr(quote, scene.find("\"", quote) - quote)
		head = path_at + 1
		if not path.ends_with(suffix):
			continue
		var block_at: int = scene.rfind("[sub_resource", path_at)
		var name_at: int = scene.find("resource_name = \"", block_at)
		if name_at < 0 or name_at > path_at:
			continue
		var name_end: int = scene.find("\"", name_at + "resource_name = \"".length())
		if scene.substr(name_at + "resource_name = \"".length(),
				name_end - name_at - "resource_name = \"".length()) != TIMELINE:
			continue

		var index: String = scene.substr(line_start + 7, scene.find("/", line_start + 7) - line_start - 7)
		var keys_at: int = scene.find("tracks/%s/keys = " % index, path_at)
		if keys_at < 0:
			continue
		var chunk: String = scene.substr(keys_at, 4000)
		return _parse_keys(chunk)
	return []


func _parse_keys(chunk: String) -> Array:
	var times: PackedStringArray = _between(chunk, "\"times\": PackedFloat32Array(", ")").split(",")
	var values: String = _between(chunk, "\"values\": [", "]")
	var out: Array = []

	var alphas: Array = []
	var colour := RegEx.new()
	colour.compile("Color\\([^)]*?([0-9.]+)\\s*\\)")
	for m in colour.search_all(values):
		alphas.append(m.get_string(1).to_float())

	var i: int = 0
	for raw in times:
		var t: String = raw.strip_edges()
		if t.is_empty():
			continue
		if alphas.size() > i:
			out.append([t.to_float(), alphas[i]])
		else:
			var parts: PackedStringArray = values.split(",")
			out.append([t.to_float(), parts[i].strip_edges() == "true" if parts.size() > i else false])
		i += 1
	return out


func _value_at(keys: Array, when: float, fallback: Variant) -> Variant:
	var value: Variant = fallback
	for pair in keys:
		if float(pair[0]) <= when + 0.0001:
			value = pair[1]
		else:
			break
	return value


func _between(text: String, open: String, close: String) -> String:
	var a: int = text.find(open)
	if a < 0:
		return ""
	a += open.length()
	var b: int = text.find(close, a)
	return text.substr(a, b - a) if b > a else ""


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
