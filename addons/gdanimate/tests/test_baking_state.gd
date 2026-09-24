extends RefCounted

## F13-gap cluster A: sistema de baking (estado + invalidacion).
## Port de Frame.setDirty / MovieClipInstance.setDirty / setFilters /
## SymbolInstance.isSimpleSymbol / FlxAnimateFrames.setSymbolDirty.
##
## El bake real lo maneja AdobeRenderBaker (deferred). Estos tests cubren
## la API de estado que expone el port.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const NORMAL := AdobeLayer.LayerType.NORMAL


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_frame_set_dirty_requires_bake(failures)
	_test_frame_set_dirty_no_bake_noop(failures)
	_test_instance_set_filters(failures)
	_test_instance_is_simple_symbol(failures)
	_test_set_symbol_dirty_walks_tree(failures)

	return {
		"name": "baking_state: setDirty + setFilters + isSimpleSymbol (cluster A)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


## Frame.setDirty prende _dirty solo si _require_bake.
func _test_frame_set_dirty_requires_bake(failures: Array[String]) -> void:
	var f: AdobeLayerFrame = AdobeLayerFrame.new()
	f._require_bake = true
	f._dirty = false
	f.set_dirty()
	if not f._dirty:
		failures.push_back("frame_dirty: set_dirty con _require_bake=true no prendio _dirty")


## Frame.setDirty NO prende _dirty si _require_bake es false.
func _test_frame_set_dirty_no_bake_noop(failures: Array[String]) -> void:
	var f: AdobeLayerFrame = AdobeLayerFrame.new()
	f._require_bake = false
	f._dirty = false
	f.set_dirty()
	if f._dirty:
		failures.push_back("frame_dirty_noop: set_dirty sin _require_bake prendio _dirty")


## MovieClipInstance.setFilters: marca _require_bake + _dirty segun la lista.
func _test_instance_set_filters(failures: Array[String]) -> void:
	var inst: AdobeSymbolInstance = AdobeSymbolInstance.new()

	# Con filtros: _require_bake = true.
	var filters: Array[AdobeFilter] = AdobeFilter.parse_list([
		{"N": "BLF", "BLX": 4.0, "BLY": 4.0}
	])
	inst.set_filters(filters)
	if not inst._require_bake:
		failures.push_back("set_filters: con filtros no prendio _require_bake")
	if not inst._dirty:
		failures.push_back("set_filters: con filtros no prendio _dirty")

	# Sin filtros: _require_bake = false, _dirty no se prende.
	inst.set_filters([])
	if inst._require_bake:
		failures.push_back("set_filters: sin filtros quedo _require_bake=true")


## SymbolInstance.isSimpleSymbol: timeline con 1 frame -> true.
func _test_instance_is_simple_symbol(failures: Array[String]) -> void:
	var inst: AdobeSymbolInstance = AdobeSymbolInstance.new()

	# frameCount == 1 -> simple.
	inst.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.LOOP
	if not inst.is_simple_symbol(1):
		failures.push_back("simple: frameCount=1 no devolvio true")

	# frameCount > 1 + LOOP -> no simple.
	if inst.is_simple_symbol(5):
		failures.push_back("simple: frameCount=5 con LOOP devolvio true")

	# frameCount > 1 + FREEZE_FRAME -> simple.
	inst.loop_mode = AdobeSymbolInstance.AdobeSymbolLoopMode.FREEZE_FRAME
	if not inst.is_simple_symbol(5):
		failures.push_back("simple: frameCount=5 con FREEZE_FRAME no devolvio true")


## AdobeAtlas.set_symbol_dirty recorre el arbol de simbolos y prende _dirty
## en los frames que requieren bake y contienen una instancia del symbol
## target.
func _test_set_symbol_dirty_walks_tree(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	# Symbol hoja "Sub" que sera el target.
	var sub_sym: AdobeSymbol = AdobeSymbol.new()
	sub_sym.name = &"Sub"

	# Symbol raiz "Root" con una capa que contiene una instancia de "Sub" y
	# el keyframe tiene filtros (por lo tanto _require_bake=true).
	var root_sym: AdobeSymbol = AdobeSymbol.new()
	root_sym.name = &"Root"

	var inst: AdobeSymbolInstance = AdobeSymbolInstance.new()
	inst.key = &"Sub"

	var kf: AdobeLayerFrame = AdobeLayerFrame.new()
	kf.starting_index = 0
	kf.duration = 1
	kf.elements = [inst]
	kf._require_bake = true
	kf._dirty = false

	var layer: AdobeLayer = AdobeLayer.new()
	layer.name = &"L"
	layer.layer_type = NORMAL
	layer.frames = [kf]
	layer._fill_frame_indices_from_frames()

	root_sym.layers = [layer]
	atlas.symbols[&"Sub"] = sub_sym
	atlas.symbols[&"Root"] = root_sym

	atlas.set_symbol_dirty(&"Sub")

	if not kf._dirty:
		failures.push_back("set_symbol_dirty: el frame de Root con instancia de Sub no quedo _dirty")
