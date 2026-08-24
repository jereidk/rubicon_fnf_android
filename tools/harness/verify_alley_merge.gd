extends SceneTree

## Mide la fusion del fondo del callejon contra las siete capas sueltas.
##
## Carga alley.tscn, dibuja el Parallax2 con las capas originales (con Lamp1,
## como quedara encima), luego la version fusionada, y difiere pixel a pixel en
## un viewport con camara fija. El criterio: mediana ~0, p95 pequeno, y peor
## error acotado al borde de Street (el unico remuestreo no entero, 2.38791/2.2).
##
## Run with:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/harness/verify_alley_merge.gd

const ALLEY := "res://lullaby_mod/resources/funkin/songs/safety_lullaby/alley.tscn"
const OUT := "user://alley_merge_check"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var scene: PackedScene = load(ALLEY)
	if scene == null:
		printerr("no carga alley.tscn")
		quit(1)
		return

	var alley: Node2D = scene.instantiate()
	# Fuera de la escena de juego no hay autoloads: el script de la lampara
	# lee Settings en _process. Le quitamos el proceso a todo.
	_alternate(alley)
	root.add_child(alley)

	var cam := Camera2D.new()
	cam.position = Vector2(960, 540)
	cam.zoom = Vector2(0.72, 0.72)  # 1920x1080 de mundo en 1382x778 px
	root.add_child(cam)
	cam.make_current()
	get_root().size = Vector2i(1382, 778)
	get_root().content_scale_size = Vector2i(1382, 778)

	await process_frame
	await process_frame
	var base: Image = get_root().get_texture().get_image()

	# Version fusionada: apagar las 7, encender la fusion.
	var p2: Node = alley.get_node("BG/Parallax2")
	for n: String in ["Street", "Trees", "LongFence", "Bench", "Pokecenter", "Lamp2", "BrokenLamp"]:
		p2.get_node(n).visible = false
	var merged := Sprite2D.new()
	merged.name = "MergedBack"
	merged.light_mask = 3
	merged.position = Vector2(951.4, 508.1)
	merged.scale = Vector2(2.2, 2.2)
	merged.texture = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/back_merged.png")
	p2.add_child(merged)
	p2.move_child(merged, 0)

	await process_frame
	await process_frame
	var fused: Image = get_root().get_texture().get_image()

	base.save_png(OUT + "/original.png")
	fused.save_png(OUT + "/fusionado.png")

	# Diff
	var w: int = mini(base.get_width(), fused.get_width())
	var h: int = mini(base.get_height(), fused.get_height())
	var diffs: Array[int] = []
	var worst := 0
	var worst_at := Vector2i.ZERO
	var changed := 0
	for y in h:
		for x in w:
			var a: Color = base.get_pixel(x, y)
			var b: Color = fused.get_pixel(x, y)
			var d: int = int(maxi(maxi(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0)
			diffs.append(d)
			if d > 0:
				changed += 1
			if d > worst:
				worst = d
				worst_at = Vector2i(x, y)
	diffs.sort()
	var p50: int = diffs[diffs.size() / 2]
	var p95: int = diffs[int(diffs.size() * 0.95)]
	var p99: int = diffs[int(diffs.size() * 0.99)]
	print("OUT mediana=%d p95=%d p99=%d peor=%d en %s cambiados=%d/%d (%.2f%%)" % [
		p50, p95, p99, worst, str(worst_at), changed, diffs.size(), 100.0 * changed / diffs.size()])

	quit(0 if (p95 <= 8 and worst <= 64) else 1)


func _alternate(n: Node) -> void:
	n.set_process(false)
	n.set_physics_process(false)
	n.set_process_input(false)
	for c in n.get_children():
		_alternate(c)
