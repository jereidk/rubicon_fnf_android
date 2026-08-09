extends SceneTree

## The lane half of tools/test_note_pump.gd.
##
## Lane.tscn's AnimationTree is a state machine of state machines carrying
## twenty-four advance_expressions - eight picking the direction from
## lane_id, four per direction reacting to lane_state - and all of them are
## advance_mode = AUTO, so every one runs once per frame per lane whether or
## not anything moved. RubiconMixerPump advances the tree only after
## lane_state changes; this checks that doing so leaves the receptor showing
## exactly what it showed before.
##
## Run with:
##   godot --headless --path . --script tools/test_lane_pump.gd

const LANE := "res://resources/levels/ui/funkin/mania/Lane.tscn"

## Long enough for the tree to walk Start -> RESET -> direction -> state and
## for the pump's wake window to expire, so neither side is read mid-move.
const SETTLE := 40

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load(LANE)
	if packed == null:
		print("FALLO: no pude cargar %s" % LANE)
		quit(1)
		return

	var states: Array[int] = [
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_NEUTRAL,
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_PUSH,
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_HIT,
	]
	var names: Array[String] = ["NEUTRAL", "PUSH", "HIT"]

	for lane_id: int in 4:
		for i: int in states.size():
			var stock: Dictionary = await _snapshot(packed, lane_id, states[i], true)
			var pumped: Dictionary = await _snapshot(packed, lane_id, states[i], false)
			_compare("lane %d, %s" % [lane_id, names[i]], stock, pumped)

	await _sequence_check(packed)

	print("")
	if _failures == 0:
		print("todo OK - el pump deja el receptor en el mismo estado visual")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _snapshot(packed: PackedScene, lane_id: int, state: int, stock: bool) -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)

	var lane: RubiconLevelManiaNoteHandler = packed.instantiate()
	lane.lane_id = lane_id
	holder.add_child(lane)
	if stock:
		lane._pump.release()

	lane.lane_state = state

	for i in SETTLE:
		await process_frame

	var snap: Dictionary = _read(lane)
	holder.queue_free()
	await process_frame
	return snap

## Everything the lane's state machine writes: the sprite clip its animation
## track hands to the child player, and the offset its value track sets.
func _read(lane: Node) -> Dictionary:
	var sprite: AnimatedSprite2D = lane.get_node("AnimatedSprite2D")
	var playback: AnimationNodeStateMachinePlayback = lane.get_node("AnimationTree").get(
		"parameters/playback")
	var outer: StringName = playback.get_current_node() if playback != null else &"?"
	var inner: StringName = &"?"
	if playback != null and outer != &"":
		var nested: Variant = lane.get_node("AnimationTree").get(
			"parameters/%s/playback" % outer)
		if nested is AnimationNodeStateMachinePlayback:
			inner = nested.get_current_node()
	return {
		"sprite_anim": sprite.animation,
		"sprite_offset": sprite.offset,
		"sprite_frame": sprite.frame,
		"estado": "%s/%s" % [outer, inner],
	}

func _compare(label: String, stock: Dictionary, pumped: Dictionary) -> void:
	var differences: Array[String] = []
	for key: String in stock:
		if stock[key] != pumped[key]:
			differences.append("%s: stock=%s pump=%s" % [key, stock[key], pumped[key]])

	if differences.is_empty():
		print("  ok    %-18s  %s  (%s)" % [label, stock["estado"], stock["sprite_anim"]])
		return

	_failures += 1
	print("  FALLO %s" % label)
	for line: String in differences:
		print("          %s" % line)

## A real lane is not set once and left alone - it is pressed, confirmed and
## released, and the pump has to wake for each of those.
func _sequence_check(packed: PackedScene) -> void:
	var holder := Node.new()
	root.add_child(holder)

	var stock: RubiconLevelManiaNoteHandler = packed.instantiate()
	stock.lane_id = 1
	holder.add_child(stock)
	stock._pump.release()

	var pumped: RubiconLevelManiaNoteHandler = packed.instantiate()
	pumped.lane_id = 1
	holder.add_child(pumped)

	var script: Array[int] = [
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_NEUTRAL,
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_PUSH,
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_HIT,
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_NEUTRAL,
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_HIT,
		RubiconLevelManiaNoteHandler.LaneState.LANE_STATE_NEUTRAL,
	]

	var drift: int = 0
	for state: int in script:
		stock.lane_state = state
		pumped.lane_state = state
		for i in 20:
			await process_frame
		if _read(stock)["estado"] != _read(pumped)["estado"]:
			drift += 1

	if drift == 0:
		print("  ok    press -> confirm -> release repetido sigue igual")
	else:
		_failures += 1
		print("  FALLO %d paso(s) de la secuencia divergieron" % drift)

	holder.queue_free()
	await process_frame
