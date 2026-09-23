extends RefCounted

## F9 - FlxAnimate.drawAnimate (maru dcaa33c src/animate/FlxAnimate.hx:194-196).
##
## El shift automatico al top-left del bbox del timeline:
##     var bounds = timeline._bounds;
##     matrix.translate(-bounds.x, -bounds.y);
##
## Se aplica SIEMPRE (no condicionado a applyStageMatrix). Antes el port no
## lo aplicaba en absoluto y todo sprite quedaba desplazado por
## bounds.position - la otra mitad del bug raiz del trickyDJ.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const NORMAL := AdobeLayer.LayerType.NORMAL


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_bounds_offset_from_bbox(failures)
	_test_bounds_offset_zero(failures)
	_test_bounds_offset_missing(failures)
	_test_bounds_offset_shortcut(failures)

	return {
		"name": "bounds_offset: origin-shift automatico (FlxAnimate.hx:194-196)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _make_sprite(x: float, y: float, w: float, h: float) -> AdobeAtlasSprite:
	var s: AdobeAtlasSprite = AdobeAtlasSprite.new()
	s.region = Rect2i(0, 0, int(w), int(h))
	s.transform = Transform2D(0.0, Vector2(x, y))
	s.bounding_box = Rect2()
	return s


func _make_atlas_with_symbol(sym_name: StringName, bbox_origin: Vector2) -> AdobeAtlas:
	var atlas: AdobeAtlas = AdobeAtlas.new()

	var layer: AdobeLayer = AdobeLayer.new()
	layer.name = &"L"
	layer.layer_type = NORMAL

	var frame: AdobeLayerFrame = AdobeLayerFrame.new()
	frame.starting_index = 0
	frame.duration = 1
	frame.elements = [_make_sprite(bbox_origin.x, bbox_origin.y, 50.0, 50.0)]
	layer.frames = [frame]
	layer._fill_frame_indices_from_frames()

	var sym: AdobeSymbol = AdobeSymbol.new()
	sym.layers = [layer]
	atlas.symbols[sym_name] = sym

	return atlas


## bbox (100, 200) -> bounds_offset (-100, -200).
func _test_bounds_offset_from_bbox(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = _make_atlas_with_symbol(&"walk", Vector2(100.0, 200.0))
	var off: Vector2 = atlas.compute_bounds_offset(&"walk")
	if off != Vector2(-100.0, -200.0):
		failures.push_back("from_bbox: %s != (-100, -200)" % off)


## bbox (0, 0) -> bounds_offset (0, 0). No-op.
func _test_bounds_offset_zero(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = _make_atlas_with_symbol(&"walk", Vector2.ZERO)
	var off: Vector2 = atlas.compute_bounds_offset(&"walk")
	if off != Vector2.ZERO:
		failures.push_back("zero: %s != (0, 0)" % off)


## symbol inexistente -> Vector2.ZERO (no crashea).
func _test_bounds_offset_missing(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = _make_atlas_with_symbol(&"walk", Vector2(50.0, 50.0))
	var off: Vector2 = atlas.compute_bounds_offset(&"missing")
	if off != Vector2.ZERO:
		failures.push_back("missing: %s != (0, 0)" % off)


## shortcut de carpeta (F8): "Folder/walk" resuelve a "walk" y devuelve el
## bbox de "walk".
func _test_bounds_offset_shortcut(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = _make_atlas_with_symbol(&"walk", Vector2(10.0, 20.0))
	var off: Vector2 = atlas.compute_bounds_offset(&"Folder/walk")
	if off != Vector2(-10.0, -20.0):
		failures.push_back("shortcut: %s != (-10, -20)" % off)
