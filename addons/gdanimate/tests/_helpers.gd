extends RefCounted

## Helpers compartidos por los test_*.gd. Nombre con "_" adelante a proposito:
## run_tests.gd descubre archivos por el patron "test_*.gd" y este no tiene
## que aparecer en esa lista (no tiene run(), pero mejor ni pasar por el filtro).


## Deja pasar N frames para que el rendering server aplique cambios de
## canvas_item antes de capturar un Viewport.
static func wait_frames(tree: SceneTree, count: int = 3) -> void:
	for i in count:
		await tree.process_frame


## Captura el Viewport raiz a PNG bajo tests/visual/output/. Devuelve el path
## res:// final, o "" si fallo.
static func capture_png(tree: SceneTree, file_name: String) -> String:
	var img: Image = tree.root.get_texture().get_image()
	if img == null:
		return ""
	var path: String = "res://addons/gdanimate/tests/visual/output/%s" % file_name
	var err: Error = img.save_png(path)
	if err != OK:
		printerr("No se pudo guardar %s (error %d)" % [path, err])
		return ""
	return path


## Crea un ImageTexture solido de un color, para usar como sprite de prueba
## sin necesitar un spritemap real en disco.
static func make_solid_texture(color: Color, size: Vector2i) -> ImageTexture:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## AdobeAtlas listo para tests que arman symbols/spritemap a mano en vez de
## via parse() (lo normal para fixtures sinteticos). OJO: parse() es quien
## normalmente pone format="adobe" (adobe_atlas.gd:54) - sin este helper (o
## sin poner atlas.format a mano) AnimateSymbol._draw_impl no dibuja nada,
## porque matchea contra atlas.format para elegir "adobe" vs "sparrow" y el
## default de AnimateAtlas es "placeholder". Ya me comi este bug una vez.
##
## SEGUNDO GOTCHA, tambien ya sufrido: `AdobeAtlas.draw_on()` hace `if
## stage_symbol.is_empty(): return` como primera linea (adobe_atlas.gd) - si
## el fixture llena `atlas.symbols` pero nunca `atlas.stage_symbol`, draw_on
## vuelve sin dibujar NADA, en silencio, sin error. Sea cual sea el nombre
## del symbol que el test vaya a usar (via AnimateSymbol.symbol), hay que
## ademas poner `atlas.stage_symbol = &"ese-nombre"` (no importa que sea
## literalmente el simbolo raiz real; alcanza con que no este vacio - el
## codigo cae al symbol pedido via `symbols.has(draw_info.symbol)` de
## cualquier forma). Este helper NO lo hace por vos porque no sabe que
## nombre vas a usar - ponelo vos despues de llenar atlas.symbols.
static func make_test_atlas() -> AdobeAtlas:
	var atlas: AdobeAtlas = AdobeAtlas.new()
	atlas.format = "adobe"
	atlas.framerate = 24.0
	return atlas
