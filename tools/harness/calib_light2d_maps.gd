extends SceneTree

## Saca los dos mapas de la luz: salida con base=1.0 (m+c) y base=0.0 (c),
## a resolucion 1:1 con la textura del gradiente. Con ellos el horneado de
## Python reconstruye m y c por texel sin asumir la formula del shader.
##
## Run with:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --script tools/harness/calib_light2d_maps.gd

const OUT := "user://light_calib"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	get_root().size = Vector2i(1049, 480)
	get_root().content_scale_size = Vector2i(1049, 480)

	var node := Node2D.new()
	root.add_child(node)

	var cam := Camera2D.new()
	cam.position = Vector2(801, 449)
	cam.zoom = Vector2(0.25, 0.25)  # 4196x1920 de mundo = toda la textura, 1px/texel
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

	for g in [1.0, 0.0]:
		rect.color = Color(g, g, g, 1)
		await process_frame
		await process_frame
		var on: Image = get_root().get_texture().get_image()
		on.save_png(OUT + "/map_base_%.1f.png" % g)
		print("OUT map_base_%.1f guardado %dx%d" % [g, on.get_width(), on.get_height()])

	quit(0)
