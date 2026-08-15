extends Camera3D

## Draws the scene once behind the loading screen, so the pipeline compilation
## and GPU uploads a first frame costs are paid before the player is looking
## at it.
##
## It used to do that in a single frame, and the device log measured what that
## costs: 35.6 seconds on the Collector's Shop with exactly ONE frame drawn in
## the whole window, and TIME_PROCESS reporting 38147ms for one process step.
## Across those 35.6s the resource count and the node count do not move at all
## and RAM climbs 9MB, while VRAM climbs 71MB and 154 pipelines compile - so it
## is not loading and not GDScript, it is the GPU-side cost of putting 487
## objects on screen for the first time, all at once.
##
## Two things follow. The screen is frozen solid rather than slow - the loading
## animation does not advance, and a main thread that ignores input for 35
## seconds is well past what Android is willing to wait for. And the camera
## sweep this node exists to perform never happens: the frame after the freeze
## is handed a delta of 35 seconds, so the AnimationPlayer jumps straight to
## the end and fires animation_finished. Only what the camera saw from its
## starting pose was ever warmed, which is why pipelines keep compiling later,
## during play.
##
## Godot 4.7 offers no way out of this at the API level. RenderingServer
## exposes no pipeline or precompilation method at all, and RenderingDevice's
## render_pipeline_create() only builds pipelines for shaders written against
## it directly - it cannot reach the scene renderer's internals. A pipeline
## exists once something has been drawn with it and there is no other way to
## make one. The total work is therefore fixed; the only thing that can change
## is how much of it lands on a single frame.
##
## So this spreads it. Everything the scene draws starts hidden and is revealed
## a few nodes per frame, paced against the previous frame's cost, and the
## loading screen keeps running throughout.

@export var animation_player: AnimationPlayer
@export var animation_name: StringName
@export var camera_to_focus: Camera3D

## What a revealing frame is allowed to cost before the batch shrinks.
##
## Generous on purpose: the goal is a loading screen that keeps moving, not one
## that holds 60fps. A 100ms frame still animates; a 35-second frame is the bug.
const FRAME_BUDGET_MS := 100.0

## Revealed on the first frame, before there is any measurement to go on.
const FIRST_BATCH := 4

## Ceiling, so a scene full of cheap nodes still cannot put every remaining
## pipeline on one frame.
const MAX_BATCH := 64

## Hard stop. If the pacing never converges - a scene over budget no matter how
## small the batch - the rest is revealed at once and the screen hands over. A
## long freeze is bad; a loading screen that never ends is worse.
const DEADLINE_SECONDS := 45.0

var _started_msec: int = 0

## Nodes hidden by this script, in reveal order, and how far through it is.
## Only nodes that were visible go in, so one the scene authored hidden is
## never switched on by the reveal.
var _hidden: Array[Node] = []
var _revealed: int = 0
var _batch: int = FIRST_BATCH
var _anim_done: bool = false
var _finished: bool = false

## Whether the baseline frame has been spent. See _process().
var _measured_first_frame: bool = false

func _ready() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS

	if !SceneChanger.awaiting_manual_end:
		finish_preload()
		return

	visible = true
	make_current()
	_started_msec = Time.get_ticks_msec()

	_hide_everything()

	_mark("preload camera '%s' started on %s (%d nodos por revelar)" % [
		animation_name, get_parent().scene_file_path.get_file(), _hidden.size(),
	])

	animation_player.play(animation_name)
	animation_player.animation_finished.connect(_on_animation_finished)

	# Nothing to stagger, so do not make the handover wait a frame for a reveal
	# loop with no work in it.
	if _hidden.is_empty():
		_anim_done = true

## Collects everything in the scene that draws, and hides it.
##
## VisualInstance3D covers meshes, particles and decals - the things that carry
## a material and therefore need a pipeline. CanvasItems are deliberately left
## alone: the loading screen is one, and hiding 2D would either blank the very
## screen this exists to keep alive or require telling the scene's 2D apart
## from the loader's.
##
## Takes the root rather than reading get_parent(), so it can be exercised
## without this node being in a tree - putting it in one runs _ready(), which
## on any path that is not a real scene change frees the camera on the spot.
func _hide_everything(from: Node = null) -> void:
	var scene: Node = from if from != null else get_parent()
	if scene == null:
		return

	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is VisualInstance3D and node.visible:
			node.visible = false
			_hidden.append(node)
		for child in node.get_children():
			stack.append(child)

func _process(_delta: float) -> void:
	if _finished or _started_msec == 0:
		return

	# The first _process is a measurement, not a reveal.
	#
	# Two reasons, one diagnostic and one real. The diagnostic: the device log
	# shows 11.28 seconds between this node's _ready() finishing and the first
	# process_frame, and it cannot say where they went - Performance.TIME_PROCESS
	# is a per-second maximum, so across a frame that long every timing monitor
	# in the log still reports the previous second's numbers. This mark sits
	# before that frame's draw, so its timestamp splits the window: near the
	# hide means the cost is in the draw, near the handover means it is the rest
	# of the _ready() cascade.
	#
	# The real one: the loop below backs off when the last frame was expensive,
	# and on the first frame there is no last frame. It read TIME_PROCESS from
	# before the scene existed, concluded the frame was cheap, and revealed
	# FIRST_BATCH nodes on top of whatever the scene costs to draw at all -
	# which is the one frame whose cost nobody has measured yet. Paying that
	# baseline alone, once, is worth a frame.
	if not _measured_first_frame:
		_measured_first_frame = true
		_mark("preload camera primer _process a los %dms del escondite (%d ocultos, revelados=%d)" % [
			Time.get_ticks_msec() - _started_msec, _hidden.size(), _revealed,
		])
		return

	if _revealed >= _hidden.size():
		_try_finish()
		return

	if Time.get_ticks_msec() - _started_msec >= int(DEADLINE_SECONDS * 1000.0):
		_mark("preload camera '%s' agoto el plazo con %d/%d revelados" % [
			animation_name, _revealed, _hidden.size(),
		])
		_reveal(_hidden.size() - _revealed)
		_try_finish()
		return

	# A reveal is paid for by the draw that follows this frame, not by the
	# reveal itself, so the only honest reading is how the last frame went.
	# Additive increase, multiplicative decrease: climb slowly while frames are
	# cheap, back off hard the moment one is not.
	var last_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if last_ms > FRAME_BUDGET_MS:
		_batch = maxi(1, _batch / 2)
	else:
		_batch = mini(_batch + 1, MAX_BATCH)

	_reveal(_batch)

func _reveal(count: int) -> void:
	var target: int = mini(_revealed + count, _hidden.size())
	while _revealed < target:
		var node: Node = _hidden[_revealed]
		_revealed += 1
		# Freed between hiding and revealing: a sequence can delete part of the
		# set while the loading screen is still up.
		if is_instance_valid(node):
			node.visible = true

func _on_animation_finished(_anim: StringName = &"") -> void:
	_anim_done = true
	_try_finish()

## Hands over only once the sweep has finished AND everything has been shown,
## so a sweep that runs out early cannot deliver a scene whose pipelines are
## still uncompiled.
func _try_finish() -> void:
	if _anim_done and _revealed >= _hidden.size():
		finish_preload()

func finish_preload(_anim: StringName = &"") -> void :
	if _finished:
		return
	_finished = true

	# Anything still hidden gets its visibility back even on the paths that
	# skip the reveal, or the scene hands over with holes in it.
	_reveal(_hidden.size() - _revealed)

	# 0 when the manual-end branch above skipped straight here without ever
	# starting an animation - worth distinguishing from an animation that
	# genuinely finished in under a millisecond.
	if _started_msec > 0:
		_mark("preload camera '%s' finished (%dms, %d nodos)" % [
			animation_name, Time.get_ticks_msec() - _started_msec, _hidden.size(),
		])

	if camera_to_focus != null and !camera_to_focus.current:
		camera_to_focus.make_current()

	if SceneChanger.awaiting_manual_end:
		SceneChanger.finish_loading_screen()
	queue_free()

# Soft dependency: this camera is also used in scenes opened directly from
# the editor, where DiagnosticsLog's autoload chain may not be running.
func _mark(what: String) -> void :
	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node != null and log_node.has_method("mark"):
		log_node.call("mark", what)
