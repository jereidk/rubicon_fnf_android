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

## The sweep's own keyframes, lifted out of the animation at _ready.
##
## The animation cannot drive the sweep on its own and the header above says
## why: an AnimationPlayer advances by delta, so on a scene whose frames cost
## hundreds of milliseconds an 0.8 second animation is over in four or five of
## them. 67c9fad fixed the *reveal* to run off frames instead of wall time and
## stretched it to 6737ms on Chimera; the sweep was left on animation time, so
## it now finishes in the first second and the remaining ~80 nodes are revealed
## with the camera parked wherever the last key left it.
##
## That is the half of the original diagnosis nobody closed: "only what the
## camera saw from its starting pose was ever warmed, which is why pipelines
## keep compiling later, during play." The device log still shows it - Chimera
## compiles ~95 pipelines under the precache and another 73 during the song,
## and the four sequences that stall are the four whose camera goes somewhere
## the sweep never reached: 104_photographysesh (21 pipelines over three
## frames), 121_closetrunout (5), 114_hexapproach (4) and 122_fall, whose worst
## frame is 1911.7ms for `spec+8`.
##
## So the poses are read once and re-served from _process, one per revealing
## frame, cycling. Every batch of newly revealed nodes is then drawn from a
## different viewpoint instead of all of them from the last one.
var _sweep_poses: Array[Transform3D] = []
var _sweep_cursor: int = 0

## How many extra sweep frames this served after the animation ran out, and
## what the reveal had managed by then. Reported at handover, because the
## second number is the one that says whether any of this was needed: if the
## animation finishes with the reveal already done, the sweep was never the
## problem and this whole mechanism is dead weight.
var _sweep_extra_frames: int = 0
var _revealed_at_anim_end: int = -1

## The lights and lightmaps left switched on, so the log can say whether the
## exemption actually took effect.
##
## Two numbers, because `visible` is local and rendering is not. A Light3D
## parented under a mesh that this walk does hide stops rendering anyway, and
## nothing readable from a .tscn can rule that out for the subtrees that come
## out of a .gltf. So the handover reports how many were exempted and how many
## of those are still visible *in the tree* once the hiding is done - if those
## two disagree, some of the scene's lighting is hidden by ancestry and the
## precache is still walking through lighting states.
var _kept_lit: Array[Node] = []

func _kept_lit_effective() -> int:
	var n: int = 0
	for node in _kept_lit:
		if is_instance_valid(node) and (node as Node3D).is_visible_in_tree():
			n += 1
	return n

## Whether the baseline frame has been spent. See _process().
var _measured_first_frame: bool = false

## When the last _process ran, so the next one can measure how long the frame
## between them really took. Set on the baseline frame, never read before it.
var _last_frame_usec: int = 0

func _ready() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS

	if !SceneChanger.awaiting_manual_end:
		finish_preload()
		return

	visible = true
	make_current()
	_started_msec = Time.get_ticks_msec()

	_hide_everything()

	_mark("preload camera '%s' started on %s (%d nodos por revelar, %d luces/bakes intactos de %d)" % [
		animation_name, get_parent().scene_file_path.get_file(), _hidden.size(),
		_kept_lit_effective(), _kept_lit.size(),
	])

	_collect_sweep_poses()

	animation_player.play(animation_name)
	animation_player.animation_finished.connect(_on_animation_finished)

	# Nothing to stagger, so do not make the handover wait a frame for a reveal
	# loop with no work in it.
	if _hidden.is_empty():
		_anim_done = true

## Reads the sweep's poses out of the animation, so they can be re-served after
## the animation itself has run out.
##
## Paired by index rather than by time: the two tracks in every scene here are
## authored with identical key times (fifteen at 0.05s apart on Chimera), and
## pairing on the shorter of the two counts is both simpler and safe against a
## scene that authors only one of them. A rotation with no matching position
## contributes nothing a sweep can use.
##
## Tolerant of finding nothing. A scene whose precache does not move the camera
## - or one whose tracks are named differently - just keeps the old behaviour,
## because _serve_sweep_pose() does nothing with an empty array.
func _collect_sweep_poses() -> void:
	if animation_player == null or not animation_player.has_animation(animation_name):
		return
	var anim: Animation = animation_player.get_animation(animation_name)
	if anim == null:
		return

	var pos_track: int = anim.find_track(^".:position", Animation.TYPE_VALUE)
	var rot_track: int = anim.find_track(^".:rotation", Animation.TYPE_VALUE)
	if pos_track < 0:
		return

	var count: int = anim.track_get_key_count(pos_track)
	if rot_track >= 0:
		count = mini(count, anim.track_get_key_count(rot_track))

	for i in count:
		var origin: Vector3 = anim.track_get_key_value(pos_track, i)
		var basis := Basis.IDENTITY
		if rot_track >= 0:
			basis = Basis.from_euler(anim.track_get_key_value(rot_track, i))
		_sweep_poses.append(Transform3D(basis, origin))

## Puts the camera at the next sweep pose, for the frame that is about to draw
## whatever the reveal just switched on.
##
## Only ever called once the animation is done, so the two never fight over the
## transform - while the animation is playing it owns this node's position and
## rotation, and it is authored to.
func _serve_sweep_pose() -> void:
	if _sweep_poses.is_empty():
		return
	transform = _sweep_poses[_sweep_cursor % _sweep_poses.size()]
	_sweep_cursor += 1
	_sweep_extra_frames += 1

## Classes that are VisualInstance3D but must stay on through the reveal.
##
## This used to hide every VisualInstance3D, and the comment above the walk
## claimed that was "meshes, particles and decals - the things that carry a
## material and therefore need a pipeline". Checked against the 4.7.1 binary,
## VisualInstance3D also covers Light3D and LightmapGI, which carry no material
## and compile no pipeline of their own - and hiding them is actively harmful,
## because the lighting state of the scene is part of the pipeline key.
##
## Measured on the device's own path (Vulkan, Forward Mobile), three meshes
## with three distinct shaders:
##
##     geometria, cero luces          spec=3
##     + una omni                     spec=6   (+3, recompila las mismas)
##     + una spot                     spec=9   (+3)
##     quitando la omni               spec=12  (+3)
##
## Every distinct lighting configuration the scene passes through costs a full
## set. It saturates on count - a third and a fourth omni add nothing - but the
## reveal walks lights and geometry together in DFS order, so the scene goes
## from no lights, through some, to all, and pays for each state. The control
## says the fix is free: turning lights on with nothing visible compiles **0**,
## and revealing the same geometry into an already-lit scene compiles the six
## the game actually uses instead of twelve.
##
## LightmapGI is in here for the same reason plus one more: taking the bake out
## from under a mesh is exactly the failure that blacked Chimera's house out for
## eleven days, and both scenes with a LightmapGI also carry BAKE_STATIC lights
## (the shop has nine). Leaving it on for the whole precache is strictly closer
## to the state the scene ships in.
##
## Deliberately NOT in here:
##
## - `VisibleOnScreenNotifier3D` (6, all in the shop) - hiding it is what stops
##   it firing screen_entered while a 109-degree camera sweeps the whole room.
##   That is a side effect on game logic, not a pipeline question.
## - `ReflectionProbe` (1, the shop) - it does real capture work when visible,
##   so hiding it saves something measurable, and nothing here has measured
##   which of the two costs more.
const KEEP_VISIBLE: Array[StringName] = [&"Light3D", &"LightmapGI"]

## Collects everything in the scene that draws, and hides it.
##
## CanvasItems are deliberately left alone: the loading screen is one, and
## hiding 2D would either blank the very screen this exists to keep alive or
## require telling the scene's 2D apart from the loader's.
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
			if _keeps_lighting(node):
				_kept_lit.append(node)
			else:
				node.visible = false
				_hidden.append(node)
		for child in node.get_children():
			stack.append(child)

## Whether this node defines the scene's lighting rather than drawing into it.
##
## By class name against the running ClassDB rather than by `is`, so one entry
## covers a whole branch: Light3D catches Omni, Spot, Directional and Area
## without naming four types, and a class this fork does not have simply never
## matches instead of failing to parse.
func _keeps_lighting(node: Node) -> bool:
	var cls: StringName = node.get_class()
	for keep in KEEP_VISIBLE:
		if cls == keep or ClassDB.is_parent_class(cls, keep):
			return true
	return false

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
		_last_frame_usec = Time.get_ticks_usec()
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
	#
	# Off a wall clock, because Performance.TIME_PROCESS cannot answer this -
	# as the comment fifteen lines above already says, it is a maximum over the
	# last second refreshed once a second. It does not report the previous
	# frame, and across a frame lasting seconds it reports whatever it held
	# before that frame began. So the controller never saw a spike, never
	# backed off, climbed to MAX_BATCH and revealed 64 nodes at once.
	#
	# The device log has the consequence. Entering the shop compiles 212 render
	# pipelines, and the batch that landed 47 of them took 6981ms in one frame:
	#
	#   [25.67s] precache started (132 nodos por revelar)
	#   [25.97s] pipe=149 (+92)
	#   [34.26s] precache finished (8587ms)  pipe=241 (+47)  proc=6981ms
	#
	# Android calls an app that stops answering input for five seconds
	# unresponsive, and a crash on entering the shop is already on the record
	# for this scene.
	var now_usec: int = Time.get_ticks_usec()
	var last_ms: float = float(now_usec - _last_frame_usec) / 1000.0
	_last_frame_usec = now_usec
	if last_ms > FRAME_BUDGET_MS:
		_batch = maxi(1, _batch / 2)
	else:
		_batch = mini(_batch + 1, MAX_BATCH)

	_reveal(_batch)

	# After the reveal, so this frame draws the nodes it just switched on from
	# the pose it is about to move to rather than from the previous one. Only
	# once the animation has run out; before that the animation owns the
	# transform.
	if _anim_done:
		_serve_sweep_pose()

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
	# The number that says whether the sweep was ever the problem. If the
	# animation ends with the reveal already complete, it kept up and serving
	# extra poses changes nothing; if it ends at 5/88, the other 83 nodes were
	# about to be drawn from one fixed viewpoint.
	_revealed_at_anim_end = _revealed
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
		_mark("preload camera '%s' finished (%dms, %d nodos) barrido=%d poses revelado_al_fin_anim=%d/%d extra=%d frames" % [
			animation_name, Time.get_ticks_msec() - _started_msec, _hidden.size(),
			_sweep_poses.size(), _revealed_at_anim_end, _hidden.size(),
			_sweep_extra_frames,
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
