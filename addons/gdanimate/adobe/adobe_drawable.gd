@tool
@abstract
extends Resource
class_name AdobeDrawable


## Element.hx:19 (`public var visible:Bool`), inicializado en true en el ctor
## de AnimateElement (Element.hx:29). NO es lo mismo que AdobeLayer.hidden:
## esto es por ELEMENTO, y Frame.hx:423-426 lo chequea en el loop de dibujo:
##     for (element in elements)
##         if (element.visible)
##             element.draw(...);
## El motor lo usa internamente para el baking (Frame.hx:339 y
## MovieClipInstance.hx:173 apagan un bakedFrame) y queda expuesto para que
## un consumidor pueda ocultar un elemento suelto sin tocar el JSON.
@export_storage var visible: bool = true

var bounding_box: Rect2 = Rect2():
	get:
		if bounding_box == Rect2():
			calculate_bounding_box()

		return bounding_box


func draw_on(parent: RID, frame: int, previous_transform: Transform2D, symbols: Dictionary[StringName, AdobeSymbol], stack: Array[String], id: int) -> void :
	pass


func calculate_bounding_box() -> void :
	bounding_box = Rect2()
