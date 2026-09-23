@tool
extends Resource
class_name AdobeLayer
## Port de Layer.hx (maru @ dcaa33c). Ver FIDELITY.md seccion F6.

## LayerType (Layer.hx:200-213):
##   NORMAL  - capa normal
##   CLIPPER - su forma define el recorte de las capas CLIPPED que la referencian
##   CLIPPED - su contenido se recorta contra un CLIPPER (campo Clpb)
##   FOLDER  - agrupador, NO parsea frames (Layer.hx:181-193)
enum LayerType { NORMAL, CLIPPER, CLIPPED, FOLDER }


@export_storage var name: StringName = &""
@export_storage var frames: Array[AdobeLayerFrame] = []

## Compat: caches viejos tienen `clipping: bool` en lugar de layer_type.
## load_layers setea AMBOS y _migrate_from_legacy() rellena layer_type desde
## el viejo `clipping` cuando carga un cache. Se conserva el campo para no
## perder la info vieja en el round-trip.
@export_storage var clipping: bool = false

## LayerType real (Layer.hx:32). Reemplaza la semantica binaria de `clipping`.
@export_storage var layer_type: LayerType = LayerType.NORMAL

## Nombre del clipper al que esta sujeta esta capa (Clpb).
@export_storage var clipped_by: String = ""

## Referencia directa al clipper (Layer.hx:150). Reemplaza el lookup por
## nombre en adobe_atlas.gd::frame_bounds.
@export_storage var parent_layer: AdobeLayer = null

## En el source es `visible = false` cuando: la capa es CLIPPER, o es CLIPPED
## sin clipper encontrado. Aca se invierte a `hidden` para que el default
## (false) sea "mostrar".
@export_storage var hidden: bool = false

## frame_indices (Layer.hx:34): mapa timeline_index -> keyframe_index.
@export_storage var frame_indices: Array[int] = []


var bounding_box: Rect2 = Rect2():
	get:
		if bounding_box == Rect2():
			calculate_bounding_box()
		return bounding_box


## Layer.hx:193-195.
func get_frame_count() -> int:
	return frame_indices.size()


## Port de Layer.getFrameAtIndex (Layer.hx:59-69): O(1) via frame_indices.
## Si `frame_indices` esta vacio (cache legacy) cae a un scan de frames por
## seguridad. `_migrate_from_legacy()` rellena el array al primer load.
func get_frame_at_index(index: int) -> AdobeLayerFrame:
	index = maxi(index, 0)
	var fc: int = get_frame_count()
	if fc > 0:
		if index > fc - 1:
			return null
		var fi: int = frame_indices[index]
		if fi < 0 or fi >= frames.size():
			return null
		return frames[fi]
	# Fallback legacy: scan.
	for layer_frame: AdobeLayerFrame in frames:
		if index < layer_frame.starting_index:
			continue
		if index > layer_frame.starting_index + layer_frame.duration - 1:
			continue
		return layer_frame
	return null


## Port de Layer.forEachFrame (Layer.hx:45-55).
func for_each_frame(callback: Callable) -> void:
	for frame: AdobeLayerFrame in frames:
		callback.call(frame)


## Layer.hx:186-188: rellena frame_indices desde frames. Se llama al cargar
## un cache que todavia no tiene el array (migracion).
func _fill_frame_indices_from_frames() -> void:
	frame_indices.clear()
	for i in frames.size():
		var f: AdobeLayerFrame = frames[i]
		for _j in f.duration:
			frame_indices.append(i)


## Migracion de cache legacy: caches viejos tienen `clipping: bool` pero no
## layer_type ni frame_indices. Se infiere desde `clipping` y se rellena el
## array. Idempotente: si ya esta todo, no toca nada.
func _migrate_from_legacy() -> void:
	if layer_type == LayerType.NORMAL and clipping:
		layer_type = LayerType.CLIPPER
	if frame_indices.is_empty() and not frames.is_empty():
		_fill_frame_indices_from_frames()


func calculate_bounding_box() -> void:
	# Fix F7 (fixup de F6): antes arrancaba de Rect2() vacio y mergeaba cada
	# elemento. `Rect2().merge(otro)` NO es `otro`, es "(0,0,0,0) union otro"
	# = Rect2(0, 0, ...). Esto metia el origen del atlas en el bbox de la
	# capa, que despues AdobeSymbol.merge() propagaba al bbox del simbolo,
	# que despues FlxAnimate.hx:224-225 usaba para matrix.translate(-x,-y)
	# -> sprite cortado/desplazado (bug raiz del trickyDJ).
	#
	# Ahora se usa el flag `first` como el source (Timeline.getBounds,
	# maru Timeline.hx:230-275) y se skipean frames vacios y elementos sin
	# area como el source:
	#   - `if (frame == null || frame.elements.length <= 0) continue;`
	#     (Timeline.hx:255)
	#   - `if (frameBounds.isEmpty) continue;`  (Timeline.hx:259)
	#   - Layer.hx:106, `if (!layer.visible && !includeHiddenLayers) continue;`
	if layer_type == LayerType.CLIPPER:
		return
	var rect: Rect2 = Rect2()
	var first: bool = true
	for frame: AdobeLayerFrame in frames:
		if frame.elements.is_empty():
			continue
		for element: AdobeDrawable in frame.elements:
			var eb: Rect2 = element.bounding_box
			if eb.size.x <= 0.0 or eb.size.y <= 0.0:
				continue
			if first:
				first = false
				rect = eb
			else:
				rect = rect.merge(eb)
	bounding_box = rect
