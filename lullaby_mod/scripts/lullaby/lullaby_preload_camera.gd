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

## Extra animations whose OWN camera track gets folded into the sweep, on top
## of this node's own precache animation.
##
## Why this exists: `122_fall@6.8s` still costs `frame=1911.7ms` for `spec+8`
## with RAM and VRAM flat - a pipeline-compile stall, not loading or upload -
## and three more sequences show the same shape (`121_closetrunout@0.7s`
## 489ms `pipe+5`, `104_photographysesh@6.6s` 481ms `pipe+5`,
## `107_turnaround@0.1s` 350ms). All four are cutscene shots whose camera
## frames things nothing else in the song points a camera at - `122_fall`
## alone reveals hex, SerenaFalling, SerenaBrokenArm and three pieces of the
## house on one frame, per its own `:visible` tracks. The precache's own
## sweep (`_sweep_poses` below) only visits the fixed handful of viewpoints
## *its own* animation authors, so a mesh can be `visible = true` for the
## entire loading screen and still never be drawn - and a material that is
## never drawn never compiles. Revealing it does nothing if the camera is
## never pointed at it.
##
## Read from `animation_player` (SequencePlayer, not this node's own
## animation) by name, exactly the same way `_collect_sweep_poses()` reads
## its own animation - the only difference is the node path, since a
## SequencePlayer animation's tracks are written relative to `Sequences`
## (this node's animation is instead its own `.:position`/`.:rotation`,
## because the animated node is the AnimationPlayer's own parent). A name
## with no camera track, or that does not exist, is skipped - this can never
## make the sweep worse, only leave it exactly as it was.
##
## Deliberately does NOT touch `KEEP_VISIBLE`, `_hide_everything()`, or any
## `:visible`/light state - the one thing this project's own history says not
## to touch without eleven days to spare. It only adds camera *viewpoints* for
## the reveal loop that already exists to pass through.
##
## **Verified on device, and the viewpoints alone do not do it.** Log
## 618afe39, build 27868ddd, which ships this feature configured with all four
## names:
##
##     210.3s  104_photographysesh@0.3s   frame=1693.0ms   spec+31
##     213.1s  104_photographysesh@2.5s   frame= 367.9ms   spec+6
##     230.5s  107_turnaround@0.5s        frame= 322.5ms   spec+9
##     313.6s  122_fall@6.8s              frame= 326.0ms   spec+4
##     314.8s  122_fall@7.2s              frame= 929.5ms   spec+8
##
## `vram_delta=+0.0MB` on every one, and the spikes carrying `spec+0` in the
## same stretch are 43-72ms rather than hundreds - so the stall size tracks
## the pipeline count and nothing else, at roughly 50-115ms per pipeline on
## the Adreno 619. Checked before concluding the sweep was at fault: all four
## names resolve in the SequencePlayer's library and all four animations carry
## `../Camera3D:position` and `:rotation`, so it did find them and did run.
##
## The reason is already measured further down this file:
##
##     geometria, cero luces          spec=3
##     + una omni                     spec=6   (+3, recompila las mismas)
##
## **The lighting state is part of the pipeline key**, and the sweep runs with
## the sequence's lights off - `flash` and `PhoneGlow` live under
## `Sequences/SerenaTakingPictures`, whose parents ship `visible = false`, as
## the KEEP_VISIBLE note below already records. Pointing the camera at the
## geometry compiles the "without those lights" variant; when the photo
## session switches them on, every surface they reach needs a different
## specialization. That is the +31.
##
## So the viewpoints are necessary and not sufficient. Warming these shots
## needs the lights that will be on when they play to be on while they are
## swept - see `_force_dark_lights_on()`, which does that half.
@export var extra_sweep_animations: Array[StringName] = []

## Where `extra_sweep_animations` actually live. NOT the same node as
## `animation_player` above: this node's own `animation_player` is
## `PreloadCamera/AnimationPlayer`, whose library holds only `precache` (plus
## the RESET replays already inside it) - checked directly against the scene,
## not assumed. The stalling sequences (`122_fall` etc.) are dispatched by
## `Sequences/SequencePlayer`, a sibling node with its own separate
## `AnimationLibrary`. Left unset, `extra_sweep_animations` does nothing, same
## as an empty array.
@export var extra_sweep_player: AnimationPlayer

## What a revealing frame is allowed to cost before the batch shrinks.
##
## Generous on purpose: the goal is a loading screen that keeps moving, not one
## that holds 60fps. A 100ms frame still animates; a 35-second frame is the bug.
const FRAME_BUDGET_MS := 100.0

## Revealed on the first revealing frame, before there is any measurement to
## go on.
##
## **One, and it used to be four.** The controller below is reactive: it can
## only shrink the batch *after* a frame has cost too much, so whatever the
## first batch reveals is drawn together with nothing protecting it. At four
## the batch grows to five on that frame (the additive increase runs before
## the reveal), so five never-drawn nodes land on one frame and every pipeline
## any of them needs compiles at once.
##
## That frame is the worst in the project, twice over. `10152-665dedd4` logs
## 7787.6ms inside the shop's first precache and `10154-8d1ee1ac` logs
## 7391.8ms in the same place - in a window where RAM and VRAM are flat and
## the only counter moving is `pipe`. The shop reveals its 117 nodes in about
## eleven frames, so the pacer gets ten chances to be right and one chance to
## be blind, and the blind one is where the seven seconds are.
##
## At one, the worst a blind frame can cost is one node. Everything after it
## is paced against a real measurement, and the additive increase gets back to
## a useful batch within a few frames. What it costs is those few frames of
## loading screen, on a precache that already spends eight seconds.
const FIRST_BATCH := 1

## Ceiling, so a scene full of cheap nodes still cannot put every remaining
## pipeline on one frame.
const MAX_BATCH := 64

## Past this multiple of the budget, the batch drops straight to one instead of
## halving. See the branch that uses it.
const PANIC_FACTOR := 10.0

## Hard stop. If the pacing never converges - a scene over budget no matter how
## small the batch - the rest is revealed at once and the screen hands over. A
## long freeze is bad; a loading screen that never ends is worse.
##
## **Fifteen, and it was forty-five.** Forty-five was picked as "surely more
## than enough", and on a good run it is: the shop's precache finishes in
## 5.5-6.4s (logs 95306f21 and d67addb8) and never comes near it. But it is not
## a safety net, it is a **wait the player actually serves** - the loading
## screen is still up for every second of it - and on the run where the pacing
## does not converge the whole forty-five get spent:
##
##     [157.53s] precache 'agoto el plazo' con 48/117 revelados
##     [157.53s] precache finished (45264ms, 117 nodos)
##
## That is the two-minute shop entry users are reporting, and this is the
## largest single term in it: ~33s of load, ~11s of ready, and then 45s of
## deadline. Fifteen cuts thirty seconds off the worst case and cannot touch a
## good one, which finishes in under half of it.
##
## What the shorter deadline costs is real and worth naming: whatever is still
## hidden is revealed on one frame, so a run that would have paced 69 nodes over
## the next thirty seconds now draws them together. That frame is expensive.
## It is also the frame that was going to happen at 45s anyway - the deadline
## has always ended this way - so the change is when it lands, not whether.
const DEADLINE_SECONDS := 15.0

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
## `visible` is local and rendering is not: a Light3D parented under a mesh
## this walk hides stops rendering anyway, and nothing readable from a .tscn
## can rule that out for the subtrees that come out of a .gltf. So the count
## that matters is how many are visible **in the tree**.
##
## Reported as a before/after pair, and the first version of this shipped
## without the "before" - which made it unreadable. Chimera logged
## `11 luces/bakes intactos de 16` and that looked like five lights lost to
## the hiding. Four of them are `flash` and `PhoneGlow` under
## `Sequences/SerenaTakingPictures`, and `Cameralight` and an `OmniLight3D`
## under `Environment/chimera_house/mdl_chimera_camera` - and **both of those
## parents ship `visible = false` in the scene**. Those lights were already
## dark before this node ran. A post-hide count alone cannot tell "hidden by
## my hiding" from "hidden by the scene", so it reported the second as the
## first.
##
## Taking the baseline before anything is hidden makes the drop attributable:
## equal means the exemption held, and any gap is lighting this walk really
## did take away.
var _kept_lit: Array[Node] = []
var _kept_lit_before: int = 0

## Lights switched on for the sweep that the scene ships dark, and the reason
## the photo session stalls.
##
## The four in Chimera, read off the scene: `Cameralight` and an `OmniLight3D`
## under `Environment/chimera_house/mdl_chimera_camera`, and `PhoneGlow` and
## `flash` under `Sequences/SerenaTakingPictures`. All four are locally
## `visible = true` and dark only because an ancestor is not - which is exactly
## the set `_kept_lit` holds and `_kept_lit_effective()` does not count. The log
## says the same thing from the device: `16 luces/bakes exentos, encendidos
## 11 -> 11`.
##
## Why they matter: the lighting state is part of the pipeline key (the bench in
## KEEP_VISIBLE below measures it - geometry with no lights compiles 3, the same
## geometry with one omni compiles 6). The sweep therefore compiles the "without
## the photo lights" variant of every surface it points at, and the first frame
## of `104_photographysesh` needs the other one. Log d67addb8 prices that at 736ms
## + 1662ms for 37 pipelines, with `122_fall` (1177ms) and `107_turnaround`
## (513ms) the same shape.
##
## **Switched on at the RenderingServer, not by making the ancestor visible.**
## That distinction is the whole commit. `af85b29` opened the ancestors, and did
## it before `_hide_everything()`, so the lights came on over a scene that was
## still fully visible: Chimera's precache went 15092ms -> 38530ms with one
## 20295ms frame, the shop's went 24402ms -> 45264ms, and it was reverted whole
## in `7dfa73a`. `RS.instance_set_visible()` writes the one flag that
## `Node3D.visible` propagation writes anyway, reaches nothing else in the tree,
## and fires no `visibility_changed` - so no AnimationTree condition, no
## VisibleOnScreenNotifier3D and no particle emitter can see it happen.
##
## Ordered after the hide, which is the other half of what went wrong: with
## every mesh already hidden the control in KEEP_VISIBLE says turning lights on
## costs **0** pipelines, and the reveal that follows walks into an already-lit
## scene and compiles six variants where it used to compile twelve. Coming on
## before the hide is what cost 20 seconds on one frame.
var _forced_lit: Array[VisualInstance3D] = []

func _kept_lit_effective() -> int:
	var n: int = 0
	for node in _kept_lit:
		if is_instance_valid(node) and _lit_in_tree(node as Node3D):
			n += 1
	return n

## Whether this Node3D actually renders, walking the ancestors by hand.
##
## `is_visible_in_tree()` gives the same answer at runtime and would do here.
## It is not used because it is only correct for a node that is **inside the
## tree**: `Node3D` caches its 3D parent on ENTER_TREE, so a subtree that has
## been built but not yet added reports every child visible regardless of a
## hidden ancestor. Measured on 4.7.1 headless, the same light before and after
## the tree is wired:
##
##     dentro=false   is_visible_in_tree()=true    walk=false
##     dentro=true    is_visible_in_tree()=false   walk=false
##
## That difference is not hypothetical for this file. A guard has to assemble a
## scene to test the selection at all, and under `--script` the tree is not
## wired until after `_initialize()` returns - so the version of this that asked
## the engine passed its behavioural check by accident and would have gone on
## passing it if the selection were inverted. The walk answers the same in both
## states, which is what makes the rule checkable.
##
## The walk stops at the first non-Node3D parent on purpose: 3D visibility
## propagates through Node3D and nothing else, so a Node3D under a plain Node
## under a hidden Node3D still renders, and pretending otherwise would report
## lights as dark that are not.
func _lit_in_tree(node: Node3D) -> bool:
	var spatial: Node3D = node
	while spatial != null:
		if not spatial.visible:
			return false
		spatial = spatial.get_parent() as Node3D
	return true

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

	# After the hide, never before it. See _forced_lit.
	_force_dark_lights_on()

	_mark("preload camera '%s' started on %s (%d nodos por revelar, %d luces/bakes exentos, encendidos %d -> %d, %d forzadas)" % [
		animation_name, get_parent().scene_file_path.get_file(), _hidden.size(),
		_kept_lit.size(), _kept_lit_before, _kept_lit_effective(), _forced_lit.size(),
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

	_collect_extra_sweep_poses()

## Folds `extra_sweep_animations` into `_sweep_poses` - see the export's own
## comment for why. Runs after the precache's own poses so a scene with none
## configured is byte-identical to before this existed.
##
## Matches a track by path *suffix* (`Camera3D:position`/`Camera3D:rotation`)
## rather than resolving the NodePath, deliberately: a SequencePlayer
## animation's tracks are relative to `Sequences`, so the same camera is
## `../Camera3D:position` here and `.:position` in this node's own animation.
## Matching the literal prefix would have to know which convention applies to
## which player; matching the suffix does not have to care, and is safe
## because every camera in these scenes really is named `Camera3D` - checked
## against every sequence's own tracks, not assumed.
func _collect_extra_sweep_poses() -> void:
	if extra_sweep_player == null:
		return

	for extra_name: StringName in extra_sweep_animations:
		if not extra_sweep_player.has_animation(extra_name):
			continue
		var anim: Animation = extra_sweep_player.get_animation(extra_name)
		if anim == null:
			continue

		var pos_track: int = -1
		var rot_track: int = -1
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_VALUE:
				continue
			var path: String = String(anim.track_get_path(i))
			if path.ends_with("Camera3D:position"):
				pos_track = i
			elif path.ends_with("Camera3D:rotation"):
				rot_track = i

		if pos_track < 0:
			continue

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

	# Collected first and hidden second, so the baseline below is read while
	# the scene is still as it shipped. The order of _hidden is unchanged -
	# it is the same walk, just drained afterwards - and the reveal depends on
	# that order.
	var to_hide: Array[Node] = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is VisualInstance3D and node.visible:
			if _keeps_lighting(node):
				_kept_lit.append(node)
			else:
				to_hide.append(node)
		for child in node.get_children():
			stack.append(child)

	_kept_lit_before = _kept_lit_effective()

	for node in to_hide:
		node.visible = false
		_hidden.append(node)

## Whether this node defines the scene's lighting rather than drawing into it.
##
## By class name against the running ClassDB rather than by `is`, so one entry
## covers a whole branch: Light3D catches Omni, Spot, Directional and Area
## without naming four types, and a class this fork does not have simply never
## matches instead of failing to parse.
## Switches on every light the scene ships dark, for the length of the sweep.
##
## Call order is load-bearing: this runs after `_hide_everything()`, so the
## lights come on over a scene with nothing in it. See `_forced_lit` for what
## happens when it does not.
##
## Only the ones dark because of an ancestor. A light the scene authored
## `visible = false` on itself - Chimera's `ClosetLight` is the one - never
## enters `_kept_lit` at all, because `_hide_everything()` only collects nodes
## that are locally visible. That is the right line to draw: an ancestor-dark
## light is one the sequence is about to switch on, and a self-dark light is one
## the author turned off.
func _force_dark_lights_on() -> void:
	for node in _kept_lit:
		var visual := node as VisualInstance3D
		if visual == null or _lit_in_tree(visual):
			continue
		var rid: RID = visual.get_instance()
		if not rid.is_valid():
			continue
		RenderingServer.instance_set_visible(rid, true)
		_forced_lit.append(visual)

## Puts them back before the scene is handed over, so the player never sees a
## frame lit by this.
##
## Skips any whose ancestor has since become visible for real: `Node3D` pushed
## `true` down to the same flag when that happened, and writing `false` over it
## would leave a light the scene wants on switched off - which is the failure
## mode this file already paid eleven days for, in the other direction.
##
## Returns how many it actually put back, because that skip is the half a test
## cannot otherwise see: RS instance visibility is write-only from GDScript.
func _restore_forced_lights() -> int:
	var restored: int = 0
	for visual in _forced_lit:
		if not is_instance_valid(visual) or _lit_in_tree(visual):
			continue
		var rid: RID = visual.get_instance()
		if rid.is_valid():
			RenderingServer.instance_set_visible(rid, false)
			restored += 1
	_forced_lit.clear()
	return restored

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
	if last_ms > FRAME_BUDGET_MS * PANIC_FACTOR:
		# Halving is the right response to 150ms. It is not the right response
		# to seven seconds: from a batch of five it lands on two, which is
		# still several never-drawn nodes on the next frame, and the device
		# logs show the frames right after the monster are themselves 40-70ms.
		# Past PANIC_FACTOR the frame is not "over budget", it is a different
		# kind of event, and the only safe next batch is one.
		_batch = 1
	elif last_ms > FRAME_BUDGET_MS:
		_batch = maxi(1, _batch / 2)
	elif _revealed > 0:
		# No increase on the blind frame. The baseline measured a scene with
		# nothing revealed, so "that frame was cheap" says nothing about what
		# revealing costs - and without this guard the increase runs first and
		# the first reveal is FIRST_BATCH + 1, which is how a constant set to
		# four put five never-drawn nodes on one frame.
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

	# After that reveal and before the handover: the last batch is still warmed
	# with the photo lights on, and the frame the player is given is the scene's
	# own lighting.
	_restore_forced_lights()

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
