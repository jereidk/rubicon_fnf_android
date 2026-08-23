extends SceneTree

## `luz2d=` / `luces2d=`: the 2D lights, which no counter in this log could see.
##
## `lights=` is Light3D only, so Safety Lullaby - a scene whose stage authors
## five PointLight2D - reported `lights=0(shadow=0)` on every census it ever
## produced. And `over=` cannot cover for it, because a light is not an item:
## Godot's canvas renderer draws each affected CanvasItem **again, once per
## light**, so a screen-covering Light2D doubles the fill of everything it
## touches while adding nothing at all to the item count.
##
## That gap is the standing suspect for the song's 32.48ms of GPU on 592
## primitives and no 3D. The two pure-2D scenes in log d67addb8 do not lie on
## one line - credits `over=2.0x -> gpu 7.41ms` against Safety `over=5.0x ->
## 32.48ms` is 2.5x the items and 4.4x the GPU - and the alley authors
## `BG/BgLight` with a 1049x480 texture at `texture_scale = 4.0`, a 4196x1920
## rect over a 1920x1080 stage.
##
## What this pins is that the counter answers the three questions that decide
## whether a light costs anything - is it on, does it reach the frame, and what
## is it masked to pair with - and that it says zero for the cases that cost
## nothing. The last one is not decoration: Safety keeps its ending in the same
## scene at y=2426 and y=3420 while the song's camera sits at y=540, so the huge
## `Glow` sprite and the `Darkness` light down there are free during the song.
## Both were about to be blamed for the song's GPU on scene-reading alone.
##
## Run with:
##   godot --headless --path . --script tools/test_light2d_census.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"
const ALLEY := "res://lullaby_mod/resources/funkin/songs/safety_lullaby/alley.tscn"

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0

## Built before the tree is wired so they have settled by the time anything is
## asserted - a light's global transform is not final in the frame it is added.
var _covering: PointLight2D
var _disabled: PointLight2D
var _offscreen: PointLight2D
var _dark: PointLight2D


func _initialize() -> void:
	_source_checks()
	_scene_checks()

	var texture := GradientTexture2D.new()
	texture.width = 1049
	texture.height = 480

	# BG/BgLight, to the number: 1049x480 at texture_scale 4.0 is 4196x1920 on
	# a 1920x1080 stage.
	_covering = PointLight2D.new()
	_covering.name = "Cubriente"
	_covering.texture = texture
	_covering.texture_scale = 4.0
	_covering.position = Vector2(800, 450)

	_disabled = PointLight2D.new()
	_disabled.name = "Apagada"
	_disabled.texture = texture
	_disabled.enabled = false

	# HypnoEnd's Darkness: same scene, y=3420, camera at y=540.
	_offscreen = PointLight2D.new()
	_offscreen.name = "Lejos"
	_offscreen.texture = texture
	_offscreen.position = Vector2(1005, 3420)

	_dark = PointLight2D.new()
	_dark.name = "SinEnergia"
	_dark.texture = texture
	_dark.energy = 0.0

	for light in [_covering, _disabled, _offscreen, _dark]:
		root.add_child(light)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	_coverage_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)
	return true


func _source_checks() -> void:
	var code: String = _strip_comments(_read(LOG))

	_check(code.contains("var light2d := node as Light2D"),
		"el paseo del censo mira Light2D")
	_check(code.contains("luz2d=%d/%d"),
		"y la linea CENSUS lleva luz2d=vivas/total")
	_check(code.contains("luces2d=[%s]"),
		"y nombra las mayores")
	_check(code.contains("light2d.range_item_cull_mask"),
		"con su range_item_cull_mask, que es la mitad accionable")

	# El contador viejo sigue siendo lo que era: esto lo acompaña, no lo
	# sustituye. Un Light3D no aparece en luz2d= ni al reves.
	_check(code.contains("if node is Light3D and node.is_visible_in_tree()"),
		"lights= sigue contando Light3D aparte")

	var at: int = code.find("func _light2d_coverage(")
	_check(at >= 0, "_light2d_coverage existe")
	if at < 0:
		return
	var body: String = code.substr(at)
	body = body.substr(0, body.find("\nfunc "))
	for guard: String in ["light.enabled", "light.is_visible_in_tree()", "light.energy",
			"light.get_viewport() != get_tree().root"]:
		_check(body.contains(guard), "descarta por %s" % guard)
	_check(body.contains("point.texture_scale"),
		"y el alcance sale de la textura por texture_scale, no del nodo a secas")


## The scene that motivated it, read rather than restated.
func _scene_checks() -> void:
	var alley: String = _read(ALLEY)
	var lights: int = alley.count('type="PointLight2D"')
	_check(lights >= 4, "el callejon sigue autorando varias luces 2D (%d)" % lights)
	_check(alley.contains("texture_scale = 4.0"),
		"incluida la que se escala x4")
	_check(alley.contains("light_mask = 3"),
		"y sprites con light_mask que comparte bit con range_item_cull_mask = 257")


func _coverage_checks() -> void:
	var log_node: Node = root.get_node_or_null(^"DiagnosticsLog")
	if log_node == null:
		_check(false, "existe el autoload DiagnosticsLog")
		return

	var covering: float = log_node.call("_light2d_coverage", _covering)
	_check(covering >= 0.99,
		"una luz de 4196x1920 sobre 1920x1080 cubre la pantalla entera (%.3f)" % covering)

	for pair in [[_disabled, "apagada"], [_offscreen, "en otra parte del mundo 2D"],
			[_dark, "con energy 0"]]:
		var share: float = log_node.call("_light2d_coverage", pair[0])
		_check(is_zero_approx(share), "una luz %s cuenta 0 (%.3f)" % [pair[1], share])

	# Y el orden del ranking, que es lo que se lee en el log.
	var rank: Array = [[0.2, "peque"], [1.0, "grande"], [0.6, "media"], [0.1, "minima"]]
	var text: String = log_node.call("_light2d_rank_text", rank)
	_check(text == "grande, media, peque",
		"luces2d= lista las tres mayores de mayor a menor (%s)" % text)


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
