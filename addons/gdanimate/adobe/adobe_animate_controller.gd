@tool
extends RefCounted
class_name AdobeAnimateController

## cne-flixel-animate/src/animate/FlxAnimateController.hx (414 lineas).
##
## Registro de animaciones nombradas + busqueda de frame labels. En el engine
## real extiende FlxAnimationController (core de Flixel) y ademas del registro
## maneja el playback con _curAnim, set_frameIndex override y una senal
## onFrameLabel que se dispara al cambiar de frame. Portear ese playback
## completo implicaria un sistema de animacion paralelo al que AnimateSymbol
## ya tiene (frame/speed_scale/playing/loop), con riesgo alto de conflictos.
##
## Este port cubre el REGISTRO y la BUSQUEDA (util para consumidores que
## quieren consultar "que frames tiene la animacion 'run'"), y delega el
## playback a AnimateSymbol: play() setea symbol + frame, el tween/autoplay
## interno del symbol hace el resto.
##
## Lo que NO esta portado (documentado en FIDELITY.md):
## - onFrameLabel signal que dispara en cada cambio de frame del timeline.
##   Requiere el override de set_frameIndex que el port no tiene.
## - set_frameIndex override con modulo sobre numFrames del _curAnim.
##   AnimateSymbol maneja frame directo sin wrap automatico por animacion.
## - updateTimelineBounds con el "fake FlxFrame" para width/height del sprite.

## Referencia al AnimateSymbol dueno. Se setea en el ctor.
var _sprite: AnimateSymbol

## Animaciones nombradas registradas. key=nombre, value=Dictionary con
## {name, indices, frame_rate, looped, flip_x, flip_y, timeline_symbol}.
## Estructura tipo "FlxAnimateAnimation" simplificada.
var _animations: Dictionary = {}

## Nombre de la animacion actualmente en reproduccion (o ""). El playback
## real lo maneja AnimateSymbol; esto es solo metadata para el consumidor.
var _current_anim: String = ""


func _init(sprite: AnimateSymbol) -> void:
	_sprite = sprite


## Registra una animacion a partir de los frames de un simbolo (todos sus
## frames en orden). Equivale a FlxAnimateController.hx:addBySymbol.
func add_by_symbol(anim_name: String, symbol_name: String, frame_rate: float = -1.0, looped: bool = true, flip_x: bool = false, flip_y: bool = false) -> void:
	var indices: PackedInt32Array = _all_indices_of_symbol(symbol_name)
	if indices.is_empty():
		push_warning("[AdobeAnimateController] add_by_symbol: symbol '%s' no encontrado o vacio" % symbol_name)
		return
	_register(anim_name, indices, frame_rate, looped, flip_x, flip_y, symbol_name)


## Registra una animacion a partir de indices especificos de un simbolo.
## Equivale a FlxAnimateController.hx:addBySymbolIndices.
func add_by_symbol_indices(anim_name: String, symbol_name: String, indices: PackedInt32Array, frame_rate: float = -1.0, looped: bool = true, flip_x: bool = false, flip_y: bool = false) -> void:
	_register(anim_name, indices, frame_rate, looped, flip_x, flip_y, symbol_name)


## Registra una animacion a partir de los frames que tienen cierto label
## (definido en Adobe Animate con la key "N"/"name" de un keyframe).
## Equivale a FlxAnimateController.hx:addByFrameLabel.
func add_by_frame_label(anim_name: String, label: String, frame_rate: float = -1.0, looped: bool = true, flip_x: bool = false, flip_y: bool = false, symbol_name: String = "") -> void:
	var indices: PackedInt32Array = find_frame_label_indices(label, symbol_name)
	if indices.is_empty():
		push_warning("[AdobeAnimateController] add_by_frame_label: label '%s' no encontrado" % label)
		return
	# FlxAnimateController.hx:79 `anim.timeline = usedTimeline`: la animacion
	# se queda con el timeline donde se encontro el label, para que play()
	# cambie a ese simbolo.
	_register(anim_name, indices, frame_rate, looped, flip_x, flip_y, symbol_name)


## Igual que add_by_frame_label pero tomando solo algunos indices de los que
## matchean el label. Equivale a FlxAnimateController.hx:addByFrameLabelIndices.
func add_by_frame_label_indices(anim_name: String, label: String, indices: PackedInt32Array, frame_rate: float = -1.0, looped: bool = true, flip_x: bool = false, flip_y: bool = false, symbol_name: String = "") -> void:
	var found: PackedInt32Array = find_frame_label_indices(label, symbol_name)
	if found.is_empty():
		push_warning("[AdobeAnimateController] add_by_frame_label_indices: label '%s' no encontrado" % label)
		return
	var usable: PackedInt32Array = PackedInt32Array()
	for i in indices:
		if i >= 0 and i < found.size():
			usable.append(found[i])
	if usable.is_empty():
		push_warning("[AdobeAnimateController] add_by_frame_label_indices: label '%s' + indices dan resultado vacio" % label)
		return
	_register(anim_name, usable, frame_rate, looped, flip_x, flip_y, symbol_name)


## Registra una animacion a partir de TODOS los frames del timeline del
## simbolo raiz actual. Equivale a addByTimeline.
func add_by_timeline(anim_name: String, frame_rate: float = -1.0, looped: bool = true, flip_x: bool = false, flip_y: bool = false) -> void:
	var length: int = _sprite.get_animation_length()
	if length <= 0:
		push_warning("[AdobeAnimateController] add_by_timeline: animation length 0")
		return
	var indices: PackedInt32Array = PackedInt32Array()
	for i in length:
		indices.append(i)
	_register(anim_name, indices, frame_rate, looped, flip_x, flip_y, "")


## Registra una animacion a partir de indices del timeline actual.
## Equivale a addByTimelineIndices.
func add_by_timeline_indices(anim_name: String, indices: PackedInt32Array, frame_rate: float = -1.0, looped: bool = true, flip_x: bool = false, flip_y: bool = false) -> void:
	_register(anim_name, indices, frame_rate, looped, flip_x, flip_y, "")


## cne-flixel-animate/src/animate/internal/Timeline.hx:145-171
## findFrameLabelIndices(): recorre las capas del timeline, encuentra keyframes
## con name == label, y devuelve TODOS los indices cubiertos por ese keyframe
## (frame.index .. frame.index + frame.duration - 1). Corta al primer layer
## que tenga el label (hasFoundLabel + break), para que un label duplicado en
## varias capas no sume indices repetidos.
## Indices de frame que cubre un label, port de
## Timeline.findFrameLabelIndices - maru dcaa33c
## src/animate/internal/Timeline.hx:
##
##     for (layer in layers)
##     {
##         for (frame in layer.frames)
##             if (frame.name.rtrim() == label)
##             {
##                 hasFoundLabel = true;
##                 for (i in 0...frame.duration) foundFrames.push(frame.index + i);
##             }
##         if (hasFoundLabel) break;
##     }
##
## `symbol_name` es el port del parametro opcional `?timeline` que tienen
## findFrameLabelIndices / addByFrameLabel / addByFrameLabelIndices en
## FlxAnimateController.hx:41, 95 y 189. Vacio = el timeline por default, que
## es `_animate.library.timeline` (FlxAnimateController.hx:getDefaultTimeline)
## = el simbolo raiz del Animation.json (FlxAnimateFrames.hx:425
## `frames.timeline = new Timeline(animData.AN.TL, frames, animData.AN.SN)`),
## o sea stage_symbol. El port no tenia ese parametro, asi que los labels
## que viven en un simbolo de la libreria y no en el raiz eran inalcanzables.
##
## El trim es rtrim sobre el NOMBRE del keyframe, no strip_edges sobre los
## dos, como hacia el port: un label con espacios adelante matchea en el port
## viejo y no en el motor.
func find_frame_label_indices(label: String, symbol_name: String = "") -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var atlas: AnimateAtlas = _sprite.get_atlas()
	if atlas == null or not (atlas is AdobeAtlas):
		return result

	var adobe: AdobeAtlas = atlas as AdobeAtlas
	var key: StringName = StringName(symbol_name) if not symbol_name.is_empty() else adobe.stage_symbol
	if key.is_empty() or not adobe.symbols.has(key):
		return result

	var target: AdobeSymbol = adobe.symbols[key]
	for layer: AdobeLayer in target.layers:
		var found_in_layer: bool = false
		for frame: AdobeLayerFrame in layer.frames:
			if frame.frame_label.rstrip(" \t\n\r") != label:
				continue

			found_in_layer = true
			for i in frame.duration:
				result.append(frame.starting_index + i)

		if found_in_layer:
			break

	return result


## Reproduce la animacion nombrada. En este port es un wrapper que delega a
## AnimateSymbol: setea el symbol del primer indice (o mantiene el actual) y
## el frame al primer indice registrado. El playback (avance de frame) lo
## sigue haciendo AnimateSymbol.speed_scale/playing/loop.
func play(anim_name: String) -> void:
	if not _animations.has(anim_name):
		push_warning("[AdobeAnimateController] play: animacion '%s' no registrada" % anim_name)
		return
	_current_anim = anim_name
	var anim: Dictionary = _animations[anim_name]
	var indices: PackedInt32Array = anim["indices"]
	if indices.is_empty():
		return
	if not anim["timeline_symbol"].is_empty():
		_sprite.symbol = anim["timeline_symbol"]
	_sprite.frame = indices[0]


## Nombre de la animacion actual (o "" si no hay ninguna en curso).
func get_current_anim() -> String:
	return _current_anim


## Lista de nombres de animaciones registradas.
func get_animation_names() -> Array[String]:
	var names: Array[String] = []
	for k: String in _animations.keys():
		names.append(k)
	return names


## Devuelve los indices de una animacion registrada, o array vacio.
func get_animation_indices(anim_name: String) -> PackedInt32Array:
	if not _animations.has(anim_name):
		return PackedInt32Array()
	return _animations[anim_name]["indices"]


func _all_indices_of_symbol(symbol_name: String) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var atlas: AnimateAtlas = _sprite.get_atlas()
	if atlas == null or not (atlas is AdobeAtlas):
		return result
	var adobe: AdobeAtlas = atlas as AdobeAtlas
	if not adobe.symbols.has(StringName(symbol_name)):
		return result
	var sym: AdobeSymbol = adobe.symbols[StringName(symbol_name)]
	for i in sym.length:
		result.append(i)
	return result


func _register(anim_name: String, indices: PackedInt32Array, frame_rate: float, looped: bool, flip_x: bool, flip_y: bool, timeline_symbol: String) -> void:
	_animations[anim_name] = {
		"name": anim_name,
		"indices": indices,
		"frame_rate": frame_rate,
		"looped": looped,
		"flip_x": flip_x,
		"flip_y": flip_y,
		"timeline_symbol": timeline_symbol,
	}
