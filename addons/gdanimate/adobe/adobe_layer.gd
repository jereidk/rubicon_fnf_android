@tool
extends Resource
class_name AdobeLayer


@export_storage var name: StringName = &""
@export_storage var frames: Array[AdobeLayerFrame] = []
@export_storage var clipping: bool = false
@export_storage var clipped_by: String = ""
## cne-flixel-animate/src/animate/internal/Layer.hx:141-164 (_loadJson): una capa
## con Clipped_by busca hacia arriba (indices menores) la primera capa con ese
## nombre que ademas sea tipo Clipper. Si no la encuentra, Flash oculta la capa
## por completo (visible = false) en vez de dejarla sin clip. adobe_atlas.gd
## resuelve esta busqueda en load_layers() y marca este flag; draw_symbol() la
## salta por completo cuando esta activo.
@export_storage var hidden: bool = false

var bounding_box: Rect2 = Rect2():
	get:
		if bounding_box == Rect2():
			calculate_bounding_box()

		return bounding_box


func calculate_bounding_box() -> void :
	if clipping:
		return

	var rect: Rect2 = Rect2()
	for frame: AdobeLayerFrame in frames:
		for element: AdobeDrawable in frame.elements:
			rect = rect.merge(element.bounding_box)

	bounding_box = rect
