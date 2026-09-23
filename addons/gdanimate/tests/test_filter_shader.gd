extends RefCounted

## F13b-ii.1 - filter_shader.gdshader + apply_filters_to_texture.
## Cubre: blur aplica suavizado, glow suma color, adjust modifica el color.
## El shader DropShadow/Bevel (segundo pase) es F13b-ii.2, no se testea aca.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	await _test_blur_smooths_edges(tree, failures)
	await _test_adjust_color_modifies(tree, failures)
	await _test_empty_filters_passthrough(tree, failures)

	return {
		"name": "filter_shader: blur + adjust + passthrough (F13b-ii.1)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _make_red_texture(size: int) -> ImageTexture:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	return ImageTexture.create_from_image(img)


## Textura con un borde duro: mitad izquierda roja opaca, mitad derecha
## transparente. Sin blur, la columna size/2 - 1 es roja pura (r=1.0).
## Con blur, esa columna mezcla con la mitad transparente y baja de r=1.0.
func _make_half_red_texture(size: int) -> ImageTexture:
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in range(0, size / 2):
			img.set_pixel(x, y, Color.RED)
	return ImageTexture.create_from_image(img)


## Blur 8x8 sobre un patron mitad-y-mitad: el pixel justo antes del corte
## (x = size/2 - 1) debe perder intensidad porque el sample incluye
## transparente.
func _test_blur_smooths_edges(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	var src: ImageTexture = _make_half_red_texture(32)

	# Sanity: antes del blur el pixel en x=15 es rojo puro.
	var src_img: Image = src.get_image()
	var src_px: Color = src_img.get_pixel(15, 16)
	if src_px.r < 0.99:
		failures.push_back("blur_setup: el patron no tiene borde duro (r=%f)" % src_px.r)
		return

	var filters: Array[AdobeFilter] = AdobeFilter.parse_list([
		{"N": "BLF", "BLX": 16.0, "BLY": 16.0, "Q": 1},
	])
	var out: ImageTexture = await baker.apply_filters_to_texture(src, filters, Vector2i(32, 32))

	if out == null:
		failures.push_back("blur: apply devolvio null")
		return
	if out == src:
		failures.push_back("blur: apply devolvio la misma textura (no aplico)")
		return

	var img: Image = out.get_image()
	if img == null:
		failures.push_back("blur: no pude leer la imagen resultante")
		return
	# El pixel en la columna justo antes del corte deberia mezclar con
	# transparente por el blur: r < 1.0.
	var edge: Color = img.get_pixel(15, 16)
	if edge.r >= 0.99:
		failures.push_back("blur: el borde duro no se suavizo (r=%f)" % edge.r)


## AdjustColor con brightness -0.5: los pixeles se oscurecen.
func _test_adjust_color_modifies(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	var src: ImageTexture = _make_red_texture(16)

	var filters: Array[AdobeFilter] = AdobeFilter.parse_list([
		{"N": "ACF", "BRT": -50, "H": 0, "CT": 0, "SAT": 0},
	])
	var out: ImageTexture = await baker.apply_filters_to_texture(src, filters, Vector2i(16, 16))

	if out == null or out == src:
		failures.push_back("adjust: no aplico")
		return

	var img: Image = out.get_image()
	var px: Color = img.get_pixel(8, 8)
	# Brightness -50 => 1 - 0.5 = 0.5 de multiplicador -> rojo ~0.5.
	if px.r >= 0.99:
		failures.push_back("adjust: el rojo no se atenuo (r=%f)" % px.r)


## Sin filtros: devuelve la fuente sin tocar.
func _test_empty_filters_passthrough(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	var src: ImageTexture = _make_red_texture(8)

	var filters: Array[AdobeFilter] = []
	var out: ImageTexture = await baker.apply_filters_to_texture(src, filters, Vector2i(8, 8))

	if out != src:
		failures.push_back("passthrough: con filtros vacios devolvio otra textura")
