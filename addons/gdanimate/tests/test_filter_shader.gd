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
	await _test_drop_shadow_adds_pixels(tree, failures)
	await _test_bevel_adds_pixels(tree, failures)

	return {
		"name": "filter_shader: blur + adjust + dropshadow + bevel (F13b-ii)",
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


## DropShadow: sobre una textura con contenido opaco, agregar pixeles
## semi-transparentes donde no habia nada (el shadow expandido).
func _test_drop_shadow_adds_pixels(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	var src: ImageTexture = _make_half_red_texture(32)

	var filters: Array[AdobeFilter] = AdobeFilter.parse_list([
		{"N": "DSF", "D": 6.0, "AL": 45.0, "C": "#000000", "A": 0.8, "BLX": 2.0, "BLY": 2.0, "STR": 100.0},
	])
	var out: ImageTexture = await baker.apply_filters_to_texture(src, filters, Vector2i(32, 32))

	if out == null or out == src:
		failures.push_back("dropshadow: no aplico")
		return

	var img: Image = out.get_image()
	# El shadow va hacia abajo-derecha por angle 45. Mirar en (18, 18) que
	# estaba transparente en la fuente.
	var px: Color = img.get_pixel(18, 18)
	# Deberia tener algo de alpha (el shadow se extendio ahi).
	if px.a <= 0.0:
		failures.push_back("dropshadow: no extendio alpha a la zona del shadow (a=%f)" % px.a)


## Bevel: sobre un borde duro, agregar highlight en un lado y shadow en el
## otro. El pixel del borde debe cambiar de color.
func _test_bevel_adds_pixels(tree: SceneTree, failures: Array[String]) -> void:
	var baker: AdobeRenderBaker = AdobeRenderBaker.instance()
	var src: ImageTexture = _make_half_red_texture(32)

	var filters: Array[AdobeFilter] = AdobeFilter.parse_list([
		{"N": "BF", "D": 4.0, "AL": 45.0, "HC": "#FFFFFF", "HA": 1.0, "SC": "#000000", "SA": 1.0, "BLX": 2.0, "BLY": 2.0, "STR": 100.0},
	])
	var out: ImageTexture = await baker.apply_filters_to_texture(src, filters, Vector2i(32, 32))

	if out == null or out == src:
		failures.push_back("bevel: no aplico")
		return

	var img: Image = out.get_image()
	# El bevel cambia el color del borde del patron. Mirar el pixel justo
	# en el corte (x=16, y=16) que en la fuente es transparente, ahora
	# puede tener highlight o shadow.
	var px: Color = img.get_pixel(16, 16)
	if px.a <= 0.0 and px.r == 0.0 and px.g == 0.0 and px.b == 0.0:
		failures.push_back("bevel: no agrego pixel en el borde del patron")
