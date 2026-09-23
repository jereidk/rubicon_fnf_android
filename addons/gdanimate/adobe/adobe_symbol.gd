@tool
extends Resource
class_name AdobeSymbol


@export_storage var layers: Array[AdobeLayer] = []
@export_storage var length: int = 0
## F7: nombre del simbolo (SymbolItem.name en maru, seteado por el atlas).
## Ej "anim_idle", "Symbol 3". El lookup por nombre en get_layer usa esto.
@export_storage var name: StringName = &""

## F7: mapa nombre->capa para get_layer(String). Se reconstruye con
## rebuild_layer_map() cada vez que `layers` cambia (parse, migracion).
var _layer_map: Dictionary = {}

var bounding_box: Rect2 = Rect2():
	get:
		if bounding_box == Rect2():
			calculate_bounding_box()

		return bounding_box


## F7. Port de Timeline.getLayer - maru Timeline.hx:48-51.
## `name is String ? _layerMap.get(name) : layers[name]`. El port acepta
## ambos: String/StringName va por mapa, int por indice directo.
func get_layer(ref: Variant) -> AdobeLayer:
	if ref is String or ref is StringName:
		return _layer_map.get(String(ref))
	if ref is int:
		var i: int = ref
		if i >= 0 and i < layers.size():
			return layers[i]
	return null


## F7. Port de Timeline.forEachLayer - maru Timeline.hx:60-66.
func for_each_layer(callback: Callable) -> void:
	for layer: AdobeLayer in layers:
		callback.call(layer)


## F7. Port de Timeline.getFramesAtIndex - maru Timeline.hx:75-90.
func get_frames_at_index(index: int) -> Array[AdobeLayerFrame]:
	var out: Array[AdobeLayerFrame] = []
	for layer: AdobeLayer in layers:
		var f: AdobeLayerFrame = layer.get_frame_at_index(index)
		if f != null:
			out.append(f)
	return out


## F7. Port de Timeline.getElementsAtIndex - maru Timeline.hx:92-108.
func get_elements_at_index(index: int) -> Array[AdobeDrawable]:
	var out: Array[AdobeDrawable] = []
	for layer: AdobeLayer in layers:
		var f: AdobeLayerFrame = layer.get_frame_at_index(index)
		if f == null:
			continue
		for element: AdobeDrawable in f.elements:
			out.append(element)
	return out


## F7. Port de Timeline.getFrameLabelAtIndex - maru Timeline.hx:120-133.
## Devuelve el primer label no vacio entre todas las capas en ese indice.
func get_frame_label_at_index(index: int) -> String:
	for layer: AdobeLayer in layers:
		var f: AdobeLayerFrame = layer.get_frame_at_index(index)
		if f != null and not f.frame_label.is_empty():
			return f.frame_label
	return ""


## F7: reconstruye _layer_map desde `layers`. Llamar cada vez que `layers`
## cambia (parse de atlas, migracion de caches legacy).
func rebuild_layer_map() -> void:
	_layer_map.clear()
	for layer: AdobeLayer in layers:
		_layer_map[String(layer.name)] = layer


## F7. Port de Timeline.expandBounds - maru Timeline.hx:391-401.
## Godot: Rect2.merge hace exactamente esto (min de las esquinas, max de
## right/bottom).
static func expand_bounds(base: Rect2, expanded: Rect2) -> Rect2:
	return base.merge(expanded)


## F7. Port de Timeline.maskBounds - maru Timeline.hx:406-424.
## Si el masker esta vacio devuelve el masked sin tocar. Si no se solapan,
## devuelve un rect vacio en (0, 0).
static func mask_bounds(masked: Rect2, masker: Rect2) -> Rect2:
	if masker.size.x <= 0.0 or masker.size.y <= 0.0:
		return masked
	var x1: float = maxf(masked.position.x, masker.position.x)
	var y1: float = maxf(masked.position.y, masker.position.y)
	var x2: float = minf(masked.end.x, masker.end.x)
	var y2: float = minf(masked.end.y, masker.end.y)
	if x2 <= x1 or y2 <= y1:
		return Rect2()
	return Rect2(x1, y1, x2 - x1, y2 - y1)


## F7. Port de Timeline.applyMatrixToRect - maru Timeline.hx:426-477.
## Godot: `Transform2D * Rect2` calcula el AABB de las 4 esquinas
## transformadas, mismo algoritmo que el source. El caso de rect vacio de
## maru (`return rect.set(m.tx, m.ty, 0, 0)`) tambien: `t * Rect2()` en
## Godot devuelve `Rect2(t.origin, Vector2.ZERO)`.
static func apply_matrix_to_rect(rect: Rect2, m: Transform2D) -> Rect2:
	return m * rect


## Migracion completa de layers de un cache legacy. Llamada desde
## adobe_atlas.gd::parse() cuando se carga desde cache.
##
## Dos pasos:
##   1. Por capa: inferir layer_type desde `clipping` y rellenar
##      frame_indices desde las duraciones de los keyframes.
##   2. Por capa CLIPPED sin parent_layer: resolver la referencia al clipper
##      entre las hermanas. Esto no lo puede hacer AdobeLayer solo porque
##      necesita ver el array completo.
func migrate_all_layers_from_legacy() -> void:
	for layer: AdobeLayer in layers:
		layer._migrate_from_legacy()

	# Segundo paso: parent_layer para CLIPPED sin ref (caches viejos tienen
	# clipped_by string pero no parent_layer, porque la referencia directa
	# se agrego en F6).
	for layer: AdobeLayer in layers:
		if layer.layer_type != AdobeLayer.LayerType.CLIPPED:
			continue
		if layer.parent_layer != null:
			continue
		if layer.clipped_by.is_empty():
			continue
		for other: AdobeLayer in layers:
			if other.name == layer.clipped_by and other.layer_type == AdobeLayer.LayerType.CLIPPER:
				layer.parent_layer = other
				break

	# F7: reconstruir el mapa nombre->capa despues de migrar.
	rebuild_layer_map()


func calculate_bounding_box() -> void :
	# Fix F7 (mismo bug que AdobeLayer.calculate_bounding_box): antes
	# arrancaba de Rect2() vacio y mergeaba capa por capa. `Rect2().merge()`
	# mete el origen del atlas. Ahora usa flag `first` como maru
	# Timeline.getBounds (Timeline.hx:230-275).
	#
	# El source calcula esto frame-por-frame (getWholeBounds, Timeline.hx:
	# 194-220) y aplica clipping. Este calculo sigue siendo "por capa": la
	# diferencia es observable solo con clipping frame-level (un layer
	# CLIPPED cuya mascara existe en unos frames y no en otros). Anotado
	# como TODO para F8, junto con el cache _cachedBounds.
	#
	# Skip CLIPPER por tipo (Layer.hx:106, no-visible) y CLIPPED sin
	# parent_layer (marcadas hidden=true en load_layers).
	var rect: Rect2 = Rect2()
	var first: bool = true
	for layer: AdobeLayer in layers:
		if layer.layer_type == AdobeLayer.LayerType.CLIPPER:
			continue
		if layer.hidden:
			continue

		var lb: Rect2 = layer.bounding_box
		if lb.size.x <= 0.0 or lb.size.y <= 0.0:
			continue

		if first:
			first = false
			rect = lb
		else:
			rect = rect.merge(lb)

	bounding_box = rect
