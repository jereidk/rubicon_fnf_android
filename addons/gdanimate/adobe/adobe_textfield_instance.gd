@tool
extends AdobeDrawable
class_name AdobeTextFieldInstance

## Port de TextFieldInstance.hx (maru dcaa33c, 124 lineas).
##
## Un keyframe puede contener un `TFI` que renderiza texto. En el source
## hereda de AtlasInstance (no de SymbolInstance) porque no es un contenedor
## de sub-simbolo: es un sprite con una textura generada dinamicamente a
## partir del texto + atributos del JSON.
##
## El source crea un openfl.text.TextField, lo configura con un TextFormat,
## mide textWidth/textHeight, y lo hornea a un BitmapData. El resultado se
## trata como un FlxFrame normal, con frame rect (0, 0, W, H) y matrix propia.
##
## En Godot NO se hornea a textura. Godot tiene TextLine, que dibuja directo
## al canvas RID del layer en el mismo pipeline que el resto de los elementos
## - entonces glow/blend/canvas group siguen aplicando igual sin necesidad
## de un SubViewport ni de forzar un render sincrono.
##
## Divergencias conocidas vs el source:
##   - letterSpacing (CSP): Godot no lo soporta en TextLine.add_string. Skip.
##   - bold (BL) / italic (IT): requieren variantes de la fuente; el source
##     las aplica via TextFormat. En Godot se pierden. Anotado para F13+
##     (cargar la variante bold/italic si esta disponible).
##   - BRD / ALSRP / ALTHK: el source las lee pero NO las aplica (el
##     `format.borderSize = data.ALTHK` esta comentado). Fiel: no se aplican.
##   - maxCharacters (MAX) / orientation (ORT) / lineType (LT): el source no
##     las usa en render. Fiel: no se aplican.

## Matrix propia del texto en el timeline. Port de TextFieldInstance.hx:41
## (`this.matrix = data.MX.toMatrix()`). El bbox se calcula como
## `transform * Rect2(0, 0, W, H)`, igual que AtlasInstance.getBounds.
@export_storage var transform: Transform2D = Transform2D.IDENTITY

## Texto a mostrar. Port de TextFieldInstance.text setter: si cambia, marca
## _dirty para reconstruir la TextLine.
@export_storage var text: String = "":
	set(value):
		if text != value:
			text = value
			_dirty = true

## Atributos del primer elemento de `ATR` (el source solo usa ATR[0], ver
## TextFieldInstance.hx:52). Se guardan ya resueltos del JSON.
@export_storage var font_path: String = ""
@export_storage var font_size: int = 12
@export_storage var text_color: Color = Color.WHITE
@export_storage var align: int = 0  # 0=left, 1=center, 2=right, 3=justify

## Scratch state. NO van a @export_storage (se recrean en el primer draw).
var _dirty: bool = true
var _text_line: TextLine = null
var _font: Font = null


func _get_font() -> Font:
	if _font != null:
		return _font
	if not font_path.is_empty():
		var res: Resource = null
		if ResourceLoader.exists(font_path):
			res = load(font_path)
		if res is Font:
			_font = res
			return _font
	# Fallback: fuente default del tema. El source usa el sistema operativo
	# (openfl.text.TextFormat.font con un nombre pelado). Godot no tiene
	# acceso a fuentes del sistema desde un shader/canvas - el consumidor
	# tiene que proveer font_path si quiere el tipo exacto.
	_font = ThemeDB.fallback_font
	return _font


## Construye la TextLine si hace falta. Idempotente. Port del lazy redraw
## de TextFieldInstance.redraw() + el chequeo de _dirty en draw().
func ensure_built() -> void:
	if not _dirty and _text_line != null:
		return

	_text_line = TextLine.new()
	if not text.is_empty():
		var font: Font = _get_font()
		_text_line.add_string(text, font, font_size)

	_dirty = false
	# La bounding box cacheada en AdobeDrawable ahora quedo vieja.
	bounding_box = Rect2()


## Tamano del texto como (W, H). Equivalente a textWidth/textHeight del
## source (TextFieldInstance.hx:85-86).
func get_text_size() -> Vector2:
	ensure_built()
	if _text_line == null:
		return Vector2.ZERO
	return _text_line.get_size()


## Port del bounds heredado de AtlasInstance: transform * Rect2(0, 0, W, H).
func calculate_bounding_box() -> void:
	var size: Vector2 = get_text_size()
	bounding_box = transform * Rect2(Vector2.ZERO, size)


## Draw directo al canvas RID del layer. Port de TextFieldInstance.draw ->
## AtlasInstance.draw (TextFieldInstance.hx:110-121 + AtlasInstance.hx:95-110):
##     _mat.copyFrom(tileMatrix); _mat.concat(matrix); _mat.concat(parentMatrix);
## El textfield no tiene tileMatrix (no viene de spritemap), asi que la
## transform es `parent * matrix` en convencion Godot.
##
## El offset por alineacion es manual: TextLine no maneja alineacion
## horizontal por si sola, hay que desplazar el origen. El source lo resuelve
## via TextFormat.align + textWidth del TextField; el resultado final es el
## mismo: el texto alineado dentro de su propio bbox.
func draw_to_canvas(parent: RID, previous_transform: Transform2D) -> void:
	ensure_built()
	if _text_line == null or text.is_empty():
		return

	var t: Transform2D = previous_transform * transform
	RenderingServer.canvas_item_add_set_transform(parent, t)

	var offset: Vector2 = Vector2.ZERO
	match align:
		1:  # center
			offset.x = -_text_line.get_size().x * 0.5
		2:  # right
			offset.x = -_text_line.get_size().x
		_:  # left / justify (justify cae a left como el source)
			offset.x = 0.0

	_text_line.draw(parent, offset, text_color)


func draw_on(_parent: RID, _frame: int, _previous_transform: Transform2D,
		_symbols: Dictionary[StringName, AdobeSymbol], _stack: Array[String], _id: int) -> void:
	# El dibujo del textfield se hace desde AdobeAtlas::draw_textfield, no
	# desde aca: necesita previous_transform y no la firma completa de
	# draw_on. Este metodo existe solo para cumplir el contrato abstracto.
	pass
