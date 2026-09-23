extends RefCounted

## F8 - FlxAnimateFrames.getSymbol (maru dcaa33c,
## src/animate/FlxAnimateFrames.hx:90-155).
##
## Divergencia cubierta: el shortcut de nombres con carpeta. Cuando el JSON
## referencia "Folder/walk" pero el dictionary tiene "walk" (o al reves), el
## motor prueba el ultimo segmento del path antes de rendirse. Sin esto,
## cualquier atlas exportado con carpetas de simbolos dibuja instancias
## faltantes.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_exact_match(failures)
	_test_shortcut_direct(failures)
	_test_shortcut_missing(failures)
	_test_no_slash_no_shortcut(failures)
	_test_get_length_of_fallback(failures)

	return {
		"name": "symbol_lookup: get_symbol shortcut de carpetas",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _make_atlas_with(names: Array[StringName]) -> AdobeAtlas:
	var atlas: AdobeAtlas = AdobeAtlas.new()
	for n: StringName in names:
		atlas.symbols[n] = AdobeSymbol.new()
	return atlas


func _test_exact_match(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = _make_atlas_with([&"walk", &"idle"])
	if atlas.get_symbol(&"walk") == null:
		failures.push_back("exact: get_symbol(\"walk\") null")
	if atlas.get_symbol(&"idle") == null:
		failures.push_back("exact: get_symbol(\"idle\") null")


func _test_shortcut_direct(failures: Array[String]) -> void:
	# Dictionary tiene "walk" (nombre corto). El JSON lo referencia como
	# "Symbol 3/walk". Debe resolver via shortcut.
	var atlas: AdobeAtlas = _make_atlas_with([&"walk"])
	var found: AdobeSymbol = atlas.get_symbol(&"Symbol 3/walk")
	if found == null:
		failures.push_back("shortcut_direct: no resolvio \"Symbol 3/walk\" -> \"walk\"")
	elif found != atlas.symbols[&"walk"]:
		failures.push_back("shortcut_direct: devolvio otro symbol")


func _test_shortcut_missing(failures: Array[String]) -> void:
	# Dictionary tiene "idle". El JSON referencia "Symbol 3/walk" (no existe).
	# Debe devolver null, no crashear.
	var atlas: AdobeAtlas = _make_atlas_with([&"idle"])
	if atlas.get_symbol(&"Symbol 3/walk") != null:
		failures.push_back("shortcut_missing: devolvio algo cuando no deberia")


func _test_no_slash_no_shortcut(failures: Array[String]) -> void:
	# Sin slash no hay shortcut. "walk" con dictionary {"idle"} -> null.
	var atlas: AdobeAtlas = _make_atlas_with([&"idle"])
	if atlas.get_symbol(&"walk") != null:
		failures.push_back("no_slash: devolvio algo sin slash y sin match")


func _test_get_length_of_fallback(failures: Array[String]) -> void:
	# get_length_of con nombre exacto devuelve length del symbol.
	var atlas: AdobeAtlas = _make_atlas_with([&"walk", &"stage"])
	atlas.symbols[&"walk"].length = 12
	atlas.stage_symbol = &"stage"
	atlas.symbols[&"stage"].length = 30

	if atlas.get_length_of(&"walk") != 12:
		failures.push_back("length_of: walk = %d, esperaba 12" % atlas.get_length_of(&"walk"))
	if atlas.get_length_of(&"missing") != 30:
		failures.push_back("length_of: fallback stage = %d, esperaba 30" % atlas.get_length_of(&"missing"))
	if atlas.get_length_of(&"Symbol 3/walk") != 12:
		failures.push_back("length_of: shortcut = %d, esperaba 12" % atlas.get_length_of(&"Symbol 3/walk"))
