@tool
extends Node
class_name AdobeRenderBaker


## F13b-i: infra de render-to-texture para filtros y F12b.
##
## Port conceptual de FilterRenderer.renderToBitmap
## (maru src/animate/internal/FilterRenderer.hx:257-285). El source:
##   1. Toma un FlxCamera del pool.
##   2. Llama draw_cb(cam, mat) que dibuja en el canvas de la camara.
##   3. renderGfx() lee el canvas a un BitmapData (gl.readPixels).
##   4. Devuelve el BitmapData.
##
## En Godot la version mas cercana es:
##   1. Un SubViewport persistente con transparent_bg.
##   2. El caller dibuja con canvas_item_* al canvas del viewport.
##   3. `await RenderingServer.frame_post_draw` para sincronizar.
##   4. `viewport.get_texture().get_image()` (readPixels) + ImageTexture.
##
## DIVERGENCIA ARQUITECTONICA: el source es SINCRONO (bake + usar en el mismo
## frame). Godot no lo permite. El port usa bake DEFERRED:
##   - El caller pide `request()` y sigue con lo que tenia cacheado.
##   - Este nodo hornea uno por frame en `_process()`.
##   - El resultado se ve 1 frame tarde. Imperceptible a 60fps.
##
## Serializado (1 SubViewport, 1 bake por frame): evita N viewports en
## memoria cuando hay muchas capas con filtros. Es lo que hace maru con
## `CamPool.get()` (1 camara del pool, no N).


## Señal que se emite cuando un bake termina. El caller puede reconectar
## para redibujar. Tambien se puede consultar `has_cached(key)` en `_process`.
signal bake_ready(key: String)


static var _instance: AdobeRenderBaker = null


var _viewport: SubViewport
var _cache: Dictionary = {}      # key -> ImageTexture
var _pending: Dictionary = {}    # key -> {size, draw}
var _is_baking: bool = false


## Devuelve el singleton. Lo crea si no existe (bajo root del SceneTree).
static func instance() -> AdobeRenderBaker:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	_instance = AdobeRenderBaker.new()
	_instance.name = "AdobeRenderBaker"
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).root.add_child(_instance)
	return _instance


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BakeViewport"
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)


## True si hay un bake cacheado para `key`.
func has_cached(key: String) -> bool:
	return _cache.has(key)


## Devuelve la textura cacheada, o null si no hay.
func get_cached(key: String) -> ImageTexture:
	return _cache.get(key) as ImageTexture


## Descarta el cache y los bakes pendientes de `key`. Llamar cuando cambian
## los filtros o el frame de la capa (equivalente al `_dirty = true` de
## Frame.setDirty en maru).
func invalidate(key: String) -> void:
	_cache.erase(key)
	_pending.erase(key)


## Pide un bake. Si ya hay uno pendiente con la misma key, lo reemplaza
## (el nuevo gana). `draw_cb` recibe `(canvas_rid: RID, size: Vector2)`.
##
## F13b-ii.3b: `filters` opcional. Si no esta vacio, DESPUES del bake
## crudo se aplica `apply_filters_to_texture` a la textura resultante.
## El cache que queda es la textura YA FILTRADA.
func request(key: String, size: Vector2i, draw_cb: Callable, filters: Array[AdobeFilter] = []) -> void:
	if size.x <= 0 or size.y <= 0:
		return
	_pending[key] = {
		"size": size,
		"draw": draw_cb,
		"filters": filters, 
	}


## F13b-ii: aplica la lista de filtros Adobe a una textura ya renderizada.
## Port conceptual de FilterRenderer.applyFilter
## (maru src/animate/internal/FilterRenderer.hx:400-500), pero en un solo
## pase via shader de canvas_item.
##
## Devuelve la textura filtrada como ImageTexture, o null si falla.
## El shader cubre BLUR, GLOW y ADJUST_COLOR. DROP_SHADOW y BEVEL quedan
## para F13b-ii.2 (necesitan un segundo pase con el contenido original
## para hacer el offset del shadow).
##
## `size` es el tamano de la textura fuente (se usa para el SubViewport
## intermedio).
func apply_filters_to_texture(src: ImageTexture, filters: Array[AdobeFilter], size: Vector2i) -> ImageTexture:
	if src == null or filters.is_empty() or size.x <= 0 or size.y <= 0:
		return src

	# Extraer los parametros del primer filtro de cada tipo. Por ahora
	# asumimos 1 filtro por tipo (los mods reales no los repiten).
	var blur_x: float = 0.0
	var blur_y: float = 0.0
	var glow_on: bool = false
	var glow_color: Color = Color.WHITE
	var glow_strength: float = 1.0
	var glow_inner: bool = false
	var glow_knockout: bool = false
	var adjust_on: bool = false
	var adjust_mult: Vector4 = Vector4.ONE
	var adjust_off: Vector4 = Vector4.ZERO
	var ds_on: bool = false
	var ds_color: Color = Color.BLACK
	var ds_offset: Vector2 = Vector2.ZERO
	var ds_blur: float = 0.0
	var ds_strength: float = 1.0
	var bevel_on: bool = false
	var bevel_highlight: Color = Color.WHITE
	var bevel_shadow: Color = Color.BLACK
	var bevel_offset: Vector2 = Vector2.ZERO
	var bevel_blur: float = 0.0
	var bevel_strength: float = 1.0

	for filter: AdobeFilter in filters:
		if filter == null:
			continue
		var d: Dictionary = filter.data
		match filter.type:
			AdobeFilter.AdobeFilterType.BLUR:
				blur_x = float(AdobeFilter._pick_or(d, "BLX", "blurX", 0.0))
				blur_y = float(AdobeFilter._pick_or(d, "BLY", "blurY", 0.0))
			AdobeFilter.AdobeFilterType.GLOW:
				glow_on = true
				glow_color = Color.from_string(
					String(AdobeFilter._pick_or(d, "C", "color", "#FFFFFF")), Color.WHITE)
				glow_strength = float(AdobeFilter._pick_or(d, "STR", "strength", 1.0)) / 100.0
				glow_inner = bool(AdobeFilter._pick_or(d, "IN", "inner", false))
				glow_knockout = bool(AdobeFilter._pick_or(d, "KK", "knockout", false))
				# El glow reusa el blur como radio.
				if blur_x <= 0.0:
					blur_x = float(AdobeFilter._pick_or(d, "BLX", "blurX", 6.0))
				if blur_y <= 0.0:
					blur_y = float(AdobeFilter._pick_or(d, "BLY", "blurY", 6.0))
			AdobeFilter.AdobeFilterType.ADJUST_COLOR:
				adjust_on = true
				var acf: AdobeColorMatrix = AdobeColorMatrix.adjust_from_params(
					float(AdobeFilter._pick_or(d, "BRT", "brightness", 0.0)), 
					float(AdobeFilter._pick_or(d, "H", "hue", 0.0)), 
					float(AdobeFilter._pick_or(d, "CT", "contrast", 0.0)), 
					float(AdobeFilter._pick_or(d, "SAT", "saturation", 0.0)), 
				)
				adjust_mult = Vector4(
					acf.color_multipliers[0].x, 
					acf.color_multipliers[1].y, 
					acf.color_multipliers[2].z, 
					acf.color_multipliers[3].w, 
				)
				adjust_off = acf.color_offsets
			AdobeFilter.AdobeFilterType.DROP_SHADOW:
				ds_on = true
				ds_color = Color.from_string(
					String(AdobeFilter._pick_or(d, "C", "color", "#000000")), Color.BLACK)
				ds_color.a = float(AdobeFilter._pick_or(d, "A", "alpha", 1.0))
				var dist: float = float(AdobeFilter._pick_or(d, "D", "distance", 0.0))
				var ang_deg: float = float(AdobeFilter._pick_or(d, "AL", "angle", 45.0))
				var ang: float = ang_deg * PI / 180.0
				ds_offset = Vector2(dist * cos(ang), dist * sin(ang))
				ds_blur = float(AdobeFilter._pick_or(d, "BLX", "blurX", 0.0))
				ds_strength = float(AdobeFilter._pick_or(d, "STR", "strength", 1.0)) / 100.0
			AdobeFilter.AdobeFilterType.BEVEL:
				bevel_on = true
				bevel_highlight = Color.from_string(
					String(AdobeFilter._pick_or(d, "HC", "highlightColor", "#FFFFFF")), Color.WHITE)
				bevel_highlight.a = float(AdobeFilter._pick_or(d, "HA", "highlightAlpha", 1.0))
				bevel_shadow = Color.from_string(
					String(AdobeFilter._pick_or(d, "SC", "shadowColor", "#000000")), Color.BLACK)
				bevel_shadow.a = float(AdobeFilter._pick_or(d, "SA", "shadowAlpha", 1.0))
				var dist: float = float(AdobeFilter._pick_or(d, "D", "distance", 5.0))
				var ang_deg: float = float(AdobeFilter._pick_or(d, "AL", "angle", 45.0))
				var ang: float = ang_deg * PI / 180.0
				bevel_offset = Vector2(dist * cos(ang), dist * sin(ang))
				bevel_blur = float(AdobeFilter._pick_or(d, "BLX", "blurX", 4.0))
				bevel_strength = float(AdobeFilter._pick_or(d, "STR", "strength", 1.0)) / 100.0
			_:
				pass

	# Construir el shader material.
	var shader: Shader = load("res://addons/gdanimate/filter_shader.gdshader")
	if shader == null:
		return src

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	# blur_uv: radio en UV-space (independiente del pixel_size del viewport).
	mat.set_shader_parameter(&"blur_uv", Vector2(blur_x / float(size.x), blur_y / float(size.y)))
	mat.set_shader_parameter(&"blur_x", blur_x)
	mat.set_shader_parameter(&"blur_y", blur_y)
	mat.set_shader_parameter(&"glow_enabled", 1 if glow_on else 0)
	mat.set_shader_parameter(&"glow_color", glow_color)
	mat.set_shader_parameter(&"glow_strength", glow_strength)
	mat.set_shader_parameter(&"glow_inner", 1 if glow_inner else 0)
	mat.set_shader_parameter(&"glow_knockout", 1 if glow_knockout else 0)
	mat.set_shader_parameter(&"adjust_enabled", 1 if adjust_on else 0)
	mat.set_shader_parameter(&"adjust_mult", adjust_mult)
	mat.set_shader_parameter(&"adjust_offset", adjust_off)
	mat.set_shader_parameter(&"ds_enabled", 1 if ds_on else 0)
	mat.set_shader_parameter(&"ds_color", ds_color)
	mat.set_shader_parameter(&"ds_offset_uv", Vector2(ds_offset.x / float(size.x), ds_offset.y / float(size.y)))
	mat.set_shader_parameter(&"ds_blur_uv", ds_blur / float(maxf(size.x, size.y)))
	mat.set_shader_parameter(&"ds_strength", ds_strength)
	mat.set_shader_parameter(&"bevel_enabled", 1 if bevel_on else 0)
	mat.set_shader_parameter(&"bevel_highlight", bevel_highlight)
	mat.set_shader_parameter(&"bevel_shadow", bevel_shadow)
	mat.set_shader_parameter(&"bevel_offset_uv", Vector2(bevel_offset.x / float(size.x), bevel_offset.y / float(size.y)))
	mat.set_shader_parameter(&"bevel_blur_uv", bevel_blur / float(maxf(size.x, size.y)))
	mat.set_shader_parameter(&"bevel_strength", bevel_strength)

	# Render-to-texture con el shader aplicado. Uso un SubViewport temporal
	# (no el _viewport del baker, que esta en uso serializado) para no
	# romper la garantia "1 bake por frame".
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	# TextureRect (no ColorRect): el shader lee la textura fuente en
	# TEXTURE. Un ColorRect dibuja un rect plano y el shader no tendria
	# nada que filtrar.
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.texture = src
	tex_rect.size = Vector2(size)
	tex_rect.material = mat
	viewport.add_child(tex_rect)

	# Async: esperar al render y leer la textura.
	await RenderingServer.frame_post_draw
	var result: Image = viewport.get_texture().get_image()
	viewport.queue_free()

	if result == null:
		return src
	return ImageTexture.create_from_image(result)


func _process(_delta: float) -> void:
	if _is_baking or _pending.is_empty():
		return
	_is_baking = true
	var key: String = String(_pending.keys()[0])
	var req: Dictionary = _pending[key]
	_pending.erase(key)
	_do_bake(key, req["size"], req["draw"], req.get("filters", []))
	_is_baking = false


func _do_bake(key: String, size: Vector2i, draw_cb: Callable, filters: Array[AdobeFilter]) -> void:
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var node: Node2D = Node2D.new()
	node.name = "BakeTarget"
	_viewport.add_child(node)

	# El caller dibuja con canvas_item_* contra este RID.
	draw_cb.call(node.get_canvas_item(), Vector2(size))

	# Sincronizar con el render real.
	await RenderingServer.frame_post_draw

	# Copiar a ImageTexture (mismo readPixels que maru con gl.readPixels).
	var img: Image = _viewport.get_texture().get_image()
	var tex: ImageTexture = ImageTexture.create_from_image(img)

	_viewport.remove_child(node)
	node.queue_free()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	# F13b-ii.3b: aplicar filtros si los hay. El cache que queda es la
	# textura ya filtrada (equivalente a FilterRenderer.applyFilter de
	# maru que devuelve el BitmapData final).
	if not filters.is_empty():
		var filtered: ImageTexture = await apply_filters_to_texture(tex, filters, size)
		if filtered != null:
			tex = filtered

	_cache[key] = tex

	bake_ready.emit(key)
