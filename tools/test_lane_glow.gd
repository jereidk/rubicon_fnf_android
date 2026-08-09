extends SceneTree

## Answers one question with evidence instead of reasoning about Godot's
## process order: can the lane's AnimationTree see a lane_state that is set
## and cleared inside the same frame?
##
## The receptor's glow is a state machine transition, neutral -> hit_init,
## whose advance_expression is "lane_state == 2". During autoplay
## RubiconLevelManiaNoteHandler.hit_note() sets that, and the mania _process
## clears it again a few lines later in the same call. Whether the glow ever
## happens therefore comes down to whether the AnimationTree gets a look in
## between - which is not something to guess at.
##
## The lane is instantiated with no controller parent, so _should_process()
## is false and neither _process touches lane_state. This script is then the
## only thing writing it.
##
## Run with:
##   xvfb-run -a --server-args="-screen 0 640x480x24" \
##     godot --path . --script tools/test_lane_glow.gd

const LANE := "res://lullaby_mod/resources/funkin/ui/monochrome/lne_default_mono.tscn"

const NEUTRAL := 0
const HIT := 2

## When the handler puts lane_state back to NEUTRAL after an autoplay hit.
## SAME_FRAME is what upstream does; NEXT_FRAME is what
## lane_autoplay_hit_lingers changes it to.
enum Clear { NEVER, SAME_FRAME, NEXT_FRAME }

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame

	await _case("mantenido varios frames", Clear.NEVER, true)
	await _case("borrado en el mismo frame (sin el arreglo)", Clear.SAME_FRAME, false)
	await _case("borrado al frame siguiente (con el arreglo)", Clear.NEXT_FRAME, true)

	print("")
	if _failures == 0:
		print("todo OK")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _case(name: String, clear: Clear, expected: bool) -> void:
	var packed: PackedScene = load(LANE)
	var lane: Node = packed.instantiate()
	root.add_child(lane)

	# hit_init -> hit reads results[last_hit_note_index].scoring_hit, so the
	# lane needs one result to look at or the expression cannot evaluate.
	var result := RubiconLevelNoteHitResult.new(lane)
	result.scoring_hit = RubiconLevelNoteHitResult.Hit.HIT_COMPLETE
	# Appended rather than assigned: results is Array[RubiconLevelNoteHitResult]
	# and an untyped literal will not go into it.
	lane.results.append(result)
	lane.last_hit_note_index = 0

	var tree: AnimationTree = lane.get_node("AnimationTree")
	tree.active = true
	await process_frame
	await process_frame

	var before: String = _state(tree)
	# A run whose state machine never started would report "no glow" for both
	# cases and read as a clean confirmation of the diagnosis. Fail instead.
	if not before.ends_with("/neutral"):
		_failures += 1
		print("%s:\n   FALLO de montaje: la maquina arranca en %s, no en neutral"
			% [name, before])
		lane.queue_free()
		await process_frame
		return

	# Exactly what the handler does: hit_note() sets HIT, and the mania
	# _process puts it back - the only question is when.
	lane.lane_state = HIT
	if clear == Clear.SAME_FRAME:
		lane.lane_state = NEUTRAL

	var seen: Array[String] = []
	for i in 30:
		await process_frame
		if i == 0 and clear == Clear.NEXT_FRAME:
			lane.lane_state = NEUTRAL
		var now: String = _state(tree)
		if seen.is_empty() or seen[-1] != now:
			seen.append(now)

	var glowed: bool = seen.any(func(s: String) -> bool:
		return s.contains("/hit"))

	print("%s:" % name)
	print("   estado inicial: %s" % before)
	print("   recorrido:      %s" % " -> ".join(seen))
	print("   se ilumina:     %s" % ("SI" if glowed else "NO"))

	if glowed != expected:
		_failures += 1
		print("   FALLO: se esperaba %s" % ("SI" if expected else "NO"))

	# A confirm that lights and never goes out is its own bug - the lane
	# would stay lit for the rest of the song - so the one-frame case has to
	# come back to neutral on its own, off the at-end transition.
	if clear == Clear.NEXT_FRAME and not seen[-1].ends_with("/neutral"):
		_failures += 1
		print("   FALLO: se queda en %s en vez de volver a neutral" % seen[-1])

	lane.queue_free()
	await process_frame

## The lane nests two state machines: an outer one that picks a direction off
## lane_id, and inside each direction the neutral/push/hit_init/hit machine
## that the glow lives in. Reading only the outer one reports "left" forever
## and says nothing about the glow, so this returns "<direction>/<state>".
func _state(tree: AnimationTree) -> String:
	var outer: AnimationNodeStateMachinePlayback = tree.get("parameters/playback")
	if outer == null:
		return "<sin playback>"

	var direction: String = String(outer.get_current_node())
	if direction.is_empty():
		return "<sin estado>"

	var inner: AnimationNodeStateMachinePlayback = tree.get(
		"parameters/%s/playback" % direction)
	if inner == null:
		return direction
	return "%s/%s" % [direction, String(inner.get_current_node())]
