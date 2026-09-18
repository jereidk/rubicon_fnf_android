extends Control
## Logo animado (bump) del menu, leido de un atlas Sparrow (PNG + XML).
##
## El XML de FNF tiene este formato:
##
##   <TextureAtlas imagePath="logoBumpin.png">
##     <SubTexture name="logo bumpin0000" x="0" y="0" width="894" height="670"
##                 frameX="-22" frameY="-16" frameWidth="939" frameHeight="703" />
##     ...
##   </TextureAtlas>
##
## Cada SubTexture dice que region del atlas usar (x, y, width, height) y
## donde colocarla dentro del frame completo (frameX, frameY, frameWidth,
## frameHeight). El frameX/frameY es el offset del recorte con respecto al
## origen del frame; puede ser negativo porque el recorte suele empezar
## ANTES del origen (los bordes transparentes que se recortaron estan a la
## izquierda o arriba del contenido visible).
##
## Este Control dibuja cada frame como: un TextureRect del tamano del
## frameWidth x frameHeight, con un AtlasTexture (region del atlas) que
## se coloca en position = (frameX, frameY).

const FRAME_DURATION := 0.07  ## ~15 fps, el bump clasico de FNF

var _frames: Array[Dictionary] = []  ## {region: Rect2, offset: Vector2, frame_size: Vector2}
var _frame_idx: int = 0
var _time: float = 0.0
var _rect: TextureRect  ## contenedor que se redimensiona por frame
var _sprite: TextureRect  ## el que tiene la AtlasTexture
## El atlas cargado. Se guarda aca y no se saca de _sprite.texture
## porque ese texture cambia en cada frame y la extraccion del atlas
## desde ahi es fragil.
var _atlas: Texture2D


func setup(atlas_png_path: String, atlas_xml_path: String) -> void:
	if not ResourceLoader.exists(atlas_png_path) or not ResourceLoader.exists(atlas_xml_path):
		push_warning("[AnimatedLogo] falta %s o %s" % [atlas_png_path, atlas_xml_path])
		return

	_atlas = load(atlas_png_path)
	_parse_xml(atlas_xml_path)
	if _frames.is_empty():
		return

	_rect = TextureRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(_rect)

	_sprite = TextureRect.new()
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP
	_rect.add_child(_sprite)

	# Aplicar el primer frame de una.
	var f = _frames[0]
	_rect.size = f["frame_size"]
	_rect.position = Vector2.ZERO
	_sprite.texture = _make_atlas_texture(_atlas, f["region"])
	_sprite.size = f["region"].size
	_sprite.position = f["offset"]


func _process(delta: float) -> void:
	if _frames.size() <= 1 or _rect == null:
		return
	_time += delta
	if _time < FRAME_DURATION:
		return
	_time -= FRAME_DURATION

	_frame_idx = (_frame_idx + 1) % _frames.size()
	var f = _frames[_frame_idx]
	var tex := _make_atlas_texture(_atlas, f["region"])
	if tex == null:
		return
	_sprite.texture = tex
	_sprite.size = f["region"].size
	_sprite.position = f["offset"]
	_rect.size = f["frame_size"]


func _make_atlas_texture(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	if atlas == null:
		return null
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	tex.region = region
	return tex


func _parse_xml(path: String) -> void:
	var xml := XMLParser.new()
	if xml.open(path) != OK:
		push_warning("[AnimatedLogo] no se pudo abrir %s" % path)
		return

	var frame_w: float = 0.0
	var frame_h: float = 0.0
	while xml.read() == OK:
		if xml.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if xml.get_node_name() != "SubTexture":
			continue

		var region := Rect2(
			float(xml.get_named_attribute_value_safe("x")),
			float(xml.get_named_attribute_value_safe("y")),
			float(xml.get_named_attribute_value_safe("width")),
			float(xml.get_named_attribute_value_safe("height")))

		# frameX/Y y frameWidth/Height son opcionales. Si no estan, el frame
		# completo ES la region.
		var fx := 0.0
		var fy := 0.0
		if xml.has_attribute("frameX"):
			fx = float(xml.get_named_attribute_value("frameX"))
		if xml.has_attribute("frameY"):
			fy = float(xml.get_named_attribute_value("frameY"))

		if xml.has_attribute("frameWidth"):
			frame_w = float(xml.get_named_attribute_value("frameWidth"))
			frame_h = float(xml.get_named_attribute_value("frameHeight"))
		else:
			frame_w = region.size.x
			frame_h = region.size.y

		_frames.append({
			"region": region,
			"offset": Vector2(fx, fy),
			"frame_size": Vector2(frame_w, frame_h),
		})
