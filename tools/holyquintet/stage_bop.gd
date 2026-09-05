# Plays a beat- every-2-beats bop on the stage's animated props, wired to the level
# clock. resonance.hx does `if (curBeat % 2) == 0 { playAnim('bop', true) }` for Madoka,
# Mami and the speaker - this is that, driven off RubiconLevelClock.step_change.
extends Node

var targets: Array = []

var _clock: Node = null


func _ready() -> void:
	await get_tree().process_frame
	var controller := get_parent().get_parent().get_node_or_null("RubiconLevelNoteController")
	if controller == null:
		return
	_clock = controller.get_level_clock()
	_clock.step_change.connect(_on_step)


func _on_step(step: int) -> void:
	if step % 8 != 0:
		return
	for entry: Dictionary in targets:
		var node: Node = get_parent().get_node_or_null(entry["node"])
		if node == null:
			continue
		var player: AnimationPlayer = node.get_node_or_null("AnimateSymbol/AnimationPlayer") \
			if node.has_node("AnimateSymbol/AnimationPlayer") else node.get_node_or_null("AnimationPlayer")
		if player == null:
			continue
		player.play(entry["anim"])
