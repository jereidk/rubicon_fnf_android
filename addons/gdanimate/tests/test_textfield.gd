extends RefCounted

## F12a - TextFieldInstance.hx (maru dcaa33c, 124 lineas).
## Cubre parseo del JSON + bounding box + text setter.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_parse_minimal(failures)
	_test_parse_full_attributes(failures)
	_test_bbox_from_matrix(failures)
	_test_text_setter_marks_dirty(failures)
	_test_missing_attributes(failures)

	return {
		"name": "textfield: parseo + bbox + dirty (TextFieldInstance.hx)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _test_parse_minimal(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var el: Dictionary = {
		"TFI": {
			"MX": [1.0, 0.0, 0.0, 1.0, 10.0, 20.0],
			"TXT": "hello",
		}
	}
	var tf: AdobeTextFieldInstance = atlas.load_textfield_instance(true, el)
	if tf.text != "hello":
		failures.push_back("min: text='%s', esperaba 'hello'" % tf.text)
	if tf.font_size != 12:
		failures.push_back("min: font_size=%d, esperaba 12" % tf.font_size)
	if tf.text_color != Color.WHITE:
		failures.push_back("min: color=%s, esperaba WHITE" % tf.text_color)


func _test_parse_full_attributes(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var el: Dictionary = {
		"TFI": {
			"MX": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
			"TXT": "test",
			"ATR": [{
				"SZ": 24,
				"C": "#FF0000",
				"F": "res://fonts/roboto.ttf",
				"ALN": "center",
			}]
		}
	}
	var tf: AdobeTextFieldInstance = atlas.load_textfield_instance(true, el)
	if tf.font_size != 24:
		failures.push_back("full: font_size=%d, esperaba 24" % tf.font_size)
	if tf.text_color != Color(1.0, 0.0, 0.0, 1.0):
		failures.push_back("full: color=%s, esperaba rojo" % tf.text_color)
	if tf.font_path != "res://fonts/roboto.ttf":
		failures.push_back("full: font_path='%s'" % tf.font_path)
	if tf.align != 1:
		failures.push_back("full: align=%d, esperaba 1 (center)" % tf.align)


func _test_bbox_from_matrix(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var el: Dictionary = {
		"TFI": {
			"MX": [1.0, 0.0, 0.0, 1.0, 100.0, 200.0],
			"TXT": "X",
			"ATR": [{"SZ": 16}]
		}
	}
	var tf: AdobeTextFieldInstance = atlas.load_textfield_instance(true, el)
	var bb: Rect2 = tf.bounding_box
	if bb.position != Vector2(100.0, 200.0):
		failures.push_back("bbox: origin=%s, esperaba (100, 200)" % bb.position)
	if bb.size.x <= 0.0 or bb.size.y <= 0.0:
		failures.push_back("bbox: size=%s, esperaba positivo" % bb.size)


func _test_text_setter_marks_dirty(failures: Array[String]) -> void:
	var tf: AdobeTextFieldInstance = AdobeTextFieldInstance.new()
	tf.text = "a"
	tf.ensure_built()
	var size_a: Vector2 = tf.get_text_size()
	if size_a.x <= 0.0:
		failures.push_back("dirty: text 'a' tiene size cero")

	tf.text = "aaaa"
	var size_aaaa: Vector2 = tf.get_text_size()
	if size_aaaa.x <= size_a.x:
		failures.push_back("dirty: setter no reconstruyo la TextLine (a=%s, aaaa=%s)" % [size_a, size_aaaa])


func _test_missing_attributes(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()
	var el: Dictionary = {
		"TFI": {
			"MX": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
			"ATR": [],
		}
	}
	var tf: AdobeTextFieldInstance = atlas.load_textfield_instance(true, el)
	if tf == null:
		failures.push_back("missing: devolvio null")
	if tf.text != "":
		failures.push_back("missing: text='%s', esperaba ''" % tf.text)
