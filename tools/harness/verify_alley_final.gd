extends SceneTree

## Renderiza el alley.tscn YA EDITADO (MergedBack) y lo difiere contra los
## renders guardados del alley ORIGINAL (las siete capas sueltas), a zoom 2.2
## (texel 1:1) y al encuadre general.
##
## Run with:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/harness/verify_alley_final.gd

const ALLEY := "res://lullaby_mod/resources/funkin/songs/safety_lullaby/alley.tscn"
const OUT := "user://alley_merge_check"

const CROPS := {
	"general": [Vector2(960, 540), 0.72],
	"banco_valla": [Vector2(1518, 722), 2.2],
	"pokecenter_lamp2": [Vector2(700, 250), 2.2],
	"lamp1_union": [Vector2(2051, 400), 2.2],
	"brokenlamp_borde": [Vector2(-231, 603), 2.2],
	"calle_centro": [Vector2(936, 968), 2.2],
}

var _fail := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load(ALLEY)
	if scene == null:
		printerr("no carga alley.tscn")
		quit(1)
		return
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()
	get_root().size = Vector2i(1382, 778)
	get_root().content_scale_size = Vector2i(1382, 778)

	for crop: String in CROPS:
		var ref_path: String = OUT + ("/original.png" if crop == "general" else "/1to1_%s_original.png" % crop)
		var ref := Image.load_from_file(ref_path)
		if ref == null:
			printerr("OUT %s sin referencia guardada" % crop)
			_fail = true
			continue

		var alley: Node2D = scene.instantiate()
		root.add_child(alley)
		cam.position = CROPS[crop][0]
		cam.zoom = Vector2.ONE * CROPS[crop][1]
		await process_frame
		await process_frame
		var now: Image = get_root().get_texture().get_image()
		now.save_png(OUT + "/final_%s.png" % crop)

		var w: int = mini(ref.get_width(), now.get_width())
		var h: int = mini(ref.get_height(), now.get_height())
		var diffs: Array[int] = []
		var worst := 0
		var changed := 0
		for y in h:
			for x in w:
				var a: Color = ref.get_pixel(x, y)
				var b: Color = now.get_pixel(x, y)
				var d: int = int(maxi(maxi(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0)
				diffs.append(d)
				if d > 2:
					changed += 1
				if d > worst:
					worst = d
		diffs.sort()
		var p95: int = diffs[int(diffs.size() * 0.95)]
		var p99: int = diffs[int(diffs.size() * 0.99)]
		print("OUT %s p95=%d p99=%d peor=%d cambiados(>2)=%d (%.3f%%)" % [
			crop, p95, p99, worst, changed, 100.0 * changed / diffs.size()])
		if p99 > 12:
			_fail = true
		alley.queue_free()
		await process_frame

	quit(1 if _fail else 0)
