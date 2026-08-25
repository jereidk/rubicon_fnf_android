extends SceneTree

## Banco 2D de Safety Lullaby en la ruta del telefono (Vulkan, Forward Mobile,
## 1600x720): cada capa grande de la cancion se mide apilada, igual que el
## banco de las cuatro reglas del relleno.
##
## Escenarios:
##   base        - el ColorRect de fondo solo
##   capas       - base + los 4 rect a pantalla completa (sky, clouds, mtn, front)
##   luz_N       - capas + N PointLight2D con la textura de gradiente real
##   mtn_opaco   - la montana opaca con blend_mix y con blend_disabled
##   squiggle    - capas + el shader real del SquiggleLayer
##
## Run with:
##   xvfb-run -a godot --rendering-driver vulkan --rendering-method mobile \
##     --path . --script tools/harness/bench_safety_fill.gd

const W := 1600
const H := 720
const FRAMES := 40

var _vp: Window
var _root2d: Node2D
var _layers: Array[CanvasItem] = []
var _lights: Array[PointLight2D] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_vp = root
	_vp.size = Vector2i(W, H)
	_vp.content_scale_size = Vector2i(W, H)
	_vp.transparent_bg = false
	_root2d = Node2D.new()
	root.add_child(_root2d)

	var bg_tex: Texture2D = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/back_merged.png")
	var dark_tex: Texture2D = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/darkness_gradient.png")
	var light_tex: Texture2D = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/awesomeahhlight.png")
	var mtn_tex: Texture2D = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/mountain.png")
	var cloud_tex: Texture2D = load("res://lullaby_mod/assets/funkin/safety_lullaby/maps/alley/clouds.png")

	# base: el fondo fusionado cubriendo
	var bg := Sprite2D.new()
	bg.texture = bg_tex
	bg.centered = true
	bg.position = Vector2(W, H) / 2
	bg.scale = Vector2(2.0, 2.0)
	_root2d.add_child(bg)

	# rect a pantalla completa: sky (gradiente), clouds, mountain, fronttree
	var sky := _fullrect(Color(0.11, 0.13, 0.13, 1))
	var clouds := Sprite2D.new()
	clouds.texture = cloud_tex
	clouds.position = Vector2(W, H) / 2
	clouds.scale = Vector2(2.25, 2.25)
	clouds.modulate = Color(0.75, 0.75, 0.75, 1)
	var mtn := Sprite2D.new()
	mtn.texture = mtn_tex
	mtn.position = Vector2(W * 0.8, 140)
	mtn.scale = Vector2(2.25, 2.25)
	var front := _fullrect(Color(0.02, 0.02, 0.02, 0.35))
	for c: CanvasItem in [sky, clouds, mtn, front]:
		_root2d.add_child(c)
		_layers.append(c)

	var gpu: Callable = func() -> float:
		return RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid())

	# El "base" es SOLO el fondo: las cuatro capas entran despues.
	for c in _layers:
		c.visible = false
	print("OUT base                %0.2f" % await _measure(gpu))

	for c in _layers:
		c.visible = true
	print("OUT capas(4 full)       %0.2f" % await _measure(gpu))

	# luces 2D (una cada pasada, apiladas sobre las capas)
	for i in 4:
		var l := PointLight2D.new()
		l.texture = light_tex
		l.texture_scale = 4.0
		l.position = Vector2(300 + i * 350, 400)
		l.energy = 1.0
		l.visible = false
		_root2d.add_child(l)
		_lights.append(l)
	for i in _lights.size():
		_lights[i].visible = true
		print("OUT luz_%d               %0.2f" % [i + 1, await _measure(gpu)])
	for l in _lights:
		l.visible = false

	# blend_disabled sobre una capa opaca a pantalla completa (la regla 3)
	mtn.z_index = 5
	var mtn_disabled := Sprite2D.new()
	mtn_disabled.texture = mtn_tex
	mtn_disabled.position = mtn.position
	mtn_disabled.scale = mtn.scale
	mtn_disabled.z_index = 5
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; render_mode blend_disabled;\nvoid fragment(){ COLOR = texture(TEXTURE, UV); }"
	mat.shader = sh
	mtn_disabled.material = mat
	mtn.visible = false
	_root2d.add_child(mtn_disabled)
	print("OUT mtn blend_disabled  %0.2f" % await _measure(gpu))
	mtn_disabled.visible = false
	mtn.visible = true
	print("OUT mtn blend_mix       %0.2f" % await _measure(gpu))

	quit(0)


func _fullrect(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.size = Vector2(W, H)
	return r


func _measure(_gpu: Callable) -> float:
	# En llvmpipe la query de GPU no contesta (0.0 siempre); y al ser software,
	# el wall-clock por frame ES el coste de rasterizar - no hay pipeline
	# asincrono que esconda el trabajo. Misma tecnica que render_scale_sweep.gd.
	for i in 6:
		await process_frame
	Engine.max_fps = 0
	var t0: int = Time.get_ticks_usec()
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	var t1: int = Time.get_ticks_usec()
	return float(t1 - t0) / 1000.0 / FRAMES
