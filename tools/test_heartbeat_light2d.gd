extends SceneTree

## `luz2d=` lands on the heartbeat, not only on the census.
##
## Why this had to move. The device log of 2026-08-24 has Safety Lullaby
## running from 198s to 265s with `gpu` pinned at 32ms and no 3D at all - the
## song is fill bound and the only thing that multiplies 2D fill is Light2D
## coverage, because Godot's canvas renderer redraws each affected CanvasItem
## once per light touching it. The number that says whether the 2D light budget
## is even applying is `luz2d=`, and it only existed on the CENSUS line.
##
## All four censuses of that session landed at 198.76s and 199.60s (the intro),
## 225.03s (still the intro) and 255.04s (the gameover). Not one during the
## song. Sixty-six seconds of the exact problem, unmeasured, because the census
## runs on a 30s grid and the grid missed.
##
## Raising the census rate was the obvious fix and it is the wrong one: `self=`
## on those census frames is 4.6ms and 15.4ms, so measuring more often would
## have injected the very hitching under investigation. The list of Light2Ds is
## stable for a scene, so it is collected once in the walk that already builds
## the other watch lists, and the heartbeat reduces it - thirteen rectangle
## intersections, every five seconds.
##
## What the summary reports is the SUM of coverage rather than the count, and
## that is the whole point: one PointLight2D at texture_scale 4.0 across the
## frame costs more than three small ones, and a count cannot tell them apart.
##
## Run with:
##   godot --headless --path . --script tools/test_heartbeat_light2d.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame

	_wiring_checks()
	await _behaviour_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _wiring_checks() -> void:
	var code: String = FileAccess.get_file_as_string(LOG)
	_check(not code.is_empty(), "lullaby_diagnostics_log.gd se lee")

	_check(code.contains("_light2d_summary()"), "existe el sumario de luces 2D")

	# En el HEARTBEAT, que es lo que arregla el agujero. En el censo ya estaba.
	var heartbeat: int = code.find('_entry("HEARTBEAT"')
	var entry_end: int = code.find("])", heartbeat)
	_check(heartbeat >= 0 and code.substr(heartbeat, entry_end - heartbeat).contains("_light2d_summary()"),
		"y sale en el HEARTBEAT, que cae cada cinco segundos")

	# Cacheado por escena, no recorriendo el arbol en cada latido: un censo
	# cuesta 4.6-15.4ms en esa escena y esto no puede costar eso.
	_check(code.contains("var _light2d_watch: Array[Light2D]"),
		"la lista se cachea por escena")
	var collector: String = _func_body(code, "_collect_blackout_watch")
	_check(collector.contains("_light2d_watch.clear()"),
		"...se vacia al cambiar de escena")
	_check(collector.contains("_light2d_watch.append(light2d)"),
		"...y se llena en el barrido que ya existia, sin uno nuevo")

	var summary: String = _func_body(code, "_light2d_summary")
	_check(not summary.contains("get_tree()") and not summary.contains("for node in"),
		"el sumario no recorre el arbol, solo reduce la lista")
	_check(summary.contains("is_instance_valid(light)"),
		"y tolera una luz liberada entre escenas")


## Driven for real, because every claim about what the number MEANS is a claim
## about arithmetic on rectangles.
func _behaviour_checks() -> void:
	var script: GDScript = load(LOG)
	_check(script != null, "el script carga")
	if script == null:
		return

	var log_node: Node = script.new()
	log_node.set_process(false)
	root.add_child(log_node)

	var texture := PlaceholderTexture2D.new()
	texture.size = root.size

	# Una luz que cubre la pantalla entera.
	var full := PointLight2D.new()
	full.name = "FullScreen"
	full.texture = texture
	full.position = root.size * 0.5
	root.add_child(full)

	# Y otra que cubre un cuarto de ancho y alto - un dieciseisavo del area.
	var small := PointLight2D.new()
	small.name = "Corner"
	small.texture = texture
	small.texture_scale = 0.25
	small.position = root.size * 0.5
	root.add_child(small)

	var watch: Array[Light2D] = [full, small]
	log_node.set("_light2d_watch", watch)

	# Contra la cobertura que el propio codigo calcula, no contra numeros
	# escritos aqui: `_screen_px()` no es el area del rect del viewport, asi
	# que la primera version de esto esperaba 1.00x, leia 0.51x y suspendia una
	# implementacion correcta. Lo que hay que fijar es la RELACION - la suma es
	# la suma, y un cuarto de lado es un dieciseisavo de area.
	var cover_full: float = log_node.call("_light2d_coverage", full)
	var cover_small: float = log_node.call("_light2d_coverage", small)
	_check(cover_full > 0.0 and cover_small > 0.0,
		"las dos luces cubren algo (%.3f y %.3f)" % [cover_full, cover_small])
	_check(is_equal_approx(cover_small * 16.0, cover_full),
		"y un cuarto de lado es un dieciseisavo de area (%.4f vs %.4f)"
			% [cover_small * 16.0, cover_full])

	var text: String = log_node.call("_light2d_summary")
	_check(text.contains("luz2d=2/2"), "cuenta las dos vivas de dos (%s)" % text)
	_check(text.contains("suma=%.2fx" % (cover_full + cover_small)),
		"y suma cobertura, no luces (%s)" % text)
	_check(text.contains("FullScreen@%.2fx" % cover_full),
		"nombrando la que mas cubre, que es la que hay que mirar (%s)" % text)

	# Una luz apagada no cuenta - que es exactamente lo que el presupuesto de
	# calidad hace, y por tanto lo que este numero tiene que poder mostrar.
	full.enabled = false
	var off: String = log_node.call("_light2d_summary")
	_check(off.contains("luz2d=1/2"),
		"apagar una la saca de las vivas pero no del total (%s)" % off)
	_check(off.contains("Corner@%.2fx" % cover_small),
		"...y el top pasa a la que queda (%s)" % off)

	full.queue_free()
	small.queue_free()
	log_node.queue_free()
	await process_frame


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
