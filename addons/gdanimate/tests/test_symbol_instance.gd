extends RefCounted

## F3 - SymbolInstance.hx (282) + MovieClipInstance.hx (285) de
## MaybeMaru/flixel-animate@dcaa33c.
##
## El nucleo es getFrameIndex (SymbolInstance.hx:100-140): que frame del
## sub-simbolo muestra una instancia, N frames despues del keyframe que la
## contiene, segun loop type y la ventana firstFrame/lastFrame.
##
## Las secuencias esperadas de abajo estan calculadas a mano siguiendo el
## Haxe linea por linea, NO sacadas de correr el port (seria circular).

const Helpers = preload("res://addons/gdanimate/tests/_helpers.gd")

const LOOP := AdobeSymbolInstance.AdobeSymbolLoopMode.LOOP
const ONE_SHOT := AdobeSymbolInstance.AdobeSymbolLoopMode.ONE_SHOT
const FREEZE := AdobeSymbolInstance.AdobeSymbolLoopMode.FREEZE_FRAME


func run(_tree: SceneTree) -> Dictionary:
	var failures: Array[String] = []

	_test_get_frame_index(failures)
	_test_flx_wrap(failures)

	return {
		"name": "symbol instance: getFrameIndex (SymbolInstance.hx:100-140)",
		"passed": failures.is_empty(),
		"failures": failures,
	}


func _test_get_frame_index(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	# [descripcion, length, first_frame, last_frame, loop_mode, secuencia esperada para difference = 0..N]
	var cases: Array = [
		# --- sin lastFrame ---
		[
			"FF=0 sin LF, LOOP: wrap(d, 0, 3) sobre todo el simbolo",
			4, 0, -1, LOOP, [0, 1, 2, 3, 0, 1],
		],
		[
			# EL caso que la version vieja hacia mal: el source usa
			# FlxMath.wrap(frameIndex, 0, lastIndex), asi que al pasarse del
			# final vuelve al frame 0, no a first_frame. La version vieja
			# daba 7,8,9,7,8,9.
			"FF=7 sin LF, LOOP: se pasa del final y sigue desde 0",
			10, 7, -1, LOOP, [7, 8, 9, 0, 1, 2],
		],
		[
			"FF=0 sin LF, ONE_SHOT: clampea en el ultimo",
			4, 0, -1, ONE_SHOT, [0, 1, 2, 3, 3, 3],
		],
		[
			# span = lastIndex - firstFrame + 1 = 9 - 7 + 1 = 3.
			"FF=7 sin LF, ONE_SHOT: clampea en el ultimo del simbolo",
			10, 7, -1, ONE_SHOT, [7, 8, 9, 9, 9],
		],
		# --- ventana normal (LF >= FF) ---
		[
			"FF=1 LF=2, LOOP: wrap dentro de la ventana",
			4, 1, 2, LOOP, [1, 2, 1, 2, 1],
		],
		[
			"FF=1 LF=2, ONE_SHOT: clampea en LF",
			4, 1, 2, ONE_SHOT, [1, 2, 2, 2],
		],
		[
			# min(lastFrame, lastIndex): LF=99 se recorta al largo real.
			"FF=1 LF=99 (fuera de rango), LOOP: LF se recorta a lastIndex",
			4, 1, 99, LOOP, [1, 2, 3, 1, 2, 3],
		],
		# --- ventana que se pasa del final (LF < FF) ---
		[
			# tail = 5-3 = 2 frames (3, 4); head = LF + 1 = 2 frames (0, 1).
			# totalLength = 4.
			"FF=3 LF=1, LOOP: cola 3,4 + cabeza 0,1",
			5, 3, 1, LOOP, [3, 4, 0, 1, 3, 4, 0, 1],
		],
		[
			"FF=3 LF=1, ONE_SHOT: recorre cola+cabeza una vez y se queda",
			5, 3, 1, ONE_SHOT, [3, 4, 0, 1, 1, 1],
		],
		# --- freeze ---
		[
			"FF=2, FREEZE_FRAME: siempre el mismo",
			4, 2, -1, FREEZE, [2, 2, 2, 2],
		],
		[
			"FF=2 LF=3, FREEZE_FRAME: la ventana no importa",
			4, 2, 3, FREEZE, [2, 2, 2],
		],
	]

	for case: Array in cases:
		var description: String = case[0]
		var length: int = case[1]
		var expected: Array = case[5]

		var element: AdobeSymbolInstance = AdobeSymbolInstance.new()
		element.first_frame = case[2]
		element.last_frame = case[3]
		element.loop_mode = case[4]

		var got: Array[int] = []
		for difference in expected.size():
			got.push_back(atlas.symbol_instance_frame(element, length, difference))

		if got != expected:
			failures.push_back("%s: dio %s, esperaba %s" % [description, got, expected])

	# Un sub-simbolo de largo 0 no puede reventar ni devolver basura.
	var empty: AdobeSymbolInstance = AdobeSymbolInstance.new()
	empty.first_frame = 3
	empty.last_frame = -1
	empty.loop_mode = LOOP
	if atlas.symbol_instance_frame(empty, 0, 5) != 0:
		failures.push_back("length=0: deberia dar 0")


## _flx_wrap es la transcripcion de FlxMath.wrap (max INCLUSIVO), no el
## wrapi() de Godot (max exclusivo). Se chequea contra la formula del source
## aplicada a mano.
func _test_flx_wrap(failures: Array[String]) -> void:
	var atlas: AdobeAtlas = Helpers.make_test_atlas()

	var cases: Array = [
		[0, 0, 3, 0],
		[3, 0, 3, 3],
		[4, 0, 3, 0],
		[7, 0, 3, 3],
		[5, 2, 4, 2],
		[-1, 0, 3, 3],
		[-5, 0, 3, 3],
		[2, 5, 5, 5],
	]
	for case: Array in cases:
		var got: int = atlas._flx_wrap(case[0], case[1], case[2])
		if got != case[3]:
			failures.push_back("_flx_wrap(%d, %d, %d): dio %d, esperaba %d" % [case[0], case[1], case[2], got, case[3]])
