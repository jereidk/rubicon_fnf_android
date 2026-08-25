extends SceneTree

## Calibra la formula exacta de un PointLight2D en blend MIX (2) para hornear
## su efecto en una textura: renderiza ColorRect de grises conocidos bajo un
## clon del BgLight del callejon y resuelve, por pixel, el mapa afín
## salida = m * base + c que la luz aplica. Un tercer gris verifica el modelo.
##
## Run with:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/harness/calib_light2d.gd

const OUT := "user://light_calib"
const GREYS := [1.0, 0.5, 0.25]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	get_root().size = Vector2i(1049, 480)
	get_root().content_scale_size = Vector2i(1049, 480)

	var node := Node2D.new()
	root.add_child(node)

	var cam := Camera2D.new()
	cam.position = Vector2(801, 449)  # la posicion del BgLight real
	root.add_child(cam)
	cam.make_current()

	var rect := ColorRect.new()
	rect.size = Vector2(4196, 1920)
	rect.position = Vector2(801 - 2098, 449 - 960)
	node.add_child(rect)

	var light := PointLight2D.new()
	light.blend_mode = Light2D.BLEND_MODE_MIX
	light.position = Vector2(801, 449)
	light.texture = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/darkness_gradient.png")
	light.texture_scale = 4.0
	light.energy = 0.75
	light.range_item_cull_mask = 257
	node.add_child(light)

	var imgs: Array[Image] = []
	for g in GREYS:
		rect.color = Color(g, g, g, 1)
		light.visible = false
		await process_frame
		await process_frame
		var off: Image = get_root().get_texture().get_image()

		light.visible = true
		await process_frame
		await process_frame
		var on: Image = get_root().get_texture().get_image()

		on.save_png(OUT + "/on_%.2f.png" % g)
		off.save_png(OUT + "/off_%.2f.png" % g)
		imgs.append(on)

	# Resolver m y c por pixel con los dos primeros grises y verificar con el tercero.
	# Centro y borde: dos puntos representativos.
	for p in [Vector2i(524, 240), Vector2i(100, 100), Vector2i(900, 400)]:
		var o1: Color = imgs[0].get_pixelv(p)
		var o2: Color = imgs[1].get_pixelv(p)
		var o3: Color = imgs[2].get_pixelv(p)
		for ch in 3:
			var b1 := GREYS[0]
			var b2 := GREYS[1]
			var b3 := GREYS[2]
			var m: float = (o1[ch] - o2[ch]) / (b1 - b2)
			var c: float = o1[ch] - m * b1
			var pred: float = m * b3 + c
			print("OUT px=%s ch=%d m=%.4f c=%.4f | prediccion %.4f real %.4f error %.4f" % [
				str(p), ch, m, c, pred, o3[ch], absf(pred - o3[ch])])

	quit(0)
