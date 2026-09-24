@tool
extends AdobeDrawable
class_name AdobeSymbolInstance


enum AdobeSymbolType{
	GRAPHIC = 0,
	MOVIE_CLIP,
	## cne-flixel-animate/.../ButtonInstance.hx:1-9: ButtonInstance extends
	## SymbolInstance. Se detecta en el JSON cuando ST == "B"/"button".
	## ButtonInstance.hx:33 hace this.elementType = BUTTON en el ctor.
	BUTTON

}

## cne-flixel-animate/src/animate/internal/elements/SymbolInstance.hx:269-273
## (LoopType) — el motor real solo tiene estos tres modos. No existe
## reverse: cualquier LP no reconocido cae en LOOP (ver SymbolInstance.hx:49-54).
enum AdobeSymbolLoopMode{
	LOOP = 0,
	ONE_SHOT,
	FREEZE_FRAME,
}

enum AdobeBlendMode{
	ADD = 0, 
	ALPHA = 1, 
	DARKEN = 2, 
	DIFFERENCE = 3, 
	ERASE = 4, 
	HARD_LIGHT = 5, 
	INVERT = 6, 
	LAYER = 7, 
	LIGHTEN = 8, 
	MULTIPLY = 9, 
	NORMAL = 10, 
	OVERLAY = 11, 
	SCREEN = 12, 
	SHADER = 13, 
	SUBTRACT = 14, 
}


@export_storage var key: StringName
@export_storage var type: AdobeSymbolType
@export_storage var loop_mode: AdobeSymbolLoopMode = AdobeSymbolLoopMode.LOOP
@export_storage var transform: Transform2D
@export_storage var first_frame: int
## Adobe's per-instance "last frame" (LF in an optimized Animation.json). A graphic symbol
## instance can be told to stop or wrap EARLY, before the end of the symbol it points at,
## and Animate writes that bound per instance rather than per symbol.
##
## -1 means the JSON left it out, which is the symbol's own last frame. It matters: an
## atlas can pack several poses into one symbol and give each user a two-frame window of
## it, and without this bound a play-once instance runs off its window and into the next
## pose. Animania's tadano does exactly that - one `facessing` symbol holds four sing
## directions and each direction is FF/LF two frames apart.
@export_storage var last_frame: int = -1
@export_storage var filters: Array[AdobeFilter] = []

## F13-gap cluster A: estado de baking, espejo de MovieClipInstance.hx:
## 27-32 (_dirty, _requireBake, _filters). El port solo usa los dos flags
## para exponer la API; el bake real lo maneja AdobeRenderBaker.
@export_storage var _require_bake: bool = false
@export_storage var _dirty: bool = false
@export_storage var blend_mode: AdobeBlendMode = AdobeBlendMode.NORMAL
@export_storage var color_matrix: AdobeColorMatrix = null


func calculate_bounding_box() -> void :
	pass

## F13-gap: port de SymbolInstance.get_symbolName (maru SymbolInstance.hx:
## 246-249):
##     inline function get_symbolName():String { return libraryItem?.name; }
## En el port el equivalente del `libraryItem.name` es `key` (el nombre con
## el que se busca el simbolo en `atlas.symbols`).
func symbol_name() -> String:
	return String(key)

## Port de MovieClipInstance.setDirty (maru MovieClipInstance.hx:98-110).
## En el source tambien propaga al parentFrame.setDirty(). Aca solo el flag.
func set_dirty() -> void:
	if _require_bake:
		_dirty = true


## Port de MovieClipInstance.setFilters (maru MovieClipInstance.hx:89-93):
##     this._filters = filters;
##     this._requireBake = (filters != null && filters.length > 0);
##     setDirty();
func set_filters(new_filters: Array[AdobeFilter]) -> void:
	filters = new_filters
	_require_bake = not new_filters.is_empty()
	set_dirty()


## Port de SymbolInstance.isSimpleSymbol (maru SymbolInstance.hx:146-159):
##     if (timeline.frameCount == 1) return true;
##     if (loopType == SINGLE_FRAME) return true;
##     return false;
## El port recibe `symbol_length` (frameCount) por parametro porque la
## instancia no tiene referencia directa al AdobeSymbol.
func is_simple_symbol(symbol_length: int) -> bool:
	if symbol_length == 1:
		return true
	if loop_mode == AdobeSymbolLoopMode.FREEZE_FRAME:
		return true
	return false

