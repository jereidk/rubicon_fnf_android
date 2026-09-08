extends SceneTree
func _init() -> void:
	root.ready.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var n: Node = (load("res://songs/dadbattle/dadbattle.tscn") as PackedScene).instantiate()
	root.add_child(n)
	for _i in 40:
		await process_frame
	var cam: Camera2D = n.get_node("RubiconInterpolatedCamera2D")
	print("OUT camara pos=%s zoom=%s" % [str(cam.global_position), str(cam.zoom)])
	for path: String in ["Stage/Bf", "Stage/Gf", "Stage/DadBeast"]:
		var c: Node2D = n.get_node_or_null(path)
		if c == null:
			print("OUT %s NO EXISTE" % path); continue
		print("OUT %-16s pos=%-22s visible=%s escala=%s" % [path, str(c.position),
			str(c.visible), str(c.scale)])
	for path: String in ["UILayer/UI/HealthBar", "UILayer/UI/Player", "TimeBarLayer/TimeBar"]:
		var c: CanvasItem = n.get_node_or_null(path)
		if c == null:
			print("OUT %s NO EXISTE" % path); continue
		var r: Control = c as Control
		print("OUT %-22s pos=%-18s size=%-16s visible=%s alfa=%.2f" % [path,
			str(r.position), str(r.size), str(c.visible), c.modulate.a])
	quit()
