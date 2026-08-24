extends SceneTree

## 1:1 texel check of the merged alley background against the seven loose
## layers, at several crops. zoom 2.2 = one texture texel per screen pixel,
## so a placement error of half a world unit shows as a full-pixel shift.
##
## Run with:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/harness/verify_alley_merge_1to1.gd

const ALLEY := "res://lullaby_mod/resources/funkin/songs/safety_lullaby/alley.tscn"
const OUT := "user://alley_merge_check"

const CROPS := {
	"banco_valla": Vector2(1518, 722),
	"pokecenter_lamp2": Vector2(700, 250),
	"lamp1_union": Vector2(2051, 400),
	"brokenlamp_borde": Vector2(-231, 603),
	"calle_centro": Vector2(936, 968),
}

var _fail := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var scene: PackedScene = load(ALLEY)
	var cam := Camera2D.new()
	cam.zoom = Vector2(2.2, 2.2)
	root.add_child(cam)
	cam.make_current()
	get_root().size = Vector2i(1382, 778)
	get_root().content_scale_size = Vector2i(1382, 778)

	for crop: String in CROPS:
		var alley: Node2D = scene.instantiate()
		root.add_child(alley)
		cam.position = CROPS[crop]
		await process_frame
		await process_frame
		var base: Image = get_root().get_texture().get_image()

		var p2: Node = alley.get_node("BG/Parallax2")
		for n: String in ["Street", "Trees", "LongFence", "Bench", "Pokecenter", "Lamp2", "BrokenLamp"]:
			p2.get_node(n).visible = false
		var merged := Sprite2D.new()
		merged.light_mask = 3
		merged.position = Vector2(951.4, 508.1)
		merged.scale = Vector2(2.2, 2.2)
		merged.texture = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/back_merged.png")
		p2.add_child(merged)
		p2.move_child(merged, 0)

		await process_frame
		await process_frame
		var fused: Image = get_root().get_texture().get_image()

		base.save_png(OUT + "/1to1_%s_original.png" % crop)
		fused.save_png(OUT + "/1to1_%s_fusionado.png" % crop)

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
				if d > 2:
					changed += 1
				if d > worst:
					worst = d
					worst_at = Vector2i(x, y)
		diffs.sort()
		var p95: int = diffs[int(diffs.size() * 0.95)]
		var p99: int = diffs[int(diffs.size() * 0.99)]
		print("OUT %s p95=%d p99=%d peor=%d en %s cambiados(>2)=%d (%.3f%%)" % [
			crop, p95, p99, worst, str(worst_at), changed, 100.0 * changed / diffs.size()])
		if p99 > 12:
			_fail = true

		alley.queue_free()
		await process_frame

	quit(1 if _fail else 0)
