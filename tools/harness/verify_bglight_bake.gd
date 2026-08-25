extends SceneTree

## A/B de estado final del horneado del BgLight: renderiza el alley con la
## textura SIN hornear y la luz viva a energy=0.75 (el override de la
## cancion), y luego con la textura horneada y light_mask=0. La referencia se
## construye en la misma corrida - la textura no-horneada vive solo en el
## sandbox, como back_merged_unbaked_test.png.
##
## Run with:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/harness/verify_bglight_bake.gd

const ALLEY := "res://lullaby_mod/resources/funkin/songs/safety_lullaby/alley.tscn"
const UNBAKED := "res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/back_merged_unbaked_test.png"
const CROPS := {
	"general": [Vector2(960, 540), 0.72],
	"lamp1_union": [Vector2(2051, 400), 2.2],
	"centro_luz": [Vector2(801, 449), 2.2],
	"borde_mundo": [Vector2(-231, 603), 2.2],
}

var _fail := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	get_root().size = Vector2i(1382, 778)
	get_root().content_scale_size = Vector2i(1382, 778)
	var cam := Camera2D.new()
	root.add_child(cam)
	cam.make_current()

	var unbaked: Texture2D = load(UNBAKED)
	if unbaked == null:
		printerr("OUT falta la copia no-horneada del sandbox")
		quit(1)
		return

	for crop: String in CROPS:
		# Estado A: fondo no horneado, luz viva a 0.75 (el override de la cancion)
		var alley: Node2D = (load(ALLEY) as PackedScene).instantiate()
		var bg: Node = alley.get_node("BG/Parallax2/MergedBack")
		bg.texture = unbaked
		bg.light_mask = 3
		var light: PointLight2D = alley.get_node("BG/BgLight")
		light.energy = 0.75
		root.add_child(alley)
		cam.position = CROPS[crop][0]
		cam.zoom = Vector2.ONE * CROPS[crop][1]
		await process_frame
		await process_frame
		var ref: Image = get_root().get_texture().get_image()
		alley.queue_free()
		await process_frame

		# Estado B: la escena tal cual queda (horneado, mask 0)
		var alley2: Node2D = (load(ALLEY) as PackedScene).instantiate()
		var light2: PointLight2D = alley2.get_node("BG/BgLight")
		light2.energy = 0.75
		root.add_child(alley2)
		await process_frame
		await process_frame
		var now: Image = get_root().get_texture().get_image()
		alley2.queue_free()
		await process_frame

		var w: int = mini(ref.get_width(), now.get_width())
		var h: int = mini(ref.get_height(), now.get_height())
		var diffs: Array[int] = []
		var worst := 0
		for y in h:
			for x in w:
				var a: Color = ref.get_pixel(x, y)
				var b: Color = now.get_pixel(x, y)
				var d: int = int(maxi(maxi(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b)) * 255.0)
				diffs.append(d)
				if d > worst:
					worst = d
		diffs.sort()
		var p99: int = diffs[int(diffs.size() * 0.99)]
		print("OUT %s p99=%d peor=%d" % [crop, p99, worst])
		if p99 > 4 or worst > 24:
			_fail = true

	quit(1 if _fail else 0)
