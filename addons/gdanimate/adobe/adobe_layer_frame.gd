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
## Filtros aplicados a esta frame del layer (no al elemento).
## Hoy solo guardamos GlowFilter (GF). Estructura:
##   {color: String (con #), blur_x: float, blur_y: float,
##    strength: float, alpha: float, inner: bool, knockout: bool}
## Vacio = sin filtros.
@export_storage var glow: Dictionary = {}
