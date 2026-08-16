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
	n._dep_ms = {"a/b": 3000.0, "c/d": 12000.0, "e/f": 500.0}
	n._dep_count = {"a/b": 10, "c/d": 97, "e/f": 2}
	var line: String = n._dep_breakdown()
	print("desglose: %s" % line)
	if not line.begins_with("c/d=12.0s/97"): print("FALLO no ordena por coste"); bad += 1
	else: print("ok    ordena por coste, el peor primero")
	n._dep_ms = {}; n._dep_count = {}
	if n._dep_breakdown() != "-": print("FALLO vacio"); bad += 1
	else: print("ok    vacio da '-'")
	print("" if bad else "todo OK - el desglose por subsistema")
	quit(1 if bad else 0)
