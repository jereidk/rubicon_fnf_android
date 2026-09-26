extends RefCounted

## F7 - Timeline.hx (476) + SymbolItem.hx (95) de MaybeMaru/flixel-animate@dcaa33c.
##
## Divergencias cubiertas:
##   - AdobeLayer.calculate_bounding_box metia (0, 0) al bbox por empezar
##     de Rect2() VACIO (fixup F6 -> F7). Fix: flag `first` + skip frames
##     vacios + skip elementos sin area.
##   - AdobeSymbol.calculate_bounding_box tenia el mismo bug propagado.
##   - AdobeSymbol no tenia get_layer / for_each_layer / get_frames_at_index
##     / get_elements_at_index / get_frame_label_at_index / rebuild_layer_map
##     (port de Timeline.getLayer y amigos).
##   - AdobeAtlas no tenia whole_symbol_bounds (getWholeBounds) ni
##     symbol_bounds_origin (getBoundsOrigin).

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const NORMAL := AdobeLayer.LayerType.NORMAL


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_layer_bbox_no_origin_leak(failures)
	_test_symbol_bbox_no_origin_leak(failures)
	_test_symbol_bbox_with_empty_frame(failures)
	_test_get_layer_by_name_and_index(failures)
	_test_for_each_layer(failures)
	_test_get_frames_and_elements_at_index(failures)
	_test_get_frame_label_at_index(failures)
	_test_whole_symbol_bounds(failures)
	_test_symbol_bounds_origin(failures)

	return {
		"name": "symbol: bbox sin leak de (0,0) + getLayer + getWholeBounds",
		"passed": failures.is_empty(),
		"failures": failures,
	}


## Sprite con bbox conocida. El bbox de AdobeAtlasSprite es
## (transform * tile_matrix) * Rect2(0, 0, region.size).
func _make_sprite(x: float, y: float, w: float, h: float) -> AdobeAtlasSprite:
	var s: AdobeAtlasSprite = AdobeAtlasSprite.new()
	s.region = Rect2i(0, 0, int(w), int(h))
	s.transform = Transform2D(0.0, Vector2(x, y))
	s.bounding_box = Rect2()  # forzar recalculo
	return s


## Bug raiz del trickyDJ: `Rect2().merge(bbox_lejano)` = "(0,0,0,0) union
## bbox_lejano" = Rect2(0, 0, ...). El fix usa flag `first`.
func _test_layer_bbox_no_origin_leak(failures: Array[String]) -> void:
	var layer: AdobeLayer = AdobeLayer.new()
	layer.layer_type = NORMAL

	var frame: AdobeLayerFrame = AdobeLayerFrame.new()
	frame.starting_index = 0
	frame.duration = 1
	frame.elements = [_make_sprite(100.0, 200.0, 50.0, 50.0)]
	layer.frames = [frame]
	layer.bounding_box = Rect2()

	var bb: Rect2 = layer.bounding_box
	var expected: Rect2 = Rect2(100.0, 200.0, 50.0, 50.0)
	if bb != expected:
		failures.push_back("layer_bbox: %s != %s (bug merge Rect2())" % [bb, expected])


func _test_symbol_bbox_no_origin_leak(failures: Array[String]) -> void:
	var layer: AdobeLayer = AdobeLayer.new()
	layer.layer_type = NORMAL
	var frame: AdobeLayerFrame = AdobeLayerFrame.new()
	frame.starting_index = 0
	frame.duration = 1
	frame.elements = [_make_sprite(100.0, 200.0, 50.0, 50.0)]
	layer.frames = [frame]

	var sym: AdobeSymbol = AdobeSymbol.new()
	sym.layers = [layer]
	sym.bounding_box = Rect2()

	var bb: Rect2 = sym.bounding_box
	var expected: Rect2 = Rect2(100.0, 200.0, 50.0, 50.0)
	if bb != expected:
		failures.push_back("symbol_bbox: %s != %s" % [bb, expected])


## Timeline.hx:255: `if (frame == null || frame.elements.length <= 0) continue;`
func _test_symbol_bbox_with_empty_frame(failures: Array[String]) -> void:
	var layer: AdobeLayer = AdobeLayer.new()
	layer.layer_type = NORMAL

	var f0: AdobeLayerFrame = AdobeLayerFrame.new()
	f0.starting_index = 0
	f0.duration = 1
	f0.elements = [_make_sprite(100.0, 200.0, 50.0, 50.0)]

	var f1: AdobeLayerFrame = AdobeLayerFrame.new()
	f1.starting_index = 1
	f1.duration = 1
	f1.elements = []  # keyframe vacio

	layer.frames = [f0, f1]
	layer.bounding_box = Rect2()

	var bb: Rect2 = layer.bounding_box
	var expected: Rect2 = Rect2(100.0, 200.0, 50.0, 50.0)
	if bb != expected:
		failures.push_back("empty_frame: %s != %s" % [bb, expected])


## Timeline.getLayer (maru Timeline.hx:48-51).
func _test_get_layer_by_name_and_index(failures: Array[String]) -> void:
	var sym: AdobeSymbol = AdobeSymbol.new()
	var a: AdobeLayer = AdobeLayer.new()
	a.name = &"A"
	var b: AdobeLayer = AdobeLayer.new()
	b.name = &"B"
	sym.layers = [a, b]
	sym.rebuild_layer_map()

	if sym.get_layer("A") != a:
		failures.push_back("get_layer(\"A\") != A")
	if sym.get_layer("B") != b:
		failures.push_back("get_layer(\"B\") != B")
	if sym.get_layer(0) != a:
		failures.push_back("get_layer(0) != A")
	if sym.get_layer(1) != b:
		failures.push_back("get_layer(1) != B")
	if sym.get_layer(2) != null:
		failures.push_back("get_layer(2) deberia ser null")
	if sym.get_layer("Z") != null:
		failures.push_back("get_layer(\"Z\") deberia ser null")


func _test_for_each_layer(failures: Array[String]) -> void:
	var sym: AdobeSymbol = AdobeSymbol.new()
	var a: AdobeLayer = AdobeLayer.new()
	a.name = &"A"
	var b: AdobeLayer = AdobeLayer.new()
	b.name = &"B"
	sym.layers = [a, b]

	var seen: Array[AdobeLayer] = []
	sym.for_each_layer(func(l: AdobeLayer) -> void: seen.append(l))

	if seen.size() != 2:
		failures.push_back("for_each_layer: %d, esperaba 2" % seen.size())
	elif seen[0] != a or seen[1] != b:
		failures.push_back("for_each_layer: orden incorrecto")


## Timeline.getFramesAtIndex / getElementsAtIndex.
##
## Semantica real del source (confirmada con test_layer.gd F6 y
## Layer.getFrameAtIndex): `layer.frame_indices` es un array DENSO desde 0,
## un slot por frame de duracion de cada keyframe, SIN respetar huecos por
## `frame.starting_index`. `getFrameAtIndex(i)` indexa dentro de ese array
## (i-ésimo frame local de la capa), no en el timeline global.
## Un keyframe con `I=2, DU=1` produce frame_indices=[0], y getFrameAtIndex(0)
## devuelve ese keyframe aunque su starting_index=2.
func _test_get_frames_and_elements_at_index(failures: Array[String]) -> void:
	var sym: AdobeSymbol = AdobeSymbol.new()

	# Layer A: 3 keyframes-equivalentes (DU=3), frame_indices=[0, 0, 0].
	var la: AdobeLayer = AdobeLayer.new()
	la.name = &"A"
	var fa: AdobeLayerFrame = AdobeLayerFrame.new()
	fa.starting_index = 0
	fa.duration = 3
	fa.elements = [_make_sprite(0.0, 0.0, 10.0, 10.0)]
	la.frames = [fa]
	la._fill_frame_indices_from_frames()

	# Layer B: 1 keyframe (DU=1), frame_indices=[0].
	var lb: AdobeLayer = AdobeLayer.new()
	lb.name = &"B"
	var fb: AdobeLayerFrame = AdobeLayerFrame.new()
	fb.starting_index = 0
	fb.duration = 1
	fb.elements = [_make_sprite(20.0, 20.0, 5.0, 5.0)]
	lb.frames = [fb]
	lb._fill_frame_indices_from_frames()

	sym.layers = [la, lb]

	# Index 0: ambos layers tienen frame_indices[0] -> [fa, fb].
	var f0: Array[AdobeLayerFrame] = sym.get_frames_at_index(0)
	if f0.size() != 2:
		failures.push_back("get_frames_at_index(0): %d, esperaba 2 ([fa, fb])" % f0.size())
	elif f0[0] != fa or f0[1] != fb:
		failures.push_back("get_frames_at_index(0): orden incorrecto")

	# Index 2: Layer A tiene frame_indices[2]=0; Layer B con fc=1 -> null.
	var f2: Array[AdobeLayerFrame] = sym.get_frames_at_index(2)
	if f2.size() != 1:
		failures.push_back("get_frames_at_index(2): %d, esperaba 1 ([fa])" % f2.size())
	elif f2[0] != fa:
		failures.push_back("get_frames_at_index(2)[0] != fa")

	var e0: Array[AdobeDrawable] = sym.get_elements_at_index(0)
	if e0.size() != 2:
		failures.push_back("get_elements_at_index(0): %d, esperaba 2" % e0.size())

	var e2: Array[AdobeDrawable] = sym.get_elements_at_index(2)
	if e2.size() != 1:
		failures.push_back("get_elements_at_index(2): %d, esperaba 1" % e2.size())


## Timeline.getFrameLabelAtIndex.
func _test_get_frame_label_at_index(failures: Array[String]) -> void:
	var sym: AdobeSymbol = AdobeSymbol.new()
	var la: AdobeLayer = AdobeLayer.new()
	la.name = &"A"
	var fa: AdobeLayerFrame = AdobeLayerFrame.new()
	fa.starting_index = 0
	fa.duration = 1
	fa.frame_label = ""
	la.frames = [fa]
	la._fill_frame_indices_from_frames()

	var lb: AdobeLayer = AdobeLayer.new()
	lb.name = &"B"
	var fb: AdobeLayerFrame = AdobeLayerFrame.new()
	fb.starting_index = 0
	fb.duration = 1
	fb.frame_label = "walk"
	lb.frames = [fb]
	lb._fill_frame_indices_from_frames()

	sym.layers = [la, lb]

	if sym.get_frame_label_at_index(0) != "walk":
		failures.push_back("get_frame_label_at_index(0): '%s' != 'walk'" % sym.get_frame_label_at_index(0))
	if sym.get_frame_label_at_index(5) != "":
		failures.push_back("get_frame_label_at_index(5): deberia ser ''")


## Port de Timeline.getWholeBounds.
func _test_whole_symbol_bounds(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var sym: AdobeSymbol = AdobeSymbol.new()
	sym.name = &"Test"

	var layer: AdobeLayer = AdobeLayer.new()
	layer.name = &"L"
	layer.layer_type = NORMAL

	var f0: AdobeLayerFrame = AdobeLayerFrame.new()
	f0.starting_index = 0
	f0.duration = 1
	f0.elements = [_make_sprite(10.0, 10.0, 20.0, 20.0)]

	var f1: AdobeLayerFrame = AdobeLayerFrame.new()
	f1.starting_index = 1
	f1.duration = 1
	f1.elements = [_make_sprite(100.0, 100.0, 30.0, 30.0)]

	layer.frames = [f0, f1]
	layer._fill_frame_indices_from_frames()
	sym.layers = [layer]
	sym.length = 2

	var bounds: Rect2 = atlas.whole_symbol_bounds(sym)
	# frame 0: (10, 10, 20, 20); frame 1: (100, 100, 30, 30)
	# union: (10, 10, 120, 120)
	var expected: Rect2 = Rect2(10.0, 10.0, 120.0, 120.0)
	if bounds != expected:
		failures.push_back("whole_bounds: %s != %s" % [bounds, expected])


## Port de Timeline.getBoundsOrigin.
func _test_symbol_bounds_origin(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var sym: AdobeSymbol = AdobeSymbol.new()
	sym.name = &"Test"

	var layer: AdobeLayer = AdobeLayer.new()
	layer.name = &"L"
	layer.layer_type = NORMAL

	var f: AdobeLayerFrame = AdobeLayerFrame.new()
	f.starting_index = 0
	f.duration = 1
	f.elements = [_make_sprite(50.0, 60.0, 10.0, 10.0)]
	layer.frames = [f]
	layer._fill_frame_indices_from_frames()
	sym.layers = [layer]
	sym.length = 1

	var origin: Vector2 = atlas.symbol_bounds_origin(sym)
	if origin != Vector2(50.0, 60.0):
		failures.push_back("bounds_origin: %s != (50, 60)" % origin)
