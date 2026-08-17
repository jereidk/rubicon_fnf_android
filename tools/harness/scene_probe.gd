extends Node

## Reads back what a real game scene actually did, without rendering it.
##
## The sibling of scene_shot.gd and the one to reach for first: it answers "is
## this node visible right now, and what rect does it cover" in seconds, where
## the renderer takes a minute a frame under software GL.
##
##   godot --headless --path . res://tools/harness/scene_probe.tscn \
##     -- res://lullaby_mod/songs/chimera/sng_chimera.tscn all 3d t=40 t=100
##
## Arguments after `--`: the scene, then any of
##
##   precache   make PreloadCamera take its shipped path. It reads
##              SceneChanger.awaiting_manual_end in _ready() and frees itself
##              on the spot when that is false, so without this the warm-up
##              never runs and anything that lives in it is invisible.
##   all        every visible CanvasItem that paints, biggest first, with its
##              rect in base pixels, its CanvasLayer and its effective alpha.
##   3d         every visible mesh projected onto the screen through the live
##              camera. The 2D list cannot see a mesh in front of the camera,
##              and a mesh covers the stage and draws under every CanvasLayer
##              by construction.
##   t=<secs>   advance the song's own timeline to that position and dump
##              again. Repeatable.
##   <path>     report this node's visibility by name.
##
## Run it as a SCENE, as above - not with `--script`. A SceneTree script gets
## no autoloads, so `Settings` reads null, anything gated on a settings value
## takes its default branch, and the scene answers a question you did not ask.
##
## `advance()` and never `seek()`: `precache` and the song timeline both
## dispatch clips through `animation` tracks, and a clip stepped with seek() is
## assigned and never advanced.
##
## Sample densely. A value track paints its first key over all time before it
## and a sequence can switch something on for five seconds, so the interesting
## window is often narrower than the gap between two samples. The first sweep
## here stepped 20s at a time and walked straight past the one that mattered.

var _scene_path: String = "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
var _precache: bool = false
var _all: bool = false
var _3d: bool = false
var _at: Array[float] = []
var _watch: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() > 0: _scene_path = argv[0]
	for i in range(1, argv.size()):
		var a: String = argv[i]
		if a == "precache": _precache = true
		elif a == "all": _all = true
		elif a == "3d": _3d = true
		elif a.begins_with("t="): _at.append(float(a.substr(2)))
		else: _watch.append(a)

	var s: Node = get_node_or_null(^"/root/Settings")
	print("OUT Settings=%s post_processing=%s disable_shader_effects=%s" % [
		s != null,
		s.get("graphics_post_processing") if s else "-",
		s.get("graphics_disable_shader_effects") if s else "-"])

	var changer: Node = get_node_or_null(^"/root/SceneChanger")
	if _precache and changer != null and "awaiting_manual_end" in changer:
		changer.set("awaiting_manual_end", true)

	var scene: Node = (load(_scene_path) as PackedScene).instantiate()
	add_child(scene)

	# Announced as the current scene, not just parented.
	#
	# DiagnosticsLog builds every watch list off get_tree().current_scene, so
	# without this the autoload profiles the harness - a Node with no meshes
	# and no rects - and the log comes back with no BLACKWATCH and no
	# BLACKOUT at all, which reads exactly like "nothing is covering the
	# screen" instead of "nothing was looked at".
	get_tree().current_scene = scene

	# And rebuilt, because announcing it is not enough either: the collector
	# runs a second after SceneChanger reports a change finished, and nothing
	# here goes through SceneChanger.
	var diag: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if diag != null and diag.has_method("rescan_scene"):
		diag.call("rescan_scene")

	_silence_gameover(scene)
	for _i in 5: await get_tree().process_frame
	_dump(scene, "tras _ready")

	if _precache:
		var pre: AnimationPlayer = scene.get_node_or_null(^"PreloadCamera/AnimationPlayer") as AnimationPlayer
		if pre != null and pre.has_animation(&"precache"):
			pre.play(&"precache")
			for _i in 60:
				pre.advance(1.0 / 60.0)
				await get_tree().process_frame
		_dump(scene, "tras precache")

	if _at.is_empty():
		get_tree().quit()
		return

	var clock: AnimationPlayer = _find_timeline(scene)
	if clock == null:
		print("OUT sin linea de tiempo, no puedo avanzar")
		get_tree().quit()
		return

	clock.play(&"scene")
	var done: float = 0.0
	for target in _at:
		while done < target:
			clock.advance(1.0 / 60.0)
			done += 1.0 / 60.0
		await get_tree().process_frame
		await get_tree().process_frame
		_dump(scene, "en scene@%.2fs" % clock.current_animation_position)
	get_tree().quit()


## The song's own timeline. Found by looking for the player that owns an
## animation called `scene` rather than by name: Monochrome and Chimera call
## it RubiconLevelClock, safety_lullaby calls it Clock.
func _find_timeline(scene: Node) -> AnimationPlayer:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var p := node as AnimationPlayer
		if p != null and p.has_animation(&"scene"):
			return p
		for child in node.get_children():
			stack.append(child)
	return null


## The heartbeat mechanic drains health with nobody playing, so the scene
## reaches its gameover within seconds and every dump after that describes the
## death screen instead of the song.
func _silence_gameover(scene: Node) -> void:
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script() as Script
		if script != null and "gameover" in script.resource_path.to_lower():
			node.process_mode = Node.PROCESS_MODE_DISABLED
		for child in node.get_children():
			stack.append(child)


func _dump(scene: Node, when: String) -> void:
	print("OUT === %s ===" % when)
	for path in _watch:
		var n: Node = scene.get_node_or_null(NodePath(path))
		if n == null:
			print("OUT %-52s LIBERADO/AUSENTE" % path)
			continue
		print("OUT %-52s visible=%-5s en_arbol=%s" % [
			path, n.get("visible"), n.is_visible_in_tree()])
	if _3d:
		_dump_3d(scene)
	if not _all:
		return

	var rows: Array = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var item := node as CanvasItem
		if item == null or not item.is_visible_in_tree():
			continue
		if not _paints(item):
			continue
		var r: Rect2 = _rect_of(item)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		rows.append([r.size.x * r.size.y, r, item, _layer_of(item)])
	rows.sort_custom(func(a, b): return a[0] > b[0])

	print("OUT     %d CanvasItems visibles que pintan; marco base %dx%d" % [
		rows.size(),
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))])
	for row in rows.slice(0, 24):
		var item: CanvasItem = row[2]
		var r: Rect2 = row[1]
		print("OUT     %4dx%-4d en %5d,%-5d capa=%-3d a=%.2f  %-16s %s" % [
			roundi(r.size.x), roundi(r.size.y), roundi(r.position.x), roundi(r.position.y),
			row[3], item.modulate.a * item.self_modulate.a, item.get_class(),
			scene.get_path_to(item)])


## Every visible 3D mesh, projected onto the screen through the live camera.
##
## The 2D sweep answers "is a Control covering the stage". This answers the
## other half - a mesh in front of the camera covers the stage too, draws under
## every CanvasLayer by construction, and no CanvasItem walk can see it.
func _dump_3d(scene: Node) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		print("OUT     sin Camera3D activa")
		return
	print("OUT     camara=%s fov=%.1f pos=%.2f,%.2f,%.2f" % [
		scene.get_path_to(cam), cam.fov,
		cam.global_position.x, cam.global_position.y, cam.global_position.z])
	var size: Vector2 = get_viewport().get_visible_rect().size
	var rows: Array = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var geo := node as GeometryInstance3D
		if geo == null or not geo.is_visible_in_tree():
			continue
		var aabb: AABB = geo.get_aabb()
		var xform: Transform3D = geo.global_transform
		var lo: Vector2 = Vector2.INF
		var hi: Vector2 = -Vector2.INF
		var clipped: bool = false
		for i in 8:
			var world: Vector3 = xform * aabb.get_endpoint(i)
			# A corner behind the camera has no projection, and feeding it to
			# unproject_position() returns a point mirrored to the far side of
			# the screen. Dropped, and the row is marked, rather than silently
			# reporting a rect that is inside out.
			if cam.is_position_behind(world):
				clipped = true
				continue
			var p2: Vector2 = cam.unproject_position(world)
			lo = lo.min(p2)
			hi = hi.max(p2)
		if lo.x == INF:
			continue
		var r: Rect2 = Rect2(lo, hi - lo).intersection(Rect2(Vector2.ZERO, size))
		if r.size.x <= 1.0 or r.size.y <= 1.0:
			continue
		rows.append([r.size.x * r.size.y, r, geo, clipped])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("OUT     %d mallas 3D visibles; pantalla %dx%d" % [
		rows.size(), int(size.x), int(size.y)])
	for row in rows.slice(0, 14):
		var geo: GeometryInstance3D = row[2]
		var r: Rect2 = row[1]
		print("OUT     %4dx%-4d en %5d,%-5d %s %-42s %s" % [
			roundi(r.size.x), roundi(r.size.y), roundi(r.position.x), roundi(r.position.y),
			"(recortada)" if row[3] else "           ",
			scene.get_path_to(geo), _materials_of(geo)])


## What is actually bound on each of a mesh's surfaces.
##
## Asked override-first and mesh-second, which is the order the renderer uses -
## the same order _collect_blackout_watch already applies. It matters twice
## over here: a material that lives on the mesh RESOURCE rather than on an
## override is one `Settings.graphics_disable_shader_effects` cannot strip, so
## it survives every quality preset, and it is invisible to any sweep that only
## reads the node.
##
## Prints albedo and shading mode because that is the question being asked -
## "flat opaque black" is then something this output states rather than
## something to read off a screenshot.
func _materials_of(geo: GeometryInstance3D) -> String:
	if geo.material_override != null:
		return "override:" + _describe(geo.material_override)
	var mesh_node := geo as MeshInstance3D
	if mesh_node == null or mesh_node.mesh == null:
		return "-"
	var out: PackedStringArray = PackedStringArray()
	for surface in mesh_node.mesh.get_surface_count():
		var mat: Material = mesh_node.get_surface_override_material(surface)
		var where: String = "surf%d" % surface
		if mat == null:
			mat = mesh_node.mesh.surface_get_material(surface)
			where = "malla%d" % surface
		out.append(where + ":" + _describe(mat))
	return " ".join(out)


func _describe(mat: Material) -> String:
	if mat == null:
		return "SIN MATERIAL"
	var shader_mat := mat as ShaderMaterial
	if shader_mat != null:
		return "shader(%s)" % (shader_mat.shader.resource_path.get_file() if shader_mat.shader else "?")
	var std := mat as BaseMaterial3D
	if std == null:
		return mat.get_class()
	var c: Color = std.albedo_color
	return "albedo(%.2f,%.2f,%.2f,%.2f)%s%s" % [
		c.r, c.g, c.b, c.a,
		" UNSHADED" if std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED else "",
		"" if std.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED else " transp%d" % std.transparency]


func _rect_of(item: CanvasItem) -> Rect2:
	var control := item as Control
	if control != null:
		return control.get_global_rect()
	if item.has_method("get_rect"):
		return item.get_global_transform() * (item.call("get_rect") as Rect2)
	return Rect2()


## Whether this CanvasItem puts pixels on screen itself. A bare Control and
## every layout Container draw nothing at all, and counting their rects adds
## the screen several times over for nodes that never touch a pixel.
func _paints(item: CanvasItem) -> bool:
	var control := item as Control
	if control == null:
		return item.has_method("get_rect")
	if control is Container:
		return control is SubViewportContainer or control is PanelContainer
	return control.get_class() != "Control"


func _layer_of(item: CanvasItem) -> int:
	var node: Node = item
	while node != null:
		var layer := node as CanvasLayer
		if layer != null:
			return layer.layer
		node = node.get_parent()
	return 0
