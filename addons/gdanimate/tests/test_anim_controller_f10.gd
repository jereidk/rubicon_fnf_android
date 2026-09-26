extends RefCounted

## F10 - FlxAnimateController (maru dcaa33c src/animate/FlxAnimateController.hx,
## 413 lineas). Cubre los dos gaps anotados en el port:
##   1. Signal `on_frame_label` (port de FlxAnimateController.onFrameLabel,
##      FlxAnimateController.hx:19-23).
##   2. set_anim_frame(): port del override set_frameIndex
##      (FlxAnimateController.hx:322-350). Hace posmod por indices.size() y
##      mapea al frame real del simbolo.

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_set_anim_frame_basic(failures)
	_test_set_anim_frame_wrap(failures)
	_test_set_anim_frame_unregistered(failures)
	_test_signal_exists(failures)

	return {
		"name": "anim_controller: set_anim_frame + on_frame_label (FlxAnimateController.hx)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _make_ctrl() -> AdobeAnimateController:
	var sprite: AnimateSymbol = AnimateSymbol.new()
	var ctrl: AdobeAnimateController = AdobeAnimateController.new(sprite)
	return ctrl


func _test_set_anim_frame_basic(failures: Array[String]) -> void:
	var ctrl: AdobeAnimateController = _make_ctrl()
	ctrl.add_by_timeline_indices("walk", PackedInt32Array([2, 5, 8]))

	var f0: int = ctrl.set_anim_frame("walk", 0)
	if f0 != 2:
		failures.push_back("basic: frame(0) = %d, esperaba 2" % f0)

	var f1: int = ctrl.set_anim_frame("walk", 1)
	if f1 != 5:
		failures.push_back("basic: frame(1) = %d, esperaba 5" % f1)

	var f2: int = ctrl.set_anim_frame("walk", 2)
	if f2 != 8:
		failures.push_back("basic: frame(2) = %d, esperaba 8" % f2)


## FlxAnimateController.hx:333 `frame = frame % numFrames` -> wrap.
func _test_set_anim_frame_wrap(failures: Array[String]) -> void:
	var ctrl: AdobeAnimateController = _make_ctrl()
	ctrl.add_by_timeline_indices("walk", PackedInt32Array([2, 5, 8]))

	var f3: int = ctrl.set_anim_frame("walk", 3)
	if f3 != 2:
		failures.push_back("wrap: frame(3) = %d, esperaba 2" % f3)

	var f4: int = ctrl.set_anim_frame("walk", 4)
	if f4 != 5:
		failures.push_back("wrap: frame(4) = %d, esperaba 5" % f4)

	var fneg: int = ctrl.set_anim_frame("walk", -1)
	if fneg != 8:
		failures.push_back("wrap: frame(-1) = %d, esperaba 8 (posmod)" % fneg)


func _test_set_anim_frame_unregistered(failures: Array[String]) -> void:
	var ctrl: AdobeAnimateController = _make_ctrl()
	var result: int = ctrl.set_anim_frame("nope", 0)
	if result != -1:
		failures.push_back("unregistered: %d, esperaba -1" % result)


func _test_signal_exists(failures: Array[String]) -> void:
	var ctrl: AdobeAnimateController = _make_ctrl()
	# El signal tiene que existir y ser conectable.
	if not ctrl.has_signal("on_frame_label"):
		failures.push_back("signal: on_frame_label no existe")
		return
	var received: Array[String] = []
	ctrl.on_frame_label.connect(func(l: String) -> void: received.append(l))
	# Sin atlas, get_current_label() devuelve "" -> no emite. Verificamos que
	# no crashea al llamar notify_frame_changed.
	ctrl.notify_frame_changed(0)
	if not received.is_empty():
		failures.push_back("signal: emision inesperada sin label (%s)" % str(received))
