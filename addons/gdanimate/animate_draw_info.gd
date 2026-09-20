extends RefCounted
class_name AnimateDrawInfo


@export var symbol: String = ""
@export var frame: int = 0
@export var offset: Vector2 = Vector2.ZERO
@export var transform: Transform2D = Transform2D.IDENTITY
@export var material: Material = null
@export var additive_material: Material = null
@export var screen_transform: Transform2D = Transform2D.IDENTITY
@export var light_mask: int = 1
@export var visibility_layer: int = 1

## FlxAnimate: applyStageMatrix (FlxAnimate.hx:77, default false en el
## addon, pero Codename lo activa siempre en FunkinSprite.hx:97). Cuando
## es true, el AdobeAtlas aplica stage_transform al render aunque el
## symbol este presente en el diccionario. Antes el port solo aplicaba
## stage_transform cuando el symbol NO existia, lo que dejaba a los
## Animation.json del mod HQ (cuyos root symbols SI existen) sin su
## matriz de stage.
var apply_stage_matrix: bool = false

var items: Array[RID]

## The drawing symbol's own backbuffer cache, and whether it may be used.
##
## Both of these used to live on the AnimateAtlas, which is shared: one atlas
## resource serves every AnimateSymbol that names it. The cache holds the
## canvas item RIDs of whichever symbol rebuilt last, so any other symbol
## taking the cheap path was poking that symbol's RIDs with its own transform,
## and one symbol advancing a frame cleared the flag for all of them and sent
## the lot down the full rebuild path.
##
## They belong to the symbol, so they travel with the draw instead. Passed by
## reference exactly like items, so the atlas can fill the cache in place.
var backbuffer_cache: Array[Dictionary]
var use_backbuffer_cache: bool = false


func _init(_symbol: String, _frame: int, 
		_offset: Vector2, _transform: Transform2D, 
		_items: Array[RID] = []) -> void :
	symbol = _symbol
	frame = _frame
	offset = _offset
	transform = _transform
	items = _items
