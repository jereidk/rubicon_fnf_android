@tool
extends AdobeDrawable
class_name AdobeAtlasSprite


@export_storage var region: Rect2i
@export_storage var rotated: bool
@export_storage var texture: Texture2D
@export_storage var transform: Transform2D

## Frame original, para que replace_frame(null) pueda volver atras. Equivale
## a AtlasInstance.sourceFrame (AtlasInstance.hx:34), que el ctor setea junto
## con frame (AtlasInstance.hx:45-46).
##
## NO es @export_storage: se captura perezosamente la primera vez que se
## llama a replace_frame(), leyendo los valores que todavia son los
## originales. Asi tampoco cambia el formato del .res cacheado.
var _source_texture: Texture2D = null
var _source_region: Rect2i = Rect2i()
var _source_rotated: bool = false
var _source_captured: bool = false

var _tile_matrix: Transform2D = Transform2D.IDENTITY
var _tile_matrix_built: bool = false

## Port de FlxFrame.prepareBlitMatrix(mat, blit = false) - flixel 6.2.0,
## flixel/graphics/frames/FlxFrame.hx:184-204 - que es lo que AtlasInstance
## cachea en su ctor (AtlasInstance.hx:58 `this.frame.prepareBlitMatrix(
## tileMatrix, false)`) y despues aplica primero de todo en draw()
## (AtlasInstance.hx:101-103):
##     _mat.copyFrom(tileMatrix);
##     _mat.concat(matrix);
##     _mat.concat(parentMatrix);
##
## Con blit = false el translate(-frame.x, -frame.y) no va, asi que queda
## solo la rotacion del sprite dentro del spritemap (Adobe marca "rotated" y
## FlxAnimateFrames.hx:409 lo mapea a ANGLE_NEG_90) mas el offset del frame,
## que para estos atlas siempre es (0, 0).
##
## Antes esto se armaba inline en draw_atlas_sprite() y en
## calculate_bounding_box(); tenerlo como una sola Transform2D es lo que hace
## el source y ademas es lo que replace_frame necesita para poder escribirle
## la escala encima.
##
## Va sin @export_storage a proposito: se deriva de region/rotated, asi que
## un .res cacheado de antes de este cambio lo reconstruye igual en vez de
## deserializar una identidad y perder la rotacion.
var tile_matrix: Transform2D:
	get:
		if not _tile_matrix_built:
			_tile_matrix = _build_tile_matrix()
			_tile_matrix_built = true
		return _tile_matrix
	set(value):
		_tile_matrix = value
		_tile_matrix_built = true


func _build_tile_matrix() -> Transform2D:
	if not rotated:
		return Transform2D.IDENTITY

	# ANGLE_NEG_90: rotateByNegative90() + translate(0, frame.width).
	return Transform2D(
		- PI / 2.0, 
		Vector2(0.0, region.size.x)
	)


## Port de AtlasInstance.replaceFrame - AtlasInstance.hx:70-86.
##
##     var copyFrame = (frame ?? this.sourceFrame).copyTo();
##     if (adjustScale)
##     {
##         tileMatrix.a = sourceFrame.frame.width / copyFrame.frame.width;
##         tileMatrix.d = sourceFrame.frame.height / copyFrame.frame.height;
##     }
##     this.frame = copyFrame;
##     if (this.parentFrame != null) this.parentFrame.setDirty();
##
## `frame` null vuelve al frame original. Con adjust_scale, el frame nuevo se
## reescala para ocupar exactamente lo mismo que ocupaba el viejo.
##
## Igual que el source, la escala se escribe DIRECTO sobre la a y la d de la
## tile matrix. Para un sprite rotado esa matriz tiene a = 0 y d = 0 (es una
## rotacion de 90 grados), asi que pisarlas da un shear y no una escala - el
## propio source lo marca con un "TODO: account for frame rotations"
## (AtlasInstance.hx:74). Se replica tal cual en vez de "arreglarlo", que es
## el punto de este port.
##
## Lo que NO se puede portear aca: el `parentFrame.setDirty()` final. Un
## AdobeAtlasSprite no tiene referencia a su keyframe ni al nodo (eso es
## Frame.parentFrame, F5). Despues de llamar a esto hay que marcar el
## AnimateSymbol a mano:
##     nodo.frame_dirty = true
##     nodo.queue_redraw()
func replace_frame(frame: AdobeAtlasSprite = null, adjust_scale: bool = true) -> void :
	if not _source_captured:
		_source_texture = texture
		_source_region = region
		_source_rotated = rotated
		_source_captured = true

	var new_texture: Texture2D = _source_texture
	var new_region: Rect2i = _source_region
	var new_rotated: bool = _source_rotated
	if frame != null:
		new_texture = frame.texture
		new_region = frame.region
		new_rotated = frame.rotated

	if adjust_scale and new_region.size.x != 0 and new_region.size.y != 0:
		var scaled: Transform2D = tile_matrix
		scaled.x.x = float(_source_region.size.x) / float(new_region.size.x)
		scaled.y.y = float(_source_region.size.y) / float(new_region.size.y)
		tile_matrix = scaled

	texture = new_texture
	region = new_region
	rotated = new_rotated

	# La bounding box esta cacheada en AdobeDrawable y ahora quedo vieja.
	bounding_box = Rect2()


func calculate_bounding_box() -> void :
	# getBounds, AtlasInstance.hx:168-180: el rect arranca en (0, 0, ancho,
	# alto) del frame y se le aplican la tile matrix y despues la matriz del
	# elemento. Componerlas en una sola Transform2D da lo mismo que el source
	# -que las aplica de a una, re-encajonando en el medio- porque la tile
	# matrix es una rotacion de 90 grados exactos (o identidad) y esas
	# preservan el eje: el AABB intermedio no pierde nada.
	bounding_box = (transform * tile_matrix) * Rect2(Vector2.ZERO, Vector2(region.size))
