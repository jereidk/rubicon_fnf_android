@tool
extends Resource
class_name AdobeSymbol


@export_storage var layers: Array[AdobeLayer] = []
@export_storage var length: int = 0

var bounding_box: Rect2 = Rect2():
	get:
		if bounding_box == Rect2():
			calculate_bounding_box()

		return bounding_box


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


func calculate_bounding_box() -> void :
	# F6: ademas de CLIPPER, el source skipea las capas no-visibles
	# (Layer.hx:106, `if (!layer.visible && !includeHiddenLayers) continue`).
	# En el port eso son CLIPPER (siempre invisible: su forma solo es
	# recorte) y CLIPPED sin parent_layer (visible = false en el source).
	var rect: Rect2 = Rect2()
	for layer: AdobeLayer in layers:
		if layer.layer_type == AdobeLayer.LayerType.CLIPPER:
			continue
		if layer.hidden:
			continue

		rect = rect.merge(layer.bounding_box)

	bounding_box = rect
