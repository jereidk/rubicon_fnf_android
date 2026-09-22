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
@export_storage var glow: Dictionary = {}
