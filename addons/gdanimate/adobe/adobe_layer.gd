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

## F13-gap: port de Layer.setBlankKeyframe (maru Layer.hx:85-99).
##
##     var lastFrame = getFrameAtIndex(index);
##     var startIndex = lastFrame.index;
##     var startDuration = lastFrame.duration;
##     var keyframe = new Frame(this);
##     keyframe.index = index;
##     keyframe.duration = startDuration - (index - startIndex);
##     frames.insert(frames.indexOf(lastFrame) + 1, keyframe);
##     for (i in 0...keyframe.duration)
##         frameIndices[index + i] = frames.length - 1;
##
## Inserta un keyframe VACIO en `index`. Si `index` ya es el inicio de un
## keyframe, el source no hace nada (getFrameAtIndex(index).index == index
## -> return, ver setKeyframe). Aca no chequeamos eso porque el llamador
## decide; el metodo siempre inserta.
func set_blank_keyframe(index: int) -> void:
	var last: AdobeLayerFrame = get_frame_at_index(index)
	if last == null:
		return
	var start_index: int = last.starting_index
	var start_duration: int = last.duration
	if start_index == index:
		return

	var keyframe: AdobeLayerFrame = AdobeLayerFrame.new()
	keyframe.starting_index = index
	keyframe.duration = start_duration - (index - start_index)
	if keyframe.duration <= 0:
		return

	var at: int = frames.find(last)
	frames.insert(at + 1, keyframe)

	# Reindexar frame_indices: los slots [index, index+duration) apuntan al
	# keyframe nuevo.
	var new_fi: int = frames.size() - 1
	for i in keyframe.duration:
		var slot: int = index + i
		if slot < frame_indices.size():
			frame_indices[slot] = new_fi


## F13-gap: port de Layer.setKeyframe (maru Layer.hx:67-78).
##
##     var lastFrame = getFrameAtIndex(index);
##     if (lastFrame == null || lastFrame.index == index) return;
##     setBlankKeyframe(index);
##     var keyframe = getFrameAtIndex(index);
##     keyframe.elements = lastFrame.elements.copy();
##     keyframe.name = lastFrame.name;
##
## Crea un keyframe con COPIA de los elementos del keyframe que lo contiene
## en `index`. Si `index` ya es el inicio de un keyframe, no hace nada.
func set_keyframe(index: int) -> void:
	var last: AdobeLayerFrame = get_frame_at_index(index)
	if last == null or last.starting_index == index:
		return

	set_blank_keyframe(index)
	var kf: AdobeLayerFrame = get_frame_at_index(index)
	if kf == null or kf == last:
		return

	# Copia superficial de elementos (mismo comportamiento que `.copy()`
	# del source: son referencias, no clones).
	kf.elements = last.elements.duplicate()
	kf.frame_label = last.frame_label

