extends RefCounted

## F13a - filtros (parcial). Cubre:
## - AdobeFilter.parse_list: parseo de 7 tipos con fallback a nombres largos.
## - AdobeFilter.extract_glow_compat: derivacion de glow desde el primer GLOW.
## - AdobeAtlas.expand_filter_bounds: margen por tipo (blur/glow/dropShadow).
## - AdobeColorMatrix.adjust_from_params: math de AdjustColorFilter.
##
## Lo que NO se cubre (F13b): aplicar los filtros (bake a textura).

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_parse_list_optimized(failures)
	_test_parse_list_legacy_dict(failures)
	_test_parse_unknown_filter_dropped(failures)
	_test_extract_glow_compat(failures)
	_test_expand_filter_bounds(failures)
	_test_adjust_from_params_identity(failures)

	return {
		"name": "filters: parseo + glow compat + expand bounds (F13a)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _test_parse_list_optimized(failures: Array[String]) -> void:
	var raw: Array = [
		{"N": "BLF", "BLX": 8.0, "BLY": 8.0, "Q": 1},
		{"N": "GF", "C": "#FF0000", "BLX": 6.0, "BLY": 6.0, "STR": 200.0},
		{"N": "DSF", "D": 5.0, "AL": 45.0, "C": "#000000"},
		{"N": "BF"},
		{"N": "ACF", "BRT": 20},
	]
	var filters: Array[AdobeFilter] = AdobeFilter.parse_list(raw)
	if filters.size() != 5:
		failures.push_back("parse_opt: %d filtros, esperaba 5" % filters.size())
		return
	if filters[0].type != AdobeFilter.AdobeFilterType.BLUR:
		failures.push_back("parse_opt[0]: no es BLUR")
	if filters[1].type != AdobeFilter.AdobeFilterType.GLOW:
		failures.push_back("parse_opt[1]: no es GLOW")
	if filters[2].type != AdobeFilter.AdobeFilterType.DROP_SHADOW:
		failures.push_back("parse_opt[2]: no es DROP_SHADOW")
	if filters[3].type != AdobeFilter.AdobeFilterType.BEVEL:
		failures.push_back("parse_opt[3]: no es BEVEL")
	if filters[4].type != AdobeFilter.AdobeFilterType.ADJUST_COLOR:
		failures.push_back("parse_opt[4]: no es ADJUST_COLOR")


## Formato legacy (no-optimized): dict con nombres largos como claves.
func _test_parse_list_legacy_dict(failures: Array[String]) -> void:
	var raw: Dictionary = {
		"GlowFilter": {"color": "#00FF00", "blurX": 4.0, "blurY": 4.0, "alpha": 0.8},
		"BlurFilter": {"blurX": 2.0, "blurY": 2.0, "quality": 1},
	}
	var filters: Array[AdobeFilter] = AdobeFilter.parse_list(raw)
	if filters.size() != 2:
		failures.push_back("parse_legacy: %d filtros, esperaba 2" % filters.size())
		return
	# Orden de keys en Dictionary de Godot: no garantizado, chequear por tipo.
	var has_glow: bool = false
	var has_blur: bool = false
	for f: AdobeFilter in filters:
		if f.type == AdobeFilter.AdobeFilterType.GLOW:
			has_glow = true
		elif f.type == AdobeFilter.AdobeFilterType.BLUR:
			has_blur = true
	if not has_glow:
		failures.push_back("parse_legacy: falta GLOW")
	if not has_blur:
		failures.push_back("parse_legacy: falta BLUR")


func _test_parse_unknown_filter_dropped(failures: Array[String]) -> void:
	var raw: Array = [
		{"N": "blurFilter", "BLX": 4.0, "BLY": 4.0},
		{"N": "totallyUnknownFilter"},
		{"N": "GF", "C": "#FFFFFF"},
	]
	var filters: Array[AdobeFilter] = AdobeFilter.parse_list(raw)
	if filters.size() != 2:
		failures.push_back("unknown: %d filtros, esperaba 2 (desconocido descartado)" % filters.size())
		return
	if filters[1].type != AdobeFilter.AdobeFilterType.GLOW:
		failures.push_back("unknown: el segundo no es GLOW (el desconocido no se descarto bien)")


func _test_extract_glow_compat(failures: Array[String]) -> void:
	# Con glow: primera coincidencia.
	var raw: Array = [
		{"N": "BLF", "BLX": 4.0},
		{"N": "GF", "C": "#FF00FF", "BLX": 8.0, "BLY": 4.0, "A": 0.5, "STR": 300.0, "IN": true, "KK": true},
	]
	var filters: Array[AdobeFilter] = AdobeFilter.parse_list(raw)
	var glow: Dictionary = AdobeFilter.extract_glow_compat(filters)
	if glow.is_empty():
		failures.push_back("extract_glow: glow vacio teniendo GF")
		return
	if String(glow.get("color")) != "#FF00FF":
		failures.push_back("extract_glow: color=%s" % glow.get("color"))
	if float(glow.get("blur_x")) != 8.0:
		failures.push_back("extract_glow: blur_x=%s" % glow.get("blur_x"))
	if float(glow.get("blur_y")) != 4.0:
		failures.push_back("extract_glow: blur_y=%s" % glow.get("blur_y"))
	if float(glow.get("alpha")) != 0.5:
		failures.push_back("extract_glow: alpha=%s" % glow.get("alpha"))
	if float(glow.get("strength")) != 300.0:
		failures.push_back("extract_glow: strength=%s" % glow.get("strength"))
	if not bool(glow.get("inner")):
		failures.push_back("extract_glow: inner deberia ser true")
	if not bool(glow.get("knockout")):
		failures.push_back("extract_glow: knockout deberia ser true")

	# Sin glow: dict vacio.
	var no_glow: Array[AdobeFilter] = AdobeFilter.parse_list([{"N": "BLF"}])
	if not AdobeFilter.extract_glow_compat(no_glow).is_empty():
		failures.push_back("extract_glow: deberia estar vacio sin GF")


func _test_expand_filter_bounds(failures: Array[String]) -> void:
	var base: Rect2 = Rect2(0.0, 0.0, 100.0, 100.0)

	# Blur 8x8: expande 8 en cada direccion.
	var blur_filters: Array[AdobeFilter] = AdobeFilter.parse_list([{"N": "BLF", "BLX": 8.0, "BLY": 8.0}])
	var blurred: Rect2 = AdobeAtlas.expand_filter_bounds(base, blur_filters)
	if blurred.position != Vector2(-8.0, -8.0):
		failures.push_back("expand_blur: pos=%s, esperaba (-8, -8)" % blurred.position)
	if blurred.size != Vector2(116.0, 116.0):
		failures.push_back("expand_blur: size=%s, esperaba (116, 116)" % blurred.size)

	# Glow inner: NO expande.
	var inner_glow: Array[AdobeFilter] = AdobeFilter.parse_list([{"N": "GF", "BLX": 10.0, "BLY": 10.0, "IN": true}])
	var not_expanded: Rect2 = AdobeAtlas.expand_filter_bounds(base, inner_glow)
	if not_expanded != base:
		failures.push_back("expand_glow_inner: %s != base (inner no debe expandir)" % not_expanded)

	# Glow outer: expande como blur.
	var outer_glow: Array[AdobeFilter] = AdobeFilter.parse_list([{"N": "GF", "BLX": 6.0, "BLY": 6.0, "IN": false}])
	var expanded: Rect2 = AdobeAtlas.expand_filter_bounds(base, outer_glow)
	if expanded.position != Vector2(-6.0, -6.0):
		failures.push_back("expand_glow_outer: pos=%s, esperaba (-6, -6)" % expanded.position)

	# Sin filtros: identidad.
	var none: Array[AdobeFilter] = []
	if AdobeAtlas.expand_filter_bounds(base, none) != base:
		failures.push_back("expand_none: cambio el rect sin filtros")


## adjust_from_params(0, 0, 0, 0) = identidad (brightness 0, hue 0,
## contrast 0 (=> c=1), saturation 0 (=> s=1)).
##
## Verificado contra la math del source: con h=0, cosH=1, sinH=0 ->
## hMat diagonal = (lumR + (1-lumR), lumG + (1-lumG), lumB + (1-lumB)) = (1,1,1).
## Con s=1 -> sMat diagonal = (lumR*0 + 1, ...) = (1,1,1).
## Con c=1 -> cMat diagonal = (1,1,1), offset = 128/255*(1-1)=0.
## Con b=0 -> bMat diag=1, offset=0.
## Producto: diagonal = 1, offset = 0.
func _test_adjust_from_params_identity(failures: Array[String]) -> void:
	var m: AdobeColorMatrix = AdobeColorMatrix.adjust_from_params(0.0, 0.0, 0.0, 0.0)
	if absf(m.color_multipliers[0].x - 1.0) > 0.001:
		failures.push_back("adjust_identity: R mult=%f, esperaba 1.0" % m.color_multipliers[0].x)
	if absf(m.color_multipliers[1].y - 1.0) > 0.001:
		failures.push_back("adjust_identity: G mult=%f, esperaba 1.0" % m.color_multipliers[1].y)
	if absf(m.color_multipliers[2].z - 1.0) > 0.001:
		failures.push_back("adjust_identity: B mult=%f, esperaba 1.0" % m.color_multipliers[2].z)
	if absf(m.color_offsets.x) > 0.001:
		failures.push_back("adjust_identity: R offset=%f, esperaba 0.0" % m.color_offsets.x)
