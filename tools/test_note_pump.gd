extends SceneTree

## Checks that a note driven by RubiconMixerPump ends up looking exactly like
## one whose AnimationTrees advance themselves every frame.
##
## The pump is a performance change that must not be a visual one, so this
## does not assert against hand-written expectations - it runs both
## configurations through the same states and compares the properties the
## three state machines actually write:
##
##   DirectionTree -> which trail is visible, and the sprite's animation
##   MissedTree    -> the graphic's and the trail's modulate
##   HeldTree      -> the graphic's self_modulate, and show_behind_parent
##
## Run with:
##   godot --headless --path . --script tools/test_note_pump.gd

const NOTE := "res://resources/levels/ui/funkin/mania/Note.tscn"

## Enough frames for a state machine to walk Start -> RESET -> direction and
## for the pump's wake window to run out, so neither side is caught mid-move.
const SETTLE := 40

enum State { NEUTRAL, MISSED, HELD }

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load(NOTE)
	if packed == null:
		print("FALLO: no pude cargar %s" % NOTE)
		quit(1)
		return

	for lane_id: int in 4:
		for state: State in [State.NEUTRAL, State.MISSED, State.HELD]:
			var stock: Dictionary = await _snapshot(packed, lane_id, state, true)
			var pumped: Dictionary = await _snapshot(packed, lane_id, state, false)
			_compare("lane %d, %s" % [lane_id, State.keys()[state]], stock, pumped)

	# A parked note is reused for another note in the same lane, so whatever
	# the last one left behind has to be walked back.
	await _reuse_check(packed)

	print("")
	if _failures == 0:
		print("todo OK - el pump deja la nota en el mismo estado visual")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## Builds one note in one state and reads back what the trees wrote.
func _snapshot(packed: PackedScene, lane_id: int, state: State, stock: bool) -> Dictionary:
	var holder := Node.new()
	root.add_child(holder)

	var handler: RubiconLevelManiaNoteHandler = RubiconLevelManiaNoteHandler.new()
	handler.lane_id = lane_id
	holder.add_child(handler)

	var note: RubiconLevelManiaNote = packed.instantiate()
	note.lane_id = lane_id
	handler.add_child(note)
	if stock:
		note._pump.release()

	# was_hit() and was_missed() read the handler's result for this index,
	# which is the only thing the Missed and Held state machines look at.
	handler.results.resize(1)
	handler.results[0] = _result_for(handler, state)
	note._handler = handler
	note.data_index = 0

	for i in SETTLE:
		await process_frame

	var snap: Dictionary = _read(note)
	holder.queue_free()
	await process_frame
	return snap

func _result_for(handler: RubiconLevelManiaNoteHandler, state: State) -> RubiconLevelNoteHitResult:
	var result := RubiconLevelNoteHitResult.new(handler)
	result.data_index = 0
	match state:
		State.NEUTRAL:
			result.scoring_hit = RubiconLevelNoteHitResult.Hit.HIT_NONE
			result.scoring_rating = RubiconLevelNoteHitResult.Judgment.JUDGMENT_NONE
		State.MISSED:
			result.scoring_hit = RubiconLevelNoteHitResult.Hit.HIT_COMPLETE
			result.scoring_rating = RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS
		State.HELD:
			result.scoring_hit = RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE
			result.scoring_rating = RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT
	return result

## Every property the three state machines can write, and nothing else.
func _read(note: RubiconLevelManiaNote) -> Dictionary:
	var graphic: AnimatedSprite2D = note.get_node("Container/Sprite/Graphic")
	var mask: Control = note.get_node("Container/TrailMask")
	return {
		"sprite_anim": graphic.animation,
		"graphic_modulate": graphic.modulate,
		"graphic_self_modulate": graphic.self_modulate,
		"mask_modulate": mask.modulate,
		"show_behind_parent": note.show_behind_parent,
		"trail_l": mask.get_node("TrailL").visible,
		"trail_d": mask.get_node("TrailD").visible,
		"trail_u": mask.get_node("TrailU").visible,
		"trail_r": mask.get_node("TrailR").visible,
	}

func _compare(label: String, stock: Dictionary, pumped: Dictionary) -> void:
	var differences: Array[String] = []
	for key: String in stock:
		if stock[key] != pumped[key]:
			differences.append("%s: stock=%s pump=%s" % [key, stock[key], pumped[key]])

	if differences.is_empty():
		print("  ok    %s  (%s)" % [label, stock["sprite_anim"]])
		return

	_failures += 1
	print("  FALLO %s" % label)
	for line: String in differences:
		print("          %s" % line)

## A note that was parked while greyed out must come back clean.
func _reuse_check(packed: PackedScene) -> void:
	var holder := Node.new()
	root.add_child(holder)

	var handler: RubiconLevelManiaNoteHandler = RubiconLevelManiaNoteHandler.new()
	handler.lane_id = 2
	holder.add_child(handler)

	var note: RubiconLevelManiaNote = packed.instantiate()
	note.lane_id = 2
	handler.add_child(note)

	handler.results.resize(1)
	handler.results[0] = _result_for(handler, State.MISSED)
	note._handler = handler
	note.data_index = 0

	for i in SETTLE:
		await process_frame

	var missed: Dictionary = _read(note)
	if missed["graphic_modulate"] == Color.WHITE:
		_failures += 1
		print("  FALLO la nota fallada nunca se puso gris, la prueba no mide nada")

	# What despawn -> park -> spawn does to it.
	note.visible = false
	note.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame

	handler.results[0] = _result_for(handler, State.NEUTRAL)
	note.process_mode = Node.PROCESS_MODE_INHERIT
	note.visible = true
	note.initialize(handler, 0)

	for i in SETTLE:
		await process_frame

	var reused: Dictionary = _read(note)
	if reused["graphic_modulate"] == Color.WHITE:
		print("  ok    la nota reutilizada vuelve a color normal")
	else:
		_failures += 1
		print("  FALLO la nota reutilizada sigue gris  (%s)" % reused["graphic_modulate"])

	holder.queue_free()
	await process_frame
