extends Resource

class_name SparrowFrame


@export var name: StringName = &""
@export var region: Rect2i = Rect2i()
@export var offset: Rect2i = Rect2i()
@export var rotated: bool = false
## cne-flixel/flixel/graphics/frames/FlxAtlasFrames.hx:263-264 (fromSparrow):
##     var flipX = (texture.has.flipX && texture.att.flipX == "true");
##     var flipY = (texture.has.flipY && texture.att.flipY == "true");
## Se bakean en el FlxFrame; el motor real los XOR-ea con el flip del sprite
## al dibujar (FlxFrame.hx:290-291 prepareMatrix). El port no tiene flip a
## nivel de sprite, asi que se aplican directo como espejado del rect de draw.
@export var flip_x: bool = false
@export var flip_y: bool = false
