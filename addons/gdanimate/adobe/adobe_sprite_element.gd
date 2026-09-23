@tool
extends AdobeDrawable
class_name AdobeSpriteElement


## F13b-iii: port de FlxSpriteElement.hx (maru dcaa33c, 206 lineas).
##
## Envuelve un `Node2D` (equivalente al FlxSprite de maru) para que
## participe de una timeline de Adobe Animate con transform/blend/color
## sincronizados.
##
## El source hace todo SINCRONO: modifica el FlxSprite in-place, llama
## `basic.draw()` (que va a la camara activa), y restaura. Godot no
## permite dibujo sincrono de un nodo arbitrario a un canvas ajeno, pero
## SI permite mover el nodo a un SubViewport, esperar un frame, y leer la
## textura resultante via `get_texture().get_image()`.
##
## Mecanismo (opcion B de la investigacion del source de Godot):
##   1. `_request_bake` mueve el target al SubViewport del baker via
##      `remove_child` + `add_child`. Godot dispara automaticamente
##      NOTIFICATION_EXIT_CANVAS + ENTER_CANVAS y reparenta el RID.
##   2. Baker espera `frame_post_draw`, lee la textura, la cachea.
##   3. Baker devuelve el target al padre original.
##
## DIVERGENCIA: 2 frames de latencia + el target no se dibuja en su lugar
## normal durante el bake. Para un "sprite envuelto para una timeline de
## Animate" eso es correcto: el target ES del element, no del scene tree.
##
## Caveats documentados:
## - `target.get_viewport()` devuelve el SubViewport durante el bake.
##   Si el target tiene `_process` o `_gui_input`, se disparan con el
##   viewport equivocado. Recomendado: el target no debe depender de
##   `get_viewport()` ni tener logica de input propia.
## - El target debe estar FUERA del scene tree principal cuando se
##   asigna al element. El element lo mueve durante el bake y lo devuelve
##   a `_original_parent` (que puede ser null).


## Nodo a dibujar. Equivalente a `basic:T` de FlxTypedElement.
## Puede estar sin padre (recomendado) o con padre. El element lo mueve
## temporalmente durante el bake y lo devuelve a donde estaba.
##
## Tipo CanvasItem (no Node2D) porque Control y Node2D son ambos
## CanvasItem y el source de maru acepta cualquier FlxBasic. El unico
## requerimiento es que tenga un canvas_item RID, que es lo que
## CanvasItem expone.
@export_storage var target: CanvasItem = null

## Transform del element dentro de la timeline. Equivalente a `matrix` de
## AtlasInstance: se compone como `parent_t * transform * target_local`.
@export_storage var transform: Transform2D = Transform2D.IDENTITY

## Blend mode propio del element (SymbolInstance.hx:213 en maru lo aplica
## via Blend.resolve sobre el `basic.blend`).
@export_storage var blend_mode: AdobeSymbolInstance.AdobeBlendMode = AdobeSymbolInstance.AdobeBlendMode.NORMAL

## Color matrix propia del element. Se concatena con la heredada.
@export_storage var color_matrix: AdobeColorMatrix = null

## Padre original del target (capturado al primer bake). Se usa para
## devolverlo a su lugar. NO va a @export_storage: es runtime state.
var _original_parent: Node = null
var _original_parent_captured: bool = false


## Bbox del element. Compone `transform` con el rect del target (que se
## calcula a partir del tamaño del target si es Control, o via
## `get_rect()` si esta disponible).
func calculate_bounding_box() -> void:
	if target == null or not is_instance_valid(target):
		bounding_box = Rect2()
		return

	var target_rect: Rect2 = _get_target_rect()
	bounding_box = transform * target_rect


func _get_target_rect() -> Rect2:
	if target == null:
		return Rect2()
	if target is Control:
		var c: Control = target as Control
		return Rect2(Vector2.ZERO, c.size)
	# Node2D u otro CanvasItem: no tiene tamaño propio. Si expone
	# `get_rect()` se usa; si no, fallback a 1x1 (el consumidor puede
	# overridear calculate_bounding_box()).
	if target.has_method("get_rect"):
		var r: Variant = target.call("get_rect")
		if r is Rect2:
			return r
	return Rect2(Vector2.ZERO, Vector2.ONE)


## Captura el padre original del target. Idempotente.
func capture_original_parent() -> void:
	if _original_parent_captured:
		return
	if target != null and is_instance_valid(target):
		_original_parent = target.get_parent()
	_original_parent_captured = true


## Devuelve el target a su padre original. Se llama desde el baker tras el
## bake.
func restore_target_parent() -> void:
	if target == null or not is_instance_valid(target):
		return
	var cur_parent: Node = target.get_parent()
	if cur_parent == _original_parent:
		return
	if cur_parent != null:
		cur_parent.remove_child(target)
	if _original_parent != null and is_instance_valid(_original_parent):
		_original_parent.add_child(target)


func draw_on(_parent: RID, _frame: int, _previous_transform: Transform2D,
		_symbols: Dictionary[StringName, AdobeSymbol], _stack: Array[String], _id: int) -> void:
	# El dibujo del element se hace desde AdobeAtlas::draw_symbol, no desde
	# aca. Este metodo existe solo para cumplir el contrato abstracto.
	pass
