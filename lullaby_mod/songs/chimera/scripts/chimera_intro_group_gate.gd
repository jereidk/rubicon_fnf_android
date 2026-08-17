extends Node

## Forces Chimera's `Intro` group hidden outside the two sequences that own it.
##
## THIS IS A PATCH OVER A CAUSE NOBODY HAS IDENTIFIED. Do not read it as the
## bug being solved. If you are here because you want to remove it, read this
## whole comment first - the underlying fault may well still be live.
##
## The symptom, reported from device across three builds: after Chimera's
## opening cutscene a black graphic covers the stage - full height, roughly
## three quarters of the width - and stays for the rest of the song. It covers
## the stage and not the notes because `Intro` hangs off the scene root, below
## `UILayer`.
##
## What is established:
##
##   - The mod already handles this. `103_stroll` writes `../Intro:visible =
##     false` at t=0, authored since the original port (56abe29). Nothing was
##     ever missing from the data.
##   - `103_stroll` genuinely runs. The device log has it from 206.37s to
##     221.64s while Intro/OutsideDoor is still covering the screen, with no
##     matching "deja de taparla" among 35 BLACKOUT entries.
##   - `102_intro`'s `intro-end` clip key sat at 14.791667 while the sequence
##     is cut at 14.666632 by the next dispatch, so that cleanup had never run
##     in this port. Fixed in 99301f1 - and the symptom survived it.
##   - Four candidate regressions are ruled out: the animated-bool commit and
##     its revert (fully reverted, and it only ever touched tools/), the API
##     sweep (tooling and notes, no engine code), the dance-grid restore (a
##     signal and a guard, nothing to do with visibility), and the precache
##     rework (dated after the first report of the symptom).
##
## So a value track that the mod authors, on a sequence that provably runs, is
## not taking effect, and reading the scene text has not explained why in
## three attempts. That is a runtime question - who else writes this property
## and in what order - and it needs a device log with anim= and seq= in it,
## which is exactly what those fields were added for.
##
## Until then this holds the invariant the scene already asks for, and only
## that: `Intro` is visible during 101_prelude and 102_intro, and hidden
## everywhere else. It cannot fight the authored design because it agrees with
## it - if this ever changes what the player sees during those two sequences,
## the sequences changed and this is wrong.

## The sequences that legitimately show the intro group. 101_prelude raises it
## partway through (its own track goes false at 0 and true at 15.9167) and
## 102_intro holds it up; everything after 103_stroll should not see it.
const OWNING_SEQUENCES: Array[StringName] = [&"101_prelude", &"102_intro"]

@export var intro_group: CanvasItem
@export var sequence_player: AnimationPlayer


func _ready() -> void:
	if intro_group == null or sequence_player == null:
		# Nothing to guard, and no reason to burn a frame callback saying so.
		set_process(false)


func _process(_delta: float) -> void:
	if not intro_group.visible:
		return

	# Only ever hides, never shows. Whatever raises the group during its own
	# sequences keeps doing so; this just refuses to let it outlive them.
	var current: StringName = sequence_player.assigned_animation
	if current in OWNING_SEQUENCES:
		return

	intro_group.visible = false
