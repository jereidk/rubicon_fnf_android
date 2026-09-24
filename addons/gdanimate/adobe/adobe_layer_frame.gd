@tool
extends Resource
class_name AdobeLayerFrame


@export_storage var starting_index: int = -1
@export_storage var duration: int = 0
@export_storage var elements: Array[AdobeDrawable] = []
## cne-flixel-animate/src/animate/internal/Frame.hx:216:
##     this.name = frame.N ?? "";
## Label del keyframe (JSON: "N" optimized, "name" legacy). Se usa en
## Timeline.hx:131 getFrameLabelAtIndex() / findFrameLabelIndices() para el
## controller de animaciones nombradas (Etapa 4). Vacio cuando el export no
## lo trae. NO uso "name" como identificador porque Resource ya expone .name
## en Godot 4 y hay riesgo de shadowing silencioso.
@export_storage var frame_label: String = ""
## Blend propio del KEYFRAME (no del elemento ni de la capa).
## FlxAnimateJson.hx:135-138 lo parsea (`this.B ?? this.blend`),
## Frame.hx:214 lo guarda (`this.blend = frame.B`) y Frame.draw lo resuelve
## contra el heredado antes de dibujar los elementos:
##     var blend = Blend.resolve(this.blend, blend);
## o sea que gana el del keyframe salvo que sea NORMAL. Lo escribe
## BetterTextureAtlas; Adobe Animate a secas no lo emite.
@export_storage var blend_mode: AdobeSymbolInstance.AdobeBlendMode = AdobeSymbolInstance.AdobeBlendMode.NORMAL
## Filtros aplicados a esta frame del layer (no al elemento).
## Hoy solo guardamos GlowFilter (GF). Estructura:
##   {color: String (con #), blur_x: float, blur_y: float,
##    strength: float, alpha: float, inner: bool, knockout: bool}
## Vacio = sin filtros.
##
## F13a: `glow` es ahora un DERIVADO de `filters` (primer GLOW). El shader
## inline de atlas_shader.gdshader sigue leyendo esto; cuando F13b porte el
## render-to-texture (bake real), `glow` se vuelve redundante pero se
## mantiene por compat con caches y consumidores.
@export_storage var glow: Dictionary = {}

## F13a: lista completa de filtros del keyframe. Port de FrameJson.F +
## FilterJson.resolve (FlxAnimateJson.hx:419-440). Tipos soportados:
## BLUR, ADJUST_COLOR, DROP_SHADOW, GLOW, BEVEL, GRADIENT_GLOW,
## GRADIENT_BEVEL. Aplicarlos es F13b (necesita render-to-texture).
@export_storage var filters: Array[AdobeFilter] = []

## F13-gap cluster A: estado de baking (maru Frame._requireBake/_dirty,
## Frame.hx:288-290). _require_bake se setea al parsear si hay filtros;
## _dirty lo prende set_dirty() y lo apaga el draw cuando re-pide el bake.
@export_storage var _require_bake: bool = false
@export_storage var _dirty: bool = false


## Port de Frame.setDirty (maru Frame.hx:94-112). En el source tambien
## propaga hacia arriba via layer.timeline.parent.setSymbolDirty(). Aca
## solo se prende el flag local; la propagacion la hace
## AdobeAtlas.set_symbol_dirty cuando el consumidor la pide.
func set_dirty() -> void:
	if _require_bake:
		_dirty = true

## F13-gap: port de Frame.forEachElement (maru Frame.hx:150-154).
func for_each_element(callback: Callable) -> void:
	for element: AdobeDrawable in elements:
		callback.call(element)


## F13-gap: port de Frame.convertToSymbol (maru Frame.hx:121-142).
## Saca los elementos en [from_index, to_index) de este keyframe, los
## empaqueta en un simbolo temporal (AdobeSymbol con 1 capa / 1 keyframe),
## y reemplaza el rango por una instancia de ese simbolo.
##
## En el source el Timeline temporal tiene parent = atlas, asi que el
## SymbolItem se registra en la libreria. Aca el atlas es opcional: si se
## pasa, se registra en `atlas.symbols`; si no, el simbolo queda huerfano
## (el consumidor se encarga).
##
## Devuelve la instancia creada, para chaining.
func convert_to_symbol(from_index: int, to_index: int, type: int, atlas: AdobeAtlas = null) -> AdobeSymbolInstance:
	var taken: Array[AdobeDrawable] = []
	for _i in (to_index - from_index):
		taken.append(elements[from_index])
		elements.remove_at(from_index)

	var temp_sym: AdobeSymbol = AdobeSymbol.new()
	temp_sym.name = &"tempSymbol"
	var temp_layer: AdobeLayer = AdobeLayer.new()
	temp_layer.name = &"Layer 0"
	var temp_frame: AdobeLayerFrame = AdobeLayerFrame.new()
	temp_frame.starting_index = 0
	temp_frame.duration = 1
	for el: AdobeDrawable in taken:
		temp_frame.elements.append(el)
	temp_layer.frames = [temp_frame]
	temp_layer.frame_indices = [0]
	temp_sym.layers = [temp_layer]
	temp_sym.length = 1
	temp_sym.rebuild_layer_map()

	if atlas != null:
		atlas.symbols[&"tempSymbol"] = temp_sym

	var instance: AdobeSymbolInstance = AdobeSymbolInstance.new()
	instance.key = &"tempSymbol"
	instance.transform = Transform2D.IDENTITY
	instance.type = type

	elements.insert(from_index, instance)
	return instance

