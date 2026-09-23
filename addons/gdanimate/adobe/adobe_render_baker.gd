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
func request(key: String, size: Vector2i, draw_cb: Callable) -> void:
	if size.x <= 0 or size.y <= 0:
		return
	_pending[key] = {
		"size": size,
		"draw": draw_cb,
	}


func _process(_delta: float) -> void:
	if _is_baking or _pending.is_empty():
		return
	_is_baking = true
	var key: String = String(_pending.keys()[0])
	var req: Dictionary = _pending[key]
	_pending.erase(key)
	_do_bake(key, req["size"], req["draw"])
	_is_baking = false


func _do_bake(key: String, size: Vector2i, draw_cb: Callable) -> void:
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
	_cache[key] = tex

	_viewport.remove_child(node)
	node.queue_free()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	bake_ready.emit(key)
