class_name RubiconMixerPump extends RefCounted

## Runs a set of AnimationTrees only while something can actually move them.
##
## Every state machine in the funkin mania skin advances on
## advance_mode = AUTO with an advance_expression, which means Godot compiles
## each transition into an Expression and executes it once per frame per tree
## for as long as the tree exists. The note has three such trees carrying
## twelve transitions between them, and the lane has one carrying
## twenty-four. Two of the note's expressions - was_hit() and
## was_missed() - are not even constant folds, they are calls back into
## GDScript.
##
## None of that work can change anything unless one of the values the
## expressions read has changed. lane_id and the note's direction are fixed
## for the life of the instance; lane_state, hit and missed change a handful
## of times. So the trees are switched to MANUAL and advanced only in a short
## window after an input moves, which is long enough for the state machine to
## traverse and for the state's own animation to play out.
##
## Measured on the funkin note (tools/bench_note_trees.gd): 15.5us per note
## per frame on x86 with the trees polling, ~1us with them idle.
##
## What this does NOT do is stop the animations themselves. A state's
## animation is a short clip whose animation track hands a looping clip to
## the AnimatedSprite2D's own AnimationPlayer; that player is a separate
## mixer and keeps running on its own. Nothing here touches it.

## How long to keep advancing after an input changes.
##
## The longest state animation in either skin is 0.167s (the lane's hit and
## press clips), and a state machine needs a few advances to walk Start ->
## RESET -> direction. Double the longest clip covers both with room to
## spare, and being a duration rather than a frame count it holds at 30fps
## as well as at 60.
const WAKE_SECONDS := 0.35

var _trees: Array[AnimationTree] = []
var _awake: float = 0.0

## Takes over every AnimationTree directly under [param parent].
##
## Direct children only: a lane's children include its notes, and each note
## owns and pumps the three trees inside it.
func adopt_children_of(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is AnimationTree:
			adopt(child)

func adopt(tree: AnimationTree) -> void:
	if tree == null or _trees.has(tree):
		return

	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_trees.append(tree)
	# The tree has never run, so it is sitting on whatever the scene file
	# saved rather than on the state its inputs ask for.
	wake()

## Restores the trees to advancing themselves, for anything that hands its
## mixers to something else or wants the stock behaviour back.
func release() -> void:
	for tree: AnimationTree in _trees:
		if is_instance_valid(tree):
			tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_trees.clear()
	_awake = 0.0

## Something an advance_expression reads has changed.
func wake() -> void:
	_awake = WAKE_SECONDS

func is_awake() -> bool:
	return _awake > 0.0

## Call once per frame from the owner's _process.
func pump(delta: float) -> void:
	if _awake <= 0.0:
		return

	_awake -= delta
	for tree: AnimationTree in _trees:
		if is_instance_valid(tree):
			tree.advance(delta)
