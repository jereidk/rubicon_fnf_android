@tool
extends AdobeDrawable
class_name AdobeSymbolInstance


enum AdobeSymbolType{
	GRAPHIC = 0, 
	MOVIE_CLIP

}

enum AdobeSymbolLoopMode{
	LOOP = 0, 
	ONE_SHOT, 
	FREEZE_FRAME, 
	REVERSE_ONE_SHOT, 
	REVERSE_LOOP
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
@export_storage var blend_mode: AdobeBlendMode = AdobeBlendMode.NORMAL
@export_storage var color_matrix: AdobeColorMatrix = null


func calculate_bounding_box() -> void :
	pass
