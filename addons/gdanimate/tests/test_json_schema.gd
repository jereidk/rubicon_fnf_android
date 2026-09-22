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
	_test_matrix_resolve(failures)
	_test_matrix_3d_bit_exact(failures)
	_test_matrix_perspective(failures)
	_test_element_dispatch(failures)

	return {
		"name": "json schema: claves corta/larga por campo + MatrixJson.resolve (FlxAnimateJson.hx)",
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


## MatrixJson.resolve, maru/src/animate/FlxAnimateJson.hx:717-747: el orden
## de fuentes es MX/Matrix -> M3D/Matrix3D -> POS/Position -> identidad.
func _test_matrix_resolve(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var only_mx: Transform2D = atlas.resolve_matrix({"MX": [2, 0, 0, 2, 10, 20]})
	if only_mx.origin != Vector2(10, 20) or only_mx.x.x != 2.0:
		failures.push_back("resolve_matrix: MX no se leyo (dio %s)" % only_mx)

	var only_long: Transform2D = atlas.resolve_matrix({"Matrix": [2, 0, 0, 2, 10, 20]})
	if only_long != only_mx:
		failures.push_back("resolve_matrix: \"Matrix\" (clave larga) dio distinto que \"MX\"")

	# MX gana sobre M3D, igual que el orden del source.
	var both: Transform2D = atlas.resolve_matrix({
		"MX": [1, 0, 0, 1, 7, 7],
		"M3D": [9, 0, 0, 0, 0, 9, 0, 0, 0, 0, 1, 0, 99, 99, 0, 1],
	})
	if both.origin != Vector2(7, 7):
		failures.push_back("resolve_matrix: con MX y M3D presentes tiene que ganar MX, dio origin %s" % both.origin)

	# POS/Position: texture atlas legacy de Adobe Animate 2018. El source
	# devuelve [1, 0, 0, 1, pos.x, pos.y].
	var from_pos: Transform2D = atlas.resolve_matrix({"POS": {"x": 33.0, "y": -44.0}})
	if from_pos != Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(33, -44)):
		failures.push_back("resolve_matrix: POS legacy 2018 dio %s, esperaba identidad trasladada a (33, -44)" % from_pos)

	var from_pos_long: Transform2D = atlas.resolve_matrix({"Position": {"x": 33.0, "y": -44.0}})
	if from_pos_long != from_pos:
		failures.push_back("resolve_matrix: \"Position\" (clave larga) dio distinto que \"POS\"")

	# Sin ninguna fuente: identidad, no null ni basura.
	if atlas.resolve_matrix({}) != Transform2D.IDENTITY:
		failures.push_back("resolve_matrix: un elemento sin matriz tiene que dar identidad")


## Requisito de regresion: para un M3D SIN perspectiva el resultado tiene
## que ser BIT-EXACTO al aplanado viejo (indices 0,1,4,5,12,13). El camino
## nuevo agrega el chequeo de perspectiva adelante, pero cuando no hay
## perspectiva no puede mover ni un bit de lo que ya se dibujaba.
func _test_matrix_3d_bit_exact(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var cases: Array = [
		# a=d=1, b=c=0 - el caso pedido explicitamente.
		[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
		[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 123.5, -67.25, 0, 1],
		# Escala + rotacion, todavia sin perspectiva.
		[0.5, 0.25, 0, 0, -0.75, 1.5, 0, 0, 0, 0, 1, 0, -10.125, 8.0625, 0, 1],
		[2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1, 0, 0.1, 0.2, 5, 1],
	]

	for m: Array in cases:
		# La aproximacion vieja, calculada aca mismo para comparar.
		var old_way: Transform2D = Transform2D(
			Vector2(m[0], m[1]),
			Vector2(m[4], m[5]),
			Vector2(m[12], m[13])
		)
		var new_way: Transform2D = atlas.parse_matrix(m)
		if new_way != old_way:
			failures.push_back("M3D sin perspectiva %s: el nuevo codigo dio %s, la aproximacion vieja %s (tienen que ser identicos)" % [m, new_way, old_way])

		# La forma objeto (m00..m33) tiene que dar exactamente lo mismo que
		# la forma array.
		var as_dict: Dictionary = {}
		for row: int in 4:
			for col: int in 4:
				as_dict["m%d%d" % [row, col]] = m[row * 4 + col]
		if atlas.parse_matrix(as_dict) != new_way:
			failures.push_back("M3D %s: la forma objeto m00..m33 dio distinto que la forma array" % m)


## from3Dto2D con perspectiva (maru/src/animate/FlxAnimateJson.hx:749-776).
## Se compara contra el resultado de aplicar la MISMA formula del source a
## mano, incluido el `/ z` que aplica solo a m[12]/m[13].
func _test_matrix_perspective(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	# m[3] != 0 -> hay perspectiva.
	var m: Array = [2.0, 0.0, 0.0, 0.5, 0.0, 2.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 40.0, 80.0, 0.0, 1.0]

	var expected_points: Array[Vector2] = []
	for point: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]:
		var z: float = m[3] * point.x + m[7] * point.y + m[15]
		expected_points.push_back(Vector2(
			m[0] * point.x + m[4] * point.y + m[12] / z,
			m[1] * point.x + m[5] * point.y + m[13] / z
		))
	var expected: Transform2D = Transform2D(
		expected_points[1] - expected_points[0],
		expected_points[2] - expected_points[0],
		expected_points[0]
	)

	var got: Transform2D = atlas.parse_matrix(m)
	if got != expected:
		failures.push_back("M3D con perspectiva: dio %s, esperaba %s" % [got, expected])

	# Y tiene que ser DISTINTO del aplanado ingenuo, si no el test no prueba nada.
	var naive: Transform2D = Transform2D(Vector2(m[0], m[1]), Vector2(m[4], m[5]), Vector2(m[12], m[13]))
	if got == naive:
		failures.push_back("M3D con perspectiva: el resultado coincide con el aplanado ingenuo - el chequeo de perspectiva no se activo")


## Despacho de elementos de un keyframe, Frame.hx:216-249 (maru dcaa33c):
## SI -> symbol instance, si no ASI -> atlas sprite, si no TFI -> text field
## (no porteado, se saltea), si no NADA. Y `E` puede faltar entero.
func _test_element_dispatch(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	atlas.spritemap[&"pixel"] = _make_sprite()
	atlas.symbols[&"sub"] = atlas.load_layers(true, [
		{"LN": "L", "FR": [{"I": 0, "DU": 1, "E": [{"ASI": {"N": "pixel", "MX": [1, 0, 0, 1, 0, 0]}}]}]},
	])

	var sym: AdobeSymbol = atlas.load_layers(true, [
		{
			"LN": "Mixto",
			"FR": [
				{
					"I": 0,
					"DU": 1,
					"E": [
						{"SI": {"SN": "sub", "ST": "G", "MX": [1, 0, 0, 1, 1, 1]}},
						{"ASI": {"N": "pixel", "MX": [1, 0, 0, 1, 2, 2]}},
						# TFI: el source crea un TextFieldInstance, el port lo
						# saltea. Lo que NO puede pasar es que caiga en
						# load_atlas_sprite (antes reventaba ahi).
						{"TFI": {"TXT": "hola", "MX": [1, 0, 0, 1, 3, 3]}},
						# Tipo desconocido: el source no hace push de nada.
						{"XX": {"lo que sea": 1}},
					],
				},
				# Keyframe sin "E": el source chequea null antes de iterar.
				{"I": 1, "DU": 1},
			],
		},
	])

	if sym.layers.size() != 1:
		failures.push_back("dispatch: esperaba 1 capa, hay %d" % sym.layers.size())
		return

	var frames: Array[AdobeLayerFrame] = sym.layers[0].frames
	if frames.size() != 2:
		failures.push_back("dispatch: esperaba 2 keyframes, hay %d" % frames.size())
		return

	var els: Array[AdobeDrawable] = frames[0].elements
	if els.size() != 2:
		failures.push_back("dispatch: esperaba 2 elementos utiles (SI + ASI), hay %d - TFI o el tipo desconocido se colaron" % els.size())
	else:
		if els[0] is not AdobeSymbolInstance:
			failures.push_back("dispatch: el primer elemento (SI) no salio como AdobeSymbolInstance")
		if els[1] is not AdobeAtlasSprite:
			failures.push_back("dispatch: el segundo elemento (ASI) no salio como AdobeAtlasSprite")

	if not frames[1].elements.is_empty():
		failures.push_back("dispatch: un keyframe sin \"E\" tiene que quedar sin elementos, tiene %d" % frames[1].elements.size())
