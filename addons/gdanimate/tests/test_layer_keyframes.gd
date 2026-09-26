extends RefCounted

## F13-gap cluster B: Layer.setKeyframe / setBlankKeyframe
## (maru Layer.hx:67-99).

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const NORMAL := AdobeLayer.LayerType.NORMAL


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_blank_keyframe_splits(failures)
	_test_blank_keyframe_at_start_is_noop(failures)
	_test_set_keyframe_copies_elements(failures)
	_test_set_keyframe_at_start_is_noop(failures)

	return {
		"name": "layer_keyframes: setKeyframe + setBlankKeyframe (Layer.hx)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _make_layer(frames_data: Array) -> AdobeLayer:
	var l: AdobeLayer = AdobeLayer.new()
	l.name = &"L"
	l.layer_type = NORMAL
	for d: Dictionary in frames_data:
		var f: AdobeLayerFrame = AdobeLayerFrame.new()
		f.starting_index = int(d.get("I", 0))
		f.duration = int(d.get("DU", 1))
		if d.has("E"):
			for e: AdobeDrawable in d["E"]:
				f.elements.append(e)
		l.frames.append(f)
	l._fill_frame_indices_from_frames()
	return l


func _dummy_sprite() -> AdobeAtlasSprite:
	var s: AdobeAtlasSprite = AdobeAtlasSprite.new()
	s.region = Rect2i(0, 0, 4, 4)
	return s


## setBlankKeyframe en el medio de un keyframe lo divide en dos.
func _test_blank_keyframe_splits(failures: Array[String]) -> void:
	var l: AdobeLayer = _make_layer([
		{"I": 0, "DU": 5, "E": [_dummy_sprite()]},
	])
	if l.frames.size() != 1:
		failures.push_back("blank_setup: esperaba 1 frame")
		return
	if l.frame_indices.size() != 5:
		failures.push_back("blank_setup: frame_indices=%d, esperaba 5" % l.frame_indices.size())
		return

	l.set_blank_keyframe(2)
	if l.frames.size() != 2:
		failures.push_back("blank: frames=%d, esperaba 2" % l.frames.size())
		return
	# Maru NO acorta la duracion del keyframe original (Layer.hx:87-98);
	# solo reescribe `frame_indices` para que los slots [2, 4] apunten al
	# keyframe nuevo. El campo `duration` del original queda intacto.
	if l.frames[0].duration != 5:
		failures.push_back("blank: frame0.duration=%d, esperaba 5 (maru no lo toca)" % l.frames[0].duration)
	if l.frames[1].duration != 3:
		failures.push_back("blank: frame1.duration=%d, esperaba 3" % l.frames[1].duration)
	if l.frames[1].starting_index != 2:
		failures.push_back("blank: frame1.starting_index=%d, esperaba 2" % l.frames[1].starting_index)
	if not l.frames[1].elements.is_empty():
		failures.push_back("blank: frame nuevo tiene %d elementos, esperaba 0" % l.frames[1].elements.size())
	# frame_indices: [0, 1] al original, [2, 3, 4] al nuevo.
	var expected: Array = [0, 0, 1, 1, 1]
	for i in expected.size():
		if l.frame_indices[i] != expected[i]:
			failures.push_back("blank: frame_indices[%d]=%d, esperaba %d" % [i, l.frame_indices[i], expected[i]])


## setBlankKeyframe en el inicio de un keyframe no hace nada.
func _test_blank_keyframe_at_start_is_noop(failures: Array[String]) -> void:
	var l: AdobeLayer = _make_layer([
		{"I": 0, "DU": 3, "E": [_dummy_sprite()]},
	])
	l.set_blank_keyframe(0)
	if l.frames.size() != 1:
		failures.push_back("blank_start: frames=%d, esperaba 1 (no-op)" % l.frames.size())


## setKeyframe en el medio: crea keyframe con COPIA de los elementos.
func _test_set_keyframe_copies_elements(failures: Array[String]) -> void:
	var sp: AdobeAtlasSprite = _dummy_sprite()
	var l: AdobeLayer = _make_layer([
		{"I": 0, "DU": 5, "E": [sp]},
	])
	l.set_keyframe(3)

	if l.frames.size() != 2:
		failures.push_back("setkf: frames=%d, esperaba 2" % l.frames.size())
		return
	if l.frames[1].starting_index != 3:
		failures.push_back("setkf: frame1.starting_index=%d, esperaba 3" % l.frames[1].starting_index)
	if l.frames[1].duration != 2:
		failures.push_back("setkf: frame1.duration=%d, esperaba 2" % l.frames[1].duration)
	if l.frames[1].elements.size() != 1:
		failures.push_back("setkf: frame nuevo tiene %d elementos, esperaba 1" % l.frames[1].elements.size())
	elif l.frames[1].elements[0] != sp:
		failures.push_back("setkf: el elemento no es el mismo (deberia ser referencia)")
	# El frame original conserva su elemento.
	if l.frames[0].elements.size() != 1:
		failures.push_back("setkf: frame original perdio su elemento")


## setKeyframe en el inicio de un keyframe existente no hace nada.
func _test_set_keyframe_at_start_is_noop(failures: Array[String]) -> void:
	var l: AdobeLayer = _make_layer([
		{"I": 0, "DU": 3},
		{"I": 3, "DU": 2},
	])
	l.set_keyframe(0)
	if l.frames.size() != 2:
		failures.push_back("setkf_start: frames=%d, esperaba 2 (no-op)" % l.frames.size())
	# El frame en 3 sigue siendo el original.
	if l.frames[1].starting_index != 3:
		failures.push_back("setkf_start: frame[1].starting_index=%d" % l.frames[1].starting_index)
