extends SceneTree
const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	await process_frame
	var n: Node = root.get_node_or_null(^"DiagnosticsLog")
	if n == null: print("FALLO sin autoload"); quit(1); return
	var cases := {
		"res://lullaby_mod/resources/console/console.tscn": "lullaby_mod/resources/console",
		"res://lullaby_mod/rooms/env_collector_shop.tscn": "lullaby_mod/rooms",
		"res://project.godot": ".",
		"res://addons/rubicon/scripts/data/chart/rubichart.gd": "addons/rubicon/scripts",
	}
	var bad := 0
	for path in cases:
		var got: String = n._dep_owner(path)
		if got != cases[path]:
			print("FALLO %s -> %s (esperaba %s)" % [path, got, cases[path]]); bad += 1
		else:
			print("ok    %-58s -> %s" % [path.get_file(), got])
	# The totals must be able to add up to a real load. The first version
	# charged the whole poll interval to every dependency that arrived in it,
	# so a 4.8 second load reported 188.5s for one subsystem across its 186
	# dependencies - which made the ranking a proxy for dependency count, the
	# one thing it exists to look past.
	n._dep_ms = {"a/b": 3000.0, "c/d": 12000.0, "e/f": 500.0}
	n._dep_count = {"a/b": 10, "c/d": 97, "e/f": 2}
	var line: String = n._dep_breakdown()
	print("desglose: %s" % line)
	if not line.begins_with("c/d=12.0s/97"): print("FALLO no ordena por coste"); bad += 1
	else: print("ok    ordena por coste, el peor primero")
	# The split itself, driven through the real accumulator: two subsystems
	# arriving in the same interval get half of it each, not all of it each.
	n._dep_ms = {}; n._dep_count = {}; n._dep_clock = Time.get_ticks_msec() - 1000
	n._incoming_deps = ["res://a"] as Array[String]
	# Autoload scripts, which are certainly in the cache. The first attempt
	# used two paths without checking, neither was cached, nothing "arrived"
	# and the split had nothing to divide - the check failed against a
	# correct implementation.
	var pending := PackedStringArray()
	for cand in ["res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd",
			"res://lullaby_mod/scripts/lullaby/loading/lullaby_scene_changer.gd",
			"res://menus/settings.gd", "res://menus/scene_changer.gd"]:
		if ResourceLoader.has_cached(cand):
			pending.append(cand)
	if pending.size() < 2:
		print("FALLO no hay 2 rutas cacheadas con las que probar el reparto"); bad += 1
	n._incoming_pending = pending
	n._incoming_cached = {}
	n._incoming_progress()
	var total: float = 0.0
	for k in n._dep_ms: total += float(n._dep_ms[k])
	if total > 1200.0 or total < 800.0:
		print("FALLO el intervalo no se reparte: total %.0fms de 1000" % total); bad += 1
	else:
		print("ok    un intervalo de 1000ms se reparte, no se duplica (%.0fms)" % total)

	n._dep_ms = {}; n._dep_count = {}
	if n._dep_breakdown() != "-": print("FALLO vacio"); bad += 1
	else: print("ok    vacio da '-'")
	print("" if bad else "todo OK - el desglose por subsistema")
	quit(1 if bad else 0)
