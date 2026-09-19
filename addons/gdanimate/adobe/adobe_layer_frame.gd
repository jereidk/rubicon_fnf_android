@tool
extends Resource
class_name AdobeLayerFrame


@export_storage var starting_index: int = -1
@export_storage var duration: int = 0
@export_storage var elements: Array[AdobeDrawable] = []
## Filtros aplicados a esta frame del layer (no al elemento).
## Hoy solo guardamos GlowFilter (GF). Estructura:
##   {color: String (con #), blur_x: float, blur_y: float,
##    strength: float, alpha: float, inner: bool, knockout: bool}
## Vacio = sin filtros.
@export_storage var glow: Dictionary = {}
