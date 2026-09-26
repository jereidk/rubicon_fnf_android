extends RefCounted

## F6 - Layer.hx (262) de MaybeMaru/flixel-animate@dcaa33c.
##
## Divergencias cubiertas:
##   - frame_indices (Layer.hx:34, :186-188): un slot por frame de duracion
##     de cada keyframe. Reemplaza el scan O(N) del port viejo.
##   - Precedencia Clpb > LT (Layer.hx:141-164): si Clpb esta presente la capa
##     es CLIPPED y el LT no se mira.
##   - FOLDER no parsea frames (Layer.hx:181-193).
##   - parentLayer es referencia directa al clipper (Layer.hx:150).
##   - Migracion de caches legacy (clipping:bool -> layer_type).

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const NORMAL := AdobeLayer.LayerType.NORMAL
const CLIPPER := AdobeLayer.LayerType.CLIPPER
const CLIPPED := AdobeLayer.LayerType.CLIPPED
const FOLDER := AdobeLayer.LayerType.FOLDER


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_frame_indices(failures)
	_test_clpb_precedence_over_lt(failures)
	_test_folder_no_frames(failures)
	_test_parent_layer_ref(failures)
	_test_migration_legacy(failures)

	return {
		"name": "layer: frame_indices + LayerType + parent_layer + migracion",
		"passed": failures.is_empty(),
		"failures": failures,
	}


## Layer.hx:186-188: `for (_ in 0...frame.duration) frameIndices.push(i)`.
## Con keyframes de duracion 1, 3, 2 -> [0, 1, 1, 1, 2, 2].
func _test_frame_indices(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var sym: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "L", "FR": [
			{"I": 0, "DU": 1, "E": []},
			{"I": 1, "DU": 3, "E": []},
			{"I": 4, "DU": 2, "E": []},
		]},
	])
	if sym.layers.size() != 1:
		failures.push_back("fi: esperaba 1 capa, hay %d" % sym.layers.size())
		return

	var layer: AdobeLayer = sym.layers[0]
	var expected: Array = [0, 1, 1, 1, 2, 2]
	if layer.frame_indices.size() != expected.size():
		failures.push_back("fi: frame_indices.size=%d, esperaba %d" % [layer.frame_indices.size(), expected.size()])
		return
	for i in expected.size():
		if layer.frame_indices[i] != expected[i]:
			failures.push_back("fi: frame_indices[%d]=%d, esperaba %d" % [i, layer.frame_indices[i], expected[i]])

	# get_frame_at_index: O(1) via el array. Los tres frames validos.
	if layer.get_frame_at_index(0) != layer.frames[0]:
		failures.push_back("fi: get(0) != frames[0]")
	if layer.get_frame_at_index(2) != layer.frames[1]:
		failures.push_back("fi: get(2) != frames[1]")
	if layer.get_frame_at_index(5) != layer.frames[2]:
		failures.push_back("fi: get(5) != frames[2]")
	# Fuera de rango -> null.
	if layer.get_frame_at_index(6) != null:
		failures.push_back("fi: get(6) deberia ser null")
	# Layer.hx:61: `index = FlxMath.maxInt(index, 0)` -> clampa negativos a 0.
	if layer.get_frame_at_index(-1) != layer.frames[0]:
		failures.push_back("fi: get(-1) deberia clampear a 0")


## Layer.hx:141-164: si `Clpb` esta presente la capa es CLIPPED y el bloque
## `else` (donde se evalua LT) NO corre. El port viejo miraba los dos por
## separado. Test: capa con Clpb Y LT=Clp a la vez -> debe ser CLIPPED.
func _test_clpb_precedence_over_lt(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var sym: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "Mask", "LT": "Clp", "FR": [{"I": 0, "DU": 1, "E": []}]},
		# Capa con ambos campos: LT miente (dice Clp), Clpb manda.
		{"LN": "L", "LT": "Clp", "Clpb": "Mask", "FR": [{"I": 0, "DU": 1, "E": []}]},
	])
	if sym.layers.size() != 2:
		failures.push_back("prec: esperaba 2 capas, hay %d" % sym.layers.size())
		return
	var l: AdobeLayer = sym.layers[1]
	if l.layer_type != CLIPPED:
		failures.push_back("prec: layer_type=%d, esperaba CLIPPED (%d)" % [l.layer_type, CLIPPED])


## Layer.hx:181-193: `if (this.layerType != FOLDER) { ... parse FR ... }`.
## Una capa FOLDER con FR en el JSON NO debe crear keyframes.
func _test_folder_no_frames(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var sym: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "Folder", "LT": "Fld", "FR": [{"I": 0, "DU": 3, "E": []}]},
	])
	if sym.layers.size() != 1:
		failures.push_back("folder: esperaba 1 capa")
		return
	var l: AdobeLayer = sym.layers[0]
	if l.layer_type != FOLDER:
		failures.push_back("folder: layer_type=%d, esperaba FOLDER (%d)" % [l.layer_type, FOLDER])
	if not l.frames.is_empty():
		failures.push_back("folder: frames deberia estar vacio, tiene %d" % l.frames.size())
	if not l.frame_indices.is_empty():
		failures.push_back("folder: frame_indices deberia estar vacio")


## Layer.hx:150: `parentLayer = aboveLayer` (referencia directa). Antes el
## port guardaba el nombre y hacia lookup cada vez en frame_bounds.
func _test_parent_layer_ref(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var sym: AdobeSymbol = atlas.load_layers(true, [
		{"LN": "Mask", "LT": "Clp", "FR": [{"I": 0, "DU": 1, "E": []}]},
		{"LN": "L", "Clpb": "Mask", "FR": [{"I": 0, "DU": 1, "E": []}]},
	])
	if sym.layers.size() != 2:
		failures.push_back("parent: esperaba 2 capas")
		return
	var mask: AdobeLayer = sym.layers[0]
	var clipped: AdobeLayer = sym.layers[1]
	if clipped.parent_layer == null:
		failures.push_back("parent: parent_layer es null, esperaba ref a Mask")
		return
	if clipped.parent_layer != mask:
		failures.push_back("parent: parent_layer no apunta a Mask (identidad)")
	if clipped.hidden:
		failures.push_back("parent: hidden=true, deberia ser false (el clipper existe)")


## Migracion de caches legacy: tienen `clipping: bool` pero no layer_type ni
## frame_indices ni parent_layer. Despues de la migracion completa todo debe
## estar en su lugar.
func _test_migration_legacy(failures: Array[String]) -> void:
	# Armamos a mano una capa "como cache viejo".
	var legacy: AdobeLayer = AdobeLayer.new()
	legacy.clipping = true
	legacy.layer_type = AdobeLayer.LayerType.NORMAL
	var f: AdobeLayerFrame = AdobeLayerFrame.new()
	f.starting_index = 0
	f.duration = 3
	legacy.frames = [f]

	var sym: AdobeSymbol = AdobeSymbol.new()
	sym.layers = [legacy]

	sym.migrate_all_layers_from_legacy()

	if legacy.layer_type != CLIPPER:
		failures.push_back("migr: layer_type=%d, esperaba CLIPPER (inferido de clipping=true)" % legacy.layer_type)
	if legacy.frame_indices.size() != 3:
		failures.push_back("migr: frame_indices.size=%d, esperaba 3" % legacy.frame_indices.size())

	# Idempotencia: la segunda corrida no debe cambiar nada.
	var before_size: int = legacy.frame_indices.size()
	var before_type: int = legacy.layer_type
	sym.migrate_all_layers_from_legacy()
	if legacy.frame_indices.size() != before_size:
		failures.push_back("migr: segunda corrida cambio frame_indices")
	if legacy.layer_type != before_type:
		failures.push_back("migr: segunda corrida cambio layer_type")

	# Y una capa CLIPPED sin parent_layer pero con clipped_by del cache viejo:
	# la migracion debe resolver la referencia entre las hermanas.
	var legacy_clipper: AdobeLayer = AdobeLayer.new()
	legacy_clipper.clipping = true
	legacy_clipper.name = &"Mask"
	legacy_clipper.layer_type = AdobeLayer.LayerType.NORMAL  # cache viejo no lo tiene
	var legacy_clipped: AdobeLayer = AdobeLayer.new()
	legacy_clipped.clipped_by = "Mask"
	legacy_clipped.layer_type = AdobeLayer.LayerType.CLIPPED  # se hubiera perdido, pero forzamos
	legacy_clipped.parent_layer = null

	var sym2: AdobeSymbol = AdobeSymbol.new()
	sym2.layers = [legacy_clipper, legacy_clipped]
	sym2.migrate_all_layers_from_legacy()

	if legacy_clipper.layer_type != CLIPPER:
		failures.push_back("migr2: clipper no migro de clipping=true a CLIPPER")
	if legacy_clipped.parent_layer != legacy_clipper:
		failures.push_back("migr2: parent_layer no se resolvio entre hermanas")
