extends RefCounted

## F1 - fidelidad del esquema de claves del Animation.json contra
## maru/src/animate/FlxAnimateJson.hx (ref dcaa33c).
##
## Ese archivo NO tiene un "modo optimizado" global: cada campo se resuelve
## por separado con `this.<corta> ?? this.<larga>` (FlxAnimateJson.hx:129-130
## y ~90 getters mas). Este parser elegia el esquema una sola vez con
## `optimized = data.has("AN")` y despues miraba una sola clave, asi que
## cualquier JSON de claves mezcladas - que Adobe si produce, con el bloque
## raiz corto y los LIBRARY/*.json largos - perdia campos en silencio.
##
## Test de unidad puro sobre el parser (no dibuja nada): arma diccionarios
## sinteticos y verifica que load_layers/load_frame/load_symbol_instance
## lean los mismos valores con claves cortas, largas y mezcladas.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_pair_helpers(failures)
	_test_mixed_keys(failures)

	return {
		"name": "json schema: claves corta/larga se resuelven por campo (FlxAnimateJson.hx)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


## get_pair/has_pair tienen que encontrar el campo este escrito como este
## escrito, sin importar el flag `optimized` que reciban.
func _test_pair_helpers(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var short_dict: Dictionary = {"I": 7}
	var long_dict: Dictionary = {"index": 7}
	var empty_dict: Dictionary = {}

	for flag: bool in [true, false]:
		if atlas.get_pair(flag, short_dict, "index", "I") != 7:
			failures.push_back("get_pair(optimized=%s): no leyo la clave corta 'I'" % flag)
		if atlas.get_pair(flag, long_dict, "index", "I") != 7:
			failures.push_back("get_pair(optimized=%s): no leyo la clave larga 'index'" % flag)
		if not atlas.has_pair(flag, short_dict, "index", "I"):
			failures.push_back("has_pair(optimized=%s): dijo false para la clave corta" % flag)
		if not atlas.has_pair(flag, long_dict, "index", "I"):
			failures.push_back("has_pair(optimized=%s): dijo false para la clave larga" % flag)
		if atlas.has_pair(flag, empty_dict, "index", "I"):
			failures.push_back("has_pair(optimized=%s): dijo true para un dict sin ninguna de las dos" % flag)
		if atlas.get_pair(flag, empty_dict, "index", "I") != null:
			failures.push_back("get_pair(optimized=%s): no devolvio null sin ninguna de las dos" % flag)

	# La corta gana, igual que el orden del `??` de Haxe (`this.I ?? this.index`).
	var both: Dictionary = {"I": 1, "index": 2}
	if atlas.get_pair(false, both, "index", "I") != 1:
		failures.push_back("get_pair: con ambas claves presentes tiene que ganar la corta (como `this.I ?? this.index`)")


## El caso que rompia de verdad: un simbolo escrito en formato LARGO dentro
## de un atlas que el parser marco como "optimizado" (y al reves). Antes
## cargaba capas sin nombre, sin frames y sin elementos, sin un solo error.
func _test_mixed_keys(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"pixel"] = _make_sprite()

	var long_layers: Array = [
		{
			"Layer_name": "Capa larga",
			"Frames": [
				{
					"index": 0,
					"duration": 3,
					"name": "etiqueta",
					"elements": [{"ATLAS_SPRITE_instance": {"name": "pixel", "Matrix": [1, 0, 0, 1, 5, 6]}}],
				}
			],
		},
	]
	var short_layers: Array = [
		{
			"LN": "Capa corta",
			"FR": [
				{
					"I": 0,
					"DU": 3,
					"N": "etiqueta",
					"E": [{"ASI": {"N": "pixel", "MX": [1, 0, 0, 1, 5, 6]}}],
				}
			],
		},
	]

	# Cruzado a proposito: el formato largo se parsea con optimized=true y el
	# corto con optimized=false. Con la resolucion por campo el flag no
	# cambia nada; con el esquema global los dos daban basura.
	var from_long: AdobeSymbol = atlas.load_layers(true, long_layers)
	var from_short: AdobeSymbol = atlas.load_layers(false, short_layers)

	for pair: Array in [["largo", from_long, "Capa larga"], ["corto", from_short, "Capa corta"]]:
		var tag: String = pair[0]
		var sym: AdobeSymbol = pair[1]
		var expected_name: String = pair[2]

		if sym.layers.size() != 1:
			failures.push_back("formato %s: esperaba 1 capa, hay %d" % [tag, sym.layers.size()])
			continue

		var layer: AdobeLayer = sym.layers[0]
		if layer.name != expected_name:
			failures.push_back("formato %s: Layer_name/LN dio \"%s\"" % [tag, layer.name])
		if layer.frames.size() != 1:
			failures.push_back("formato %s: esperaba 1 keyframe, hay %d" % [tag, layer.frames.size()])
			continue

		var frame: AdobeLayerFrame = layer.frames[0]
		if frame.duration != 3:
			failures.push_back("formato %s: duration/DU dio %d, esperaba 3" % [tag, frame.duration])
		if frame.frame_label != "etiqueta":
			failures.push_back("formato %s: name/N (label) dio \"%s\"" % [tag, frame.frame_label])
		if frame.elements.size() != 1:
			failures.push_back("formato %s: esperaba 1 elemento, hay %d" % [tag, frame.elements.size()])
			continue

		var element: AdobeDrawable = frame.elements[0]
		if element is not AdobeAtlasSprite:
			failures.push_back("formato %s: el elemento no salio como AdobeAtlasSprite" % tag)
		elif element.transform.origin != Vector2(5, 6):
			failures.push_back("formato %s: Matrix/MX dio origin %s, esperaba (5, 6)" % [tag, element.transform.origin])

	if sym_length(from_long) != sym_length(from_short):
		failures.push_back("formato largo y corto dieron largos distintos: %d vs %d" % [sym_length(from_long), sym_length(from_short)])


func sym_length(sym: AdobeSymbol) -> int:
	return sym.length


func _make_sprite() -> AdobeAtlasSprite:
	var sprite: AdobeAtlasSprite = AdobeAtlasSprite.new()
	sprite.region = Rect2i(0, 0, 4, 4)
	sprite.rotated = false
	sprite.texture = Helpers.make_solid_texture(Color.RED, Vector2i(4, 4))
	sprite.transform = Transform2D.IDENTITY
	return sprite
