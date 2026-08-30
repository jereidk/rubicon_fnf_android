extends Node

## Writes a diagnostics log to disk so problems that only happen on a real
## phone can be read after the fact instead of reproduced on demand.
##
## The on-screen debug display already shows FPS, memory and render counters,
## but it only shows them NOW - by the time the player notices a stutter the
## interesting numbers are two seconds gone, and nobody can read a counter
## while playing anyway. This records the same figures continuously, keeps a
## rolling window of recent frames, and writes a detailed snapshot whenever
## something is actually worth looking at.
##
## It is deliberately quiet during normal play. Writing a line every frame
## would produce a log too large to read, cost I/O on the very frames that
## are already struggling, and bury the real events. Instead it logs:
##
##   - a heartbeat every HEARTBEAT_SECONDS, so there is always a baseline to
##     compare a spike against
##   - a frame spike, when a frame takes SPIKE_FACTOR times longer than the
##     recent median (this is what a stutter looks like from in here)
##   - a memory jump, when static memory grows by MEMORY_JUMP_MB at once
##   - scene changes, with the before/after memory and how long the load took
##   - every error and warning that reaches ErrorHandler
##
## Each entry carries the full counter set, so any single line is enough to
## tell a CPU-bound stall (process time up, draw calls flat) from a GPU one
## (draw calls and VRAM up) from a leak (orphan nodes climbing across
## heartbeats) - which is exactly the distinction that decides how to fix it.
##
## Two of those counters are read far more often than they are read
## correctly, so they are worth spelling out:
##
##   proc=  is Performance.TIME_PROCESS, which Godot resets once a second.
##          It is the WORST frame in that second, not the frame's own process
##          time and not an average. A menu sitting at a solid 60fps reports
##          proc=20ms routinely. Compare median= (this file's own rolling
##          median of real frame times) to judge the typical frame, and read
##          proc= as "how bad the worst hitch in that second was".
##
##   draw=  is a count of draw calls, not a duration. It says how much work
##          was handed to the GPU, not how long the GPU took - gpu= says
##          that, and it is a real hardware timestamp.
##
## script= exists because those two plus churn= still left most of a bad
## frame unexplained: Monochrome's spikes run 45-144ms with gpu at 12ms,
## cpu_render at 1ms and note churn at 0.3ms, which accounts for about a
## tenth of the frame. It brackets the whole per-frame processing pass -
## every node's _process, and the internal processing AnimationPlayer and
## AnimationTree run alongside it - so a spike now splits into "the main
## thread was busy" (script high) and "the main thread was waiting" (script
## low, and the time is in the render/present path instead). Those two want
## opposite fixes, and nothing in this log could tell them apart.

## Where the log goes, in order of preference.
##
## ANDROID_APP is the app-private external directory. It shows up in any file
## manager and needs no permission whatsoever on Android 4.4+.
##
## There used to be a first choice above it: a hidden folder at the root of
## shared storage, so everything the game writes for the player to find lived
## in one place. Reaching it needs "All files access"
## (MANAGE_EXTERNAL_STORAGE), which was the only permission this build asked
## for, and the device logs show it was never used anyway - every session
## reports dir_used as the app-private path, because that entry is tried
## first once the shared one fails. Dropping both means the APK requests no
## permissions at all and nothing about where the log lands changes.
##
## FALLBACK is user://, which Godot maps to INTERNAL app storage
## (/data/user/0/<package>/files) - unreachable without root, and the reason
## the log appeared to not exist at all before. Kept last so desktop builds
## and locked-down devices still log rather than silently doing nothing.
##
## The package name has to be spelled out because Godot exposes no API for
## it; keep it in step with export_presets.cfg's package/unique_name.
## Fallback only - the real package is read back from user:// at runtime by
## _android_package(), so a build exported under a different package name
## (a side-by-side test build, say) still logs into its own directory
## instead of one the OS will not let it write to.
const ANDROID_PACKAGE := "com.rubicon.fnf"
const ANDROID_APP_LOG_DIR_FMT := "/storage/emulated/0/Android/data/%s/files/logs"
const FALLBACK_LOG_DIR := "user://logs"

const MAX_LOG_FILES := 5

## A frame this much slower than the recent median counts as a spike. 2.5x is
## high enough that ordinary jitter doesn't trip it but low enough to catch a
## hitch the player would feel.
const SPIKE_FACTOR := 2.5
const SPIKE_MIN_MS := 24.0

const MEMORY_JUMP_MB := 24.0
const HEARTBEAT_SECONDS := 5.0
const WINDOW_SIZE := 120

## Spikes cluster - one stutter can trip the check for several frames running,
## and a loading screen can trip it dozens of times. Rate-limited so a single
## bad moment costs a few lines rather than a few hundred.
const SPIKE_COOLDOWN_SECONDS := 0.5

## A frame this long is reported whatever the window thinks, and this exists
## because the window was wrong twice about the same stretch of the session.
##
## _frames_seen is reset to 0 on every SCENE_IN, deliberately - the frame
## buffer is meaningless across a load and moderate frames after one would
## otherwise read as spikes against a stale pre-load median. But the gate that
## reset feeds is `_frames_seen > WINDOW_SIZE`, and WINDOW_SIZE is 120, so the
## detector is disarmed for 120 frames after every load. The precache runs
## immediately after one, at a handful of frames per second: the shop's spends
## 8.6 seconds and never gets near 120 frames. So the detector is asleep across
## exactly the stretch it exists to measure.
##
## Measured twice, on two builds. 10152-665dedd4 has a 7787.6ms frame inside
## the shop's first precache and no SPIKE line for it. 10154-8d1ee1ac, after
## the four gate timers were moved to the wall clock, still has a 7391.8ms one
## and still no SPIKE. Both times only SUMMARY caught it, because
## _bucket_worst_ms never consults the window.
##
## 250ms cannot be a false positive. It is fifteen frames at 60fps, the player
## sees it on any device, and it is worth a line at any point in a load. The
## ratio test stays for everything below it, where "spike" really does mean
## "against what this scene normally costs".
const SPIKE_ALWAYS_MS := 250.0

## Cuantas entradas seguidas con `gpu` a cero y `cpu_render` por encima de
## cero hacen falta para dar el reloj de GPU por no soportado.
##
## No todos los drivers contestan a `viewport_get_measured_render_time_gpu`.
## El moto g(60)s (Mali-G76 MC4, driver 1.1.131) devuelve 0.00 en los 984
## latidos de `dcb37c09`, con `cpu_render` variando normalmente al lado - y
## `gpu=0.00ms` se lee como un frame gratis, que es justo lo contrario de lo
## que pasa. El discriminador es esa pareja: si de verdad no se dibujara
## nada, `cpu_render` tambien estaria a cero.
const GPU_TIMING_UNSUPPORTED_ENTRIES := 12

## A census walks the whole scene tree, so it is far too expensive to do per
## frame - every 30s is enough to see a trend without becoming part of the
## problem it measures.
const CENSUS_SECONDS := 30.0
const CENSUS_ON_PROC_MS := 300.0

## How many 2D fill contributors `relleno=` names. Six fits the line and is
## more than enough: Safety Lullaby's five screens come from twenty-three
## items, and anything outside the top six is under a tenth of a screen.
const OVERDRAW_RANK := 6

## Progress fractions to report during a threaded load.
##
## Dense right after 0.50, because that is where the whole thing lives.
##
## The Collector's Shop loads in about 5s the first time in a session and
## 17-24s after that. Splitting 0.50-0.75 said the difference was all in
## that band; splitting it again said it is all in the first 5% of it:
##
##            0 -> 50%   50 -> 55%   55 -> 90%   total
##   cold      2253ms      2690ms       118ms     5062ms
##   warm      2216ms     14856ms        73ms    17147ms
##
## Same +72MB of VRAM across that band both times, and everything from 0.55
## to 0.90 finishes inside 100ms. So it is one chunk of the dependency list,
## uploading the same textures, taking 5.5x as long once the resource cache
## holds 21000 entries instead of 650 - a stall at a point, not a crawl.
##
## It also killed the note in this repo that blamed VRAM pressure: VRAM went
## from 625MB to 164MB with the ASTC work and the degradation did not move.
##
## 1% steps now, because at this resolution the answer is either one
## resource or a handful of them.
const LOAD_CHECKPOINTS: PackedFloat32Array = [0.25, 0.5, 0.51, 0.52, 0.53, 0.54, 0.55, 0.6, 0.75, 0.9]

const SUMMARY_MINUTES := 2.0

## Frame-time histogram buckets, in milliseconds, chosen around the vsync
## intervals of a 60Hz panel rather than around round numbers.
##
## median= and worst= cannot answer the question these were added for. Safety
## Lullaby and Chimera both report frame=33.30ms, and 33.30ms is exactly two
## vsync intervals at 60Hz - which has two completely different explanations
## that no counter in this log could separate:
##
##   a pacing lock - the frame misses its deadline by a hair, the compositor
##   holds it for the next interval, and every frame lands on 33.3ms whatever
##   the real work costs. The fix is to find the small overrun.
##
##   genuine load - the work really does take 25-40ms and the numbers scatter
##   across that range. The fix is to find the big cost.
##
## A histogram tells them apart on sight. Everything piled in one bucket with
## nothing on either side is a lock; a spread is load. The 20-28 bucket is the
## discriminator: it is the range no vsync-locked frame can land in.
const FRAME_BUCKET_EDGES: PackedFloat32Array = [12.0, 20.0, 28.0, 40.0, 60.0, 100.0]
const FRAME_BUCKET_LABELS: PackedStringArray = ["<12", "12-20", "20-28", "28-40", "40-60", "60-100", "100+"]

## How close to an exact multiple of the refresh interval a frame has to land
## to count as vsync-aligned. Half a millisecond either way of 16.67 is far
## tighter than any real workload holds by accident.
const VSYNC_TOLERANCE_MS := 0.7

var log_path: String = ""
var _log_dir: String = ""

var _file: FileAccess
var _frame_times: PackedFloat32Array
var _frame_index: int = 0
var _frames_seen: int = 0

## When the app was suspended, and for how long, so the frame that spans the
## resume can be told apart from a stall. See _notification().
var _paused_at_msec: int = 0
var _suspended_ms: int = 0

var _time_since_heartbeat: float = 0.0
var _time_since_spike: float = 999.0
var _time_since_census: float = 0.0
## VRAM as of the previous frame. A stall frame that also uploaded texture
## memory is a different problem from one that did not: the first is the GPU
## being fed, the second is pipeline compilation or plain processing. proc
## counts all idle work together and cannot separate them, so the delta is
## what distinguishes them.
var _last_vram: int = 0
## Previous entry's pipeline total, so each line can report its own delta.
var _last_pipelines: int = 0
## Entradas seguidas con `gpu` a cero mientras `cpu_render` no lo estaba, y
## el pestillo que se echa al pasar de GPU_TIMING_UNSUPPORTED_ENTRIES. Una vez
## echado no se vuelve a soltar: el driver no cambia dentro de una sesion.
var _gpu_zero_entries: int = 0
var _gpu_timing_unsupported: bool = false
var _last_frames_drawn: int = 0
var _last_frames_processed: int = 0

## Input events seen since the last entry, and when the last one arrived.
##
## This is the counter the 60/40 report needed and nobody had. The tester
## found that Monochrome settles at 40fps when you stop touching the hitbox
## and returns to 60 when you play again, and - the tell - that it does not
## happen while screen recording. Nothing in the game does that; it is
## Android's touch-boost DVFS raising the clocks while you touch and letting
## them fall while you do not. Every timing in this log is wall-clock
## milliseconds, so they all inflate together when the governor steps down,
## and SUMMARY vs_first cannot tell that apart from thermal throttling.
##
## idle= is seconds since the last input event. A quiet stretch measured at
## idle=8s and a busy one at idle=0.0s are not comparable numbers, and until
## now the log gave no way to know which kind a heartbeat was. It also puts
## a number on input activity itself: the shop's dead Back button showed up
## as forty MARK lines, which only exist because that one handler was
## instrumented by hand.
##
## Lower bound by construction: an autoload is an earlier sibling than the
## main scene, so anything that calls set_input_as_handled() before this
## runs is not counted. Good enough for "was the player touching the screen",
## which is the whole question.
var _in_touch: int = 0
var _in_key: int = 0
var _in_action: int = 0
var _in_other: int = 0
var _last_input_ms: int = 0

func _input(event: InputEvent) -> void:
	_last_input_ms = Time.get_ticks_msec()
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton:
		_in_touch += 1
	elif event is InputEventKey:
		_in_key += 1
	elif event is InputEventAction:
		_in_action += 1
	else:
		_in_other += 1
## Last graphics summary written, so SETTINGS only logs real changes.
var _last_graphics_summary: String = ""
var _last_memory: int = 0
var _peak_memory: int = 0
var _lowest_fps: int = -1
var _session_start_ms: int = 0

## Wall clock of the previous _process, which is what frame_ms is measured
## from. Zero until the first frame, where delta is the only thing available.
var _last_frame_usec: int = 0

## The wall-clock length of the previous frame, kept so timers added later feed
## off the same clock as the rest of the file. Every gate in here that counted
## `delta` instead went silent on exactly the frames it existed to catch.
var _last_frame_wall_ms: float = 0.0

var _scene_change_started_ms: int = 0

## The scene handed to change_scene_to_packed(), and when. Both only live for
## the handful of frames the swap takes; see _watch_swap().
var _swap_path: String = ""
var _swap_requested_ms: int = 0

## Writes the memory trace from its own thread. Null where /proc is not
## readable, which is everywhere that is not Linux or Android.
##
## preload rather than the class_name, and typed as RefCounted rather than as
## LullabyMemorySampler: a class_name only resolves once the global class cache
## has been rebuilt by an import, so annotating it here makes this file - the
## diagnostics log, the thing that is supposed to still work when nothing else
## does - fail to parse on a checkout that has not been imported yet.
const MemorySampler := preload("res://lullaby_mod/scripts/lullaby/debug/lullaby_memory_sampler.gd")

var _sampler: RefCounted = null
var _scene_change_memory: int = 0

## Brackets the frame's processing pass. This node runs first (see
## PROCESS_FIRST) and stamps the start; _ScriptTail runs last and measures
## the span.
##
## Read one frame behind on purpose, and that is not a rounding error: this
## node's _process is the first thing in the frame, so the only completed
## span available to it is the previous frame's - which is exactly the frame
## the `delta` it was handed describes. The two line up.
var _script_begin_usec: int = 0
var _script_usec: int = 0
var _script_peak_usec: int = 0

## What this node's own _process cost on the last frame, and on the frame
## that set the script_max record. Reported as self= so the diagnostics'
## share of rest= is a number rather than an argument.
var _self_usec: int = 0
var _peak_self_usec: int = 0

## Nodes in the running scene with _process enabled, counted in the same walk
## as the mixer list.
##
## rest= is the whole idle step minus the parts that are named, so the number
## of nodes that can contribute to it is a bound on the problem. Peepers was
## 256 _process callbacks firing while hidden and it took a shader counter to
## notice; a plain count would have said it outright.
var _process_nodes: int = 0

## What the scene was doing on the frame that set the script_max record: the
## sequence and its position, and how many mixers were running.
##
## Snapshotted at the same instant as the rest of the peak breakdown, because
## a spike attributed to "the census thirty seconds ago" is not attributed.
var _peak_seq: String = "-"
var _peak_players: int = 0
var _peak_trees: int = 0

## Every VisualInstance3D in the running scene, collected in the same walk as
## the mixers.
##
## Chimera costs 36.4ms of GPU against the shop's 14.7ms with fewer draw
## calls and the same primitive count, and every count-based explanation has
## died: not geometry, not lights, not shadows, not render scale. What has
## never been counted is how much of the 3D is actually on screen frame by
## frame - objs= is the engine's total for the whole frame including the
## SubViewports, not this scene's visible meshes.
var _visual3d_watch: Array[VisualInstance3D] = []

## Visible surfaces whose bound material is NOT opaque.
##
## Anything in ALPHA_SCISSOR discards, and a discard defeats early-Z on a tiled
## GPU: the fragment shader runs for every covered pixel whether or not
## something nearer already wrote it. Chimera's house has eight such materials
## and this project has never counted them, so "is it lights or is it
## overdraw" had no number on either side. GPUSPLIT below measures the second
## half in milliseconds; this says how much surface can cause it.
var _alpha_surface_count: int = 0

## GPUSPLIT: the same shot timed three ways, one frame each.
##
## The one measurement this project has needed all along and never had. `gpu=`
## is a single number for the whole frame, so "Chimera is per-fragment lighting"
## and "Chimera is 3D overdraw" both fit it and neither could be ruled out. The
## device can settle it itself: `Viewport.debug_draw` re-renders the same scene
## with the lighting removed (UNSHADED) or with every fragment reduced to a
## trivial additive blend (OVERDRAW), and
## `viewport_get_measured_render_time_gpu()` costs nothing to read.
##
##     base - unshaded   = what the per-fragment lighting maths costs
##     overdraw          = what rasterising that depth complexity costs at all
##
## No GPU->CPU readback anywhere, which is what made the old `sonda=` field
## expensive enough to delete: this only swaps an enum and reads a counter that
## is already being collected.
##
## Costs one visually wrong frame per sample - the player reported it as "un
## flash blanco opaco" in both 3D scenes, unprompted and without knowing it
## existed - which is why it is opt-in **per launch**: `Settings`'
## `diagnostics_gpu_split`, the row under Diagnostics Log in the console's Misc
## tab, deliberately unprefixed so save() never writes it and no install can
## come back up with it still on.
const GPU_SPLIT_SECONDS := 20.0

var _gpu_split_state: int = 0
var _time_since_gpu_split: float = 0.0
var _gpu_split_base: float = 0.0

## Which of the two debug passes this sample takes. Alternating instead of
## doing both in one cycle is what gets this down to **one** wrong frame per
## sample: each line is self-contained (base against one of the two) and the
## two halves interleave across a song.
var _gpu_split_overdraw_turn: bool = false

## SCRIPTSPLIT: the same frame timed twice, once with the animation mixers off.
##
## `rest=` is everything in the idle step that none of the named counters
## claim, and on Chimera it is the whole story - p50 5.24ms, p90 24.18ms, max
## 30.60ms, against notes= at p50 1.24 and this node's own share at 3.73. Its
## own docstring already says what to do about that: "if it is most of
## script_max, whatever owns the spike has still never been timed."
##
## Correlating it against everything the log already counts settles nothing.
## Over 45 Chimera heartbeats, `rest` against players playing is r=+0.26,
## against nodes with _process +0.14, against tweens -0.16, against bones
## -0.14. Not one of them explains it, which is the whole reason to measure
## instead of reason: the obvious suspect is 73 AnimationPlayers and 14
## AnimationTrees over 304 tracks, and the counters say the obvious suspect is
## not obviously it.
##
## So it borrows GPUSPLIT's method rather than inventing one. `sin_luz` works
## by rendering one frame with the lights gone and subtracting; this runs one
## frame with every AnimationMixer inactive and subtracts. The engine's
## animation step cannot be bracketed from GDScript - a mixer is an ordinary
## Node processing at its own priority, so no pair of probes isolates it - but
## it can be switched off, and a difference is a measurement.
##
## One frozen frame per sample: 1/60s with nothing animating, against the
## debug_draw switch GPUSPLIT already ships (which costs 40-68ms of shader
## variant compilation on its first sample in a scene). Offset half a period
## from it so the two never land on the same frame and neither measures the
## other.
const SCRIPT_SPLIT_SECONDS := 20.0

## Half a period out of phase with GPU_SPLIT_SECONDS, in milliseconds of
## credit, so the first sample of each lands ten seconds from the other's.
const SCRIPT_SPLIT_PHASE := 10000.0

var _script_split_state: int = 0
var _time_since_script_split: float = -SCRIPT_SPLIT_PHASE
var _script_split_base: float = 0.0

## The mixers this sample switched off. Stashed rather than re-activated
## wholesale, so the restore puts back exactly what was running instead of
## starting something the scene had deliberately stopped.
var _script_split_paused: Array[AnimationMixer] = []

## Physics ticks executed inside the last frame.
##
## A late frame asks for catch-up ticks and pays for all of them before it
## can present, so a 150ms frame at 30Hz can carry four physics steps that a
## 16ms frame does not. phys= reports the time but not the count, and the two
## answer different questions: 6ms across one tick is a heavy world, 6ms
## across four is a frame that was already late. max_physics_steps_per_frame
## was dropped 8 to 4 on exactly this reasoning and it was never measured.
var _last_physics_frames: int = 0
var _physics_steps: int = 0

## Microseconds a fixed amount of arithmetic took, sampled once per heartbeat.
##
## This is the counter every measurement in this project has needed and none
## has had. Two separate effects make wall-clock milliseconds lie in the same
## direction - Android's touch-boost governor drops the clocks when nobody is
## touching the screen, and thermal throttling drops them over a session - and
## SUMMARY vs_first cannot tell those apart from a scene that got heavier.
## This log's Chimera run reads vs_first=+44%: real, and unattributable.
##
## Fixed work, timed. If bench= rises by the same factor as script=, the scene
## did not change and the device did. Comparable only within one template -
## GDScript in a debug build runs arithmetic about 1.24x slower - so the
## header's `template :` line is what makes two logs comparable.
##
## 2000 iterations, not the 20000 this started at. Measured here: 20000 costs
## 1.08ms a run, which on a phone several times slower would put a spike on
## one frame every second - the exact instrument-perturbs-the-measurement
## mistake this counter exists to expose. 2000 measures 104us with p90/p50 at
## 1.19x and 104 counts of 1us resolution, which is enough to see a 1.5x clock
## change. It runs inside self=, so it is subtracted from rest= rather than
## silently inflating it.
const BENCH_ITERATIONS := 2000
var _bench_usec: int = 0
var _bench_sink: int = 0

## Nodes running _physics_process, counted alongside _process.
##
## A sweep of the repo found three users and none timing-critical, which is
## what justified halving the physics rate on the low presets - but that was a
## text search, not a measurement, and it cannot see a node the engine drives
## itself. procn= and physn= are the two halves of "how much can the main loop
## possibly be doing".
var _physics_nodes: int = 0

## Particle systems in the scene, 2D and 3D together.
##
## Never counted anywhere in this project, and one of the few things that can
## cost a whole frame on its own on a tile GPU. A hidden emitter still
## simulates unless one_shot or emitting is off, so live= counts what is
## visible and total= what exists.
var _particles_watch: Array[Node] = []

## Skeletons in the scene and the bones they carry.
##
## Hex alone is 113 bones with 2122 tracks across 18 animations. Skinning is
## paid per visible frame on both sides of the bus, and no counter in this log
## has ever mentioned it.
var _skeleton_bones: int = 0
var _skeleton_count: int = 0

## Distinct 3D materials across the scene's surfaces, against the surface
## count.
##
## This is the Peepers bug class asked about 3D. 128 eyes carried 128 unique
## ShaderMaterials that differed only in a value the shader used as a no-op,
## so nothing batched and the wall of eyes cost half of Monochrome's frame.
## Nothing would have found that faster than surfaces-versus-unique-materials
## in one line, and nothing in this log answers it for 3D.
var _surface_count: int = 0
var _material_count: int = 0
## What the worst frame since the last read was made of. Captured at the
## moment the record is beaten, so these describe one single frame rather
## than four independent maxima that may have happened on four different
## ones.
var _peak_note_usec: int = 0
var _peak_lane_usec: int = 0
var _peak_bounds_usec: int = 0
var _peak_pump_usec: int = 0
var _peak_char_usec: int = 0
var _peak_chars: int = 0

## When the previous entry was written, so per-interval counters can be
## reported as rates instead of as totals over an unknown window.
var _last_entry_ms: int = 0

## Priorities far outside anything gameplay uses, so this brackets every
## other node rather than landing in the middle of them.
const PROCESS_FIRST := -100000
const PROCESS_LAST := 100000

## Closes the bracket opened by the log's own _process. A separate node
## because process_priority orders whole nodes - one node cannot run both
## first and last.
##
## Its priority is set by the creator rather than in here: an inner class
## does not see the outer script's constants, and reading PROCESS_LAST from
## this scope would not resolve.
class _ScriptTail extends Node:
	var log_node: Node

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		if log_node == null:
			return
		log_node._close_script_bracket(Time.get_ticks_usec())


## Un punto de control dentro de la escena, para partir `rest=` por subarbol.
##
## `rest=` es el paso de proceso menos lo que tiene nombre, y en Chimera son 31
## de 32 ms. Los contadores que ya hay -notas, carriles, limites, pump,
## personajes- suman 2.4 ms entre todos, o sea que lo que cuesta no es nada de
## lo que alguien penso en medir. Un numero asi no se ataja adivinando: hay que
## poder decir QUE subarbol.
##
## Como: Godot llama `_process` en orden de arbol dentro de la misma
## `process_priority`, y todo el juego esta en la 0. Asi que una sonda colgada
## como ULTIMO hijo de un nodo de primer nivel corre despues de todos sus
## hermanos anteriores y de sus subarboles enteros. La diferencia entre dos
## sondas consecutivas es lo que costo lo que hay entre ellas.
##
## Por que no vale `process_priority` para esto, que seria mas limpio: ordena
## ANTES que el arbol, asi que solo sirve para abrir y cerrar el corchete
## -que es justo lo que ya hacen este nodo y `_ScriptTail`- y no para partirlo.
##
## Se cuelgan de la escena y mueren con ella. Un subarbol con el proceso
## apagado -lo que le hace `LullabyCutsceneVideo` a su cutscene- no estampa, y
## eso se distingue de "costo cero" porque el hueco se reporta como `-`.
class _ScriptProbe extends Node:
	var log_node: Node
	var slot: int = -1

	func _process(_delta: float) -> void:
		if log_node != null:
			log_node._stamp_probe(slot, Time.get_ticks_usec())


## Nombre de cada region y el instante en que su sonda corrio este fotograma.
##
## -1 = no corrio, que NO es lo mismo que cero: un subarbol en
## PROCESS_MODE_DISABLED no estampa.
var _probe_names: PackedStringArray = []
var _probe_at: PackedInt64Array = []

## El reparto por region del fotograma que gano el record, en microsegundos.
var _peak_regions: PackedInt64Array = []


func _stamp_probe(slot: int, now_usec: int) -> void:
	if slot >= 0 and slot < _probe_at.size():
		_probe_at[slot] = now_usec


## Cuelga una sonda al final de cada hijo de primer nivel de la escena.
##
## Solo de los que tienen algo que medir: un nodo sin descendientes con
## `_process` no puede aportar a `rest=`, y una sonda por cada uno solo alargaria
## la linea.
func _install_probes(scene: Node) -> void:
	_probe_names.clear()
	_probe_at.clear()
	if scene == null:
		return

	for child: Node in scene.get_children():
		if child is _ScriptProbe:
			continue
		if not _has_processing(child):
			continue
		var probe := _ScriptProbe.new()
		probe.name = "DiagProbe_%s" % child.name
		probe.log_node = self
		probe.slot = _probe_names.size()
		_probe_names.append(child.name)
		_probe_at.append(-1)
		child.add_child(probe)


## Si algo de este subarbol puede correr GDScript por fotograma.
func _has_processing(node: Node) -> bool:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_processing() or n.is_physics_processing():
			return true
		for c: Node in n.get_children():
			stack.append(c)
	return false


## El reparto del fotograma pico, listo para escribir.
func _regions_text() -> String:
	if _peak_regions.is_empty():
		return "-"
	var rows: Array = []
	for i: int in _peak_regions.size():
		rows.append([_peak_regions[i], _probe_names[i] if i < _probe_names.size() else "?"])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var out: PackedStringArray = []
	for row: Array in rows.slice(0, 6):
		if row[0] < 0:
			out.append("%s=-" % row[1])
		elif row[0] >= 100:
			out.append("%s=%.2f" % [row[1], row[0] / 1000.0])
	return " ".join(out) if not out.is_empty() else "(todo <0.1ms)"


func _close_script_bracket(now_usec: int) -> void:
	_script_usec = now_usec - _script_begin_usec

	# The record is kept on the frame minus this node's own share, not on the
	# frame. self= exists because rest= was the largest number in this log and
	# nobody had measured the instrument inside it; the first device log with
	# self= in it answered that, and the answer was that the instrument is
	# most of it - 8.47ms of a 10.67ms peak in Chimera, 10.44 of the shop's,
	# 16.82 during a load.
	#
	# That is not the log being slow on an ordinary frame. It is that the peak
	# resets at every heartbeat and the frame that writes the heartbeat is
	# inside the window it resets, builds a 1500-character line out of ninety
	# arguments, and wins the record by construction. So script_max= has been
	# describing the logging frame rather than the worst gameplay frame, every
	# time, and its breakdown named rest= for a cost that was self= all along.
	#
	# Ranking on the remainder fixes it without hiding anything: self= is
	# still reported, and the frame that now wins is the worst one the game
	# actually had. The 4% of SPIKEs that land within 120ms of a heartbeat
	# says the spike list was never affected by this - only script_max was.
	var game_usec: int = maxi(0, _script_usec - _self_usec)
	if game_usec <= _script_peak_usec:
		return

	# The frame that beats the record is the only one whose breakdown is
	# worth keeping. script_max= has been the biggest unattributed number in
	# this log for days - 19.52ms against a 4.76ms median - and the
	# sub-counters beside it are rates, which cannot hold a spike: an average
	# of 1.86ms/frame looks the same whether the cost is flat or whether one
	# frame in sixty costs everything. Snapshotting here turns that one
	# number into a list of names plus a remainder.
	_script_peak_usec = game_usec
	# This frame's, not the previous one's: this node runs first, so its own
	# _process has already finished and written _self_usec by the time the
	# tail node closes the bracket.
	_peak_self_usec = _self_usec
	_peak_seq = _sequence_state()
	var load_now: Array = _anim_load()
	_peak_players = load_now[0]
	_peak_trees = load_now[1]
	_peak_note_usec = RubiconLevelNoteHandler.frame_note_usec
	_peak_lane_usec = RubiconLevelNoteHandler.frame_lane_usec
	_peak_bounds_usec = RubiconLevelNoteHandler.frame_bounds_usec
	_peak_pump_usec = RubiconLevelNoteHandler.frame_pump_usec
	_peak_char_usec = RubiconCharacter.frame_process_usec
	_peak_chars = RubiconCharacter.frame_process_count

	# El reparto por region del MISMO fotograma, no de otro. Cada sonda estampo
	# cuando le toco; la region de una sonda es lo que va desde la anterior que
	# de verdad corrio -o desde la apertura del corchete- hasta ella.
	_peak_regions.resize(_probe_at.size())
	var prev: int = _script_begin_usec
	for i: int in _probe_at.size():
		var at: int = _probe_at[i]
		if at < 0:
			# No corrio: subarbol con el proceso apagado. Se marca y no se le
			# imputa el hueco a la region siguiente por error.
			_peak_regions[i] = -1
			continue
		_peak_regions[i] = maxi(0, at - prev)
		prev = at

## While a load is in flight, its path and which progress checkpoints have
## already been reported. A SCENE_IN of 18726ms says the load is the problem
## but not which part of it - these turn one number into a curve, so a load
## that crawls to 40% and then finishes instantly reads differently from one
## that is slow all the way through.
var _loading_path: String = ""
var _load_checkpoints_done: int = 0

## How often to sample a load in flight, and when the last sample went out.
const LOADING_ENTRY_MS := 1000
var _last_loading_entry_ms: int = 0

## The incoming scene's dependency graph, and which of its paths were already
## in the loader cache at the previous sample.
##
## This is the counter the load stall needs, and the per-second LOADING
## samples are what showed it was needed. The shop's second load sits at
## exactly 50.0% for fifteen consecutive seconds with VRAM flat at 112MB and
## res moving +3 a second - it is not uploading slowly, it is doing nothing
## at all - and then finishes in one burst. Chimera does the same for eleven
## seconds at 170MB. Same duration in two scenes of very different size, so
## it is a fixed cost, and the fraction being pinned to one value says the
## loader is inside a single dependency.
##
## Godot exposes no way to ask which one. But has_cached() answers it from
## the outside: walk the incoming scene's graph, sample which paths are
## cached once a second, and the paths that flip from uncached to cached on
## the sample the stall ends are the ones it was stuck on. Named in the
## LOADING line as `+name.ext` so the log reads as a timeline of what
## arrived when.
var _incoming_deps: PackedStringArray = PackedStringArray()
var _incoming_cached: Dictionary = {}

## The paths of _incoming_deps that were still uncached at the last sample.
##
## The per-second probe used to re-walk the whole list every time, which is
## the wrong shape twice over: it re-asks about paths whose answer can no
## longer change, and it costs the same at the end of a load as at the start,
## when by then there is almost nothing left to find. This shrinks instead,
## so the probe gets cheaper exactly as the load gets busier.
var _incoming_pending: PackedStringArray = PackedStringArray()

## What every probe in this file has cost so far on the current load, in
## microseconds, and how long the two graph walks took.
##
## This exists because a device log could not answer whether these probes
## were free. The shop's first load in the release APK took 38.0s against
## 5.6s for the same scene in the last debug APK, and six commits separate
## those two builds - three of them touching the shop, one adding the walks
## below - so "the probe did it" and "the release template did it" were both
## guesses with nothing to separate them. Measuring what the probe costs is
## cheaper than another A/B build, and settles it in whichever log comes
## next: if `probe=` reads tens of milliseconds, the probe is not the 32
## seconds and the search moves on.
var _probe_usec: int = 0
var _incoming_walk_usec: int = 0
var _residue_walk_usec: int = 0

## The same total, split by which walk spent it - because `probe=` alone
## cannot answer the only question anyone asks of it.
##
## 10152-665dedd4 reports probe=1507.3ms on a 17588ms Chimera load, and the
## obvious reading ("8.6% of the load is the diagnostics") is not supported by
## anything: three different walks feed that number and the RETAINED sweep,
## another 597ms on the same load, is not even in it. Capping the total on
## that reading would have been an optimisation aimed at a number nobody had
## broken down - and the note above PROBE_BUDGET_USEC already records what
## happens when this walk is capped without care (deps=111/112 on a graph of
## 512, every uncounted path below the cut).
##
## There is also a reason to expect the whole reading is wrong: all of this
## runs in _process, on the main thread, while load_threaded_request works on
## a WorkerThreadPool thread, on a phone with 8 cores. It spends the loading
## screen's frame budget, which is a real cost and a *different* one from
## making the load take longer. The next log settles it: if `graph=` is most
## of it, the BFS over get_dependencies() is the thing to bound; if `prog=`
## is, the per-sample has_cached() pass is; and either way `sweep=` is now
## alongside instead of hidden.
var _probe_walk_usec: int = 0
var _probe_progress_usec: int = 0
var _probe_residue_usec: int = 0

## Wall-clock ceiling on either graph walk, per frame, in microseconds.
##
## Both run on the main thread and read a file header per path - which for an
## imported resource means parsing its .import too. A cap on the number of
## paths does not bound that, because the per-path cost is a device-side
## unknown; a cap on time does. Truncation is reported, so a short answer
## never reads as a complete one.
##
## 8ms, down from 120ms. The device log made that number indefensible. probe=
## exists to say what the diagnostics cost the load they measure, and on its
## first run it said:
##
##     warning    took= 1236ms   probe=  31.8ms    2.6%
##     intro      took= 1500ms   probe=  94.4ms    6.3%
##     shop       took= 5225ms   probe= 706.3ms   13.5%
##     Chimera    took=17342ms   probe=1670.1ms    9.6%
##
## 1.67 seconds of a Chimera load spent measuring it. The budget was a
## per-frame ceiling and the walk resumes across frames, so a load lasting
## tens of seconds could spend 120ms on every one of them - four frames' worth
## of time per frame, on the frames a loading screen is trying to animate.
##
## At 8ms the walk takes more frames and finishes later, or reports (capped)
## on a short load. That is the right trade: deps= is a diagnostic, and a
## diagnostic that costs a tenth of the thing it diagnoses is not measuring
## it, it is changing it.
const PROBE_BUDGET_USEC := 8_000

## Consecutive LOADING samples that reported the same progress fraction, and
## when the run of them started.
##
## The curve is readable but nobody should have to read sixteen lines to see
## that eleven of them are identical. STALL reports the window once, when it
## breaks, with how long it lasted and how many dependencies arrived in the
## meantime - a load that goes quiet for eleven seconds and then lands 424
## resources in one sample is a completely different bug from one that
## crawls, and this says which happened in one line.
const STALL_SAMPLES := 3
var _stall_fraction: float = -1.0
var _stall_since_ms: int = 0
var _stall_samples: int = 0
var _stall_cached_at_start: int = 0

## Reports a run of identical progress samples, if it was long enough.
##
## Called both when the fraction moves and when the load finishes, and the
## second caller is the one that matters: the shop pins at exactly 50.0% and
## then completes, so the run never "breaks" - it ends. Emitting only on a
## change meant the one case this was built for produced no STALL line at
## all, which a 20000-node test load caught by sitting at 0.0% for 71
## samples and finishing silently.
func _flush_stall(now_ms: int, cached_now: int) -> void:
	if _stall_samples < STALL_SAMPLES:
		return
	_entry("STALL", "%.1f%% for %.1fs, %d deps arrived while stuck" % [
		_stall_fraction * 100.0,
		float(now_ms - _stall_since_ms) / 1000.0,
		cached_now - _stall_cached_at_start,
	])
	_stall_samples = 0

## Names for ResourceLoader.ThreadLoadStatus, checked against the binary
## rather than assumed: 0 INVALID_RESOURCE, 1 IN_PROGRESS, 2 FAILED,
## 3 LOADED.
const THREAD_STATUS_NAMES := ["invalid", "in_progress", "failed", "loaded"]

## Cap on the incoming-graph walk, same reasoning as RESIDUE_MAX_PATHS: this
## runs once per scene change, on the frame the loading screen goes up.
const INCOMING_MAX_PATHS := 1200

## Collects the paths the incoming scene depends on, breadth-first.
##
## Runs against the file rather than the loaded resource, so it works before
## anything has been loaded - which is the whole point, since the answer is
## needed while the load is still in flight.
func _collect_incoming_deps(path: String) -> void:
	_incoming_deps = PackedStringArray()
	_incoming_cached.clear()
	_incoming_pending = PackedStringArray()
	_incoming_walk_usec = 0
	if path.is_empty():
		return

	_walk_seen = {path: true}
	_walk_queue = [path]
	_continue_incoming_walk()

## Resumable state for the walk above.
##
## The walk used to stop dead at PROBE_BUDGET_USEC, and on the Collector's
## Shop it did: walk=120.1ms (capped) with 112 paths found, out of a graph
## that is really 512 files. Those 112 are the shallowest, so the log could
## report "111 of 112 cached" while the load still had sixteen seconds and
## three hundred resources left to go - all of them below the cut, none of
## them nameable. Reading that as one slow dependency was wrong, and there
## was no way to tell from the log.
##
## Same budget per frame, but the queue survives to the next one, so the walk
## finishes over a few frames of a load that lasts tens of seconds and the
## denominator becomes the real graph.
var _walk_seen: Dictionary = {}
var _walk_queue: Array[String] = []

## How long one pass of the walk may take. A variable rather than the constant
## so a test can shrink it and prove the walk really does resume - with a full
## budget and warm dependency headers the whole graph fits in a single pass,
## so the resumable path would otherwise never be exercised.
var probe_budget_usec: int = PROBE_BUDGET_USEC

func _continue_incoming_walk() -> void:
	if _walk_queue.is_empty():
		return

	var started: int = Time.get_ticks_usec()
	while not _walk_queue.is_empty() and _incoming_deps.size() < INCOMING_MAX_PATHS:
		if Time.get_ticks_usec() - started > probe_budget_usec:
			break
		var current: String = _walk_queue.pop_front()
		_incoming_deps.append(current)
		_incoming_pending.append(current)
		for dep in ResourceLoader.get_dependencies(current):
			var dep_path: String = dep.get_slice("::", dep.count("::"))
			if dep_path.is_empty() or _walk_seen.has(dep_path):
				continue
			_walk_seen[dep_path] = true
			_walk_queue.append(dep_path)

	if _walk_queue.is_empty():
		_walk_seen.clear()

	_incoming_walk_usec = Time.get_ticks_usec() - started
	_probe_usec += _incoming_walk_usec
	_probe_walk_usec += _incoming_walk_usec

## How many of the incoming scene's dependencies are cached now, and which
## ones arrived since the last sample.
func _incoming_progress() -> String:
	if _incoming_deps.is_empty():
		return "deps=-"

	var started: int = Time.get_ticks_usec()
	var arrived: Array[String] = []
	var owners_this_tick: Array[String] = []
	# Only the paths that were still uncached last time. A cached resource
	# cannot go back to uncached while the load that wants it is in flight,
	# so re-asking is work whose answer is already known - and the list this
	# walks shrinks by exactly the count that just arrived.
	var still_pending: PackedStringArray = PackedStringArray()
	for path in _incoming_pending:
		if not ResourceLoader.has_cached(path):
			still_pending.append(path)
			continue
		_incoming_cached[path] = true
		# Charged to the folder two levels down, which is what names a
		# subsystem: "console" and "collector_shop" rather than 397 filenames.
		# The shop opens 397 files in 17.9s where Monochrome opens 197 in 4.2s
		# with more megabytes, so the cost is per file and the useful question
		# is which part of the scene owns the files.
		owners_this_tick.append(_dep_owner(path))
		if arrived.size() < 4:
			arrived.append(path.get_file())
	_incoming_pending = still_pending

	# The interval is split between everything that arrived in it, not given
	# to each of them.
	#
	# Charging the full interval per dependency was the first attempt and the
	# device log made the error obvious: a 4.8 second load reported
	# assets/collector=188.5s across 186 dependencies. Every subsystem's total
	# then scales with its dependency count, which is a number already
	# available statically - so it measured the one thing it was built to look
	# past. Split, the totals add up to the load.
	var interval: float = float(Time.get_ticks_msec() - _dep_clock)
	if not owners_this_tick.is_empty():
		var share: float = interval / float(owners_this_tick.size())
		for owner in owners_this_tick:
			_dep_ms[owner] = float(_dep_ms.get(owner, 0.0)) + share
			_dep_count[owner] = int(_dep_count.get(owner, 0)) + 1
	_dep_clock = Time.get_ticks_msec()
	var progress_usec: int = Time.get_ticks_usec() - started
	_probe_usec += progress_usec
	_probe_progress_usec += progress_usec

	return "deps=%d/%d%s" % [
		_incoming_cached.size(), _incoming_deps.size(),
		"" if arrived.is_empty() else " +" + " +".join(arrived),
	]

## The scene being left, and whether its cache residue has been reported for
## this load yet.
##
## res= (Performance.OBJECT_RESOURCE_COUNT) does not come back down after
## Monochrome. Measured across one session: the Collector's Shop runs at
## res=1880, Monochrome takes it to 23548, and the *next* shop load starts
## from res=21047 and settles at 22650 - about 21000 resources outliving the
## scene that created them, with orphans back at 2, so the nodes were freed
## and their resources were not. The same load then took 18.0s against 5.6s
## cold, all of it in one band, uploading 83MB of VRAM at 5.2MB/s where the
## cold load managed 18MB/s.
##
## That is the "loads get slower within a session" problem, and it is not
## VRAM pressure - VRAM went 625MB to 164MB with the ASTC work and this did
## not move. The question left is what still holds those resources, and the
## cheapest read on it is whether the outgoing scene's own PackedScene, and
## the resources it depends on, are still in the loader cache one second
## after the tree that used them was unloaded.
## Wall time charged to each subsystem while its dependencies arrived, and how
## many arrived. Reset per load; reported on SCENE_IN.
##
## The interval between two polls is charged to whatever arrived in it, which
## over-charges when several land together and under-charges nothing. It is a
## ranking, not a stopwatch - enough to say whether the console's 97 files are
## really a quarter of the shop's 17.9 seconds before anyone refactors it out.
var _dep_ms: Dictionary = {}
var _dep_count: Dictionary = {}
var _dep_clock: int = 0

var _outgoing_scene_path: String = ""
var _residue_reported: bool = true

## Hard cap on the RESIDUE walk. A song's graph is thousands of paths and
## this runs on a frame that is already loading; the entry says when it hit
## the cap so a truncated count is never read as a whole one.
const RESIDUE_MAX_PATHS := 1500

## The animation that started most recently, and when. A SPIKE already
## reports how bad a frame was; this says what had just begun. The first
## device log could only correlate the two by eye - a census happened to
## catch SequencePlayer/122_fall near a 2837ms stall - which is enough to
## form a suspicion and not enough to confirm one. Recorded on every
## AnimationPlayer in the scene and quoted directly in the spike line.
var _last_anim: String = ""
var _last_anim_ms: int = 0
var _watched_players: Array[AnimationPlayer] = []

## Every SubViewport in the current scene, with GPU timing switched on.
##
## gpu= only ever covered the MAIN viewport - RenderingServer measures per
## viewport RID, and get_viewport() on an autoload is the root window - so a
## scene doing much of its rendering into SubViewports read as "the GPU is
## fine, this is CPU" when it was neither. The Collector's Shop is exactly
## that case: thirteen spikes at frame=68-141ms with gpu pinned at 13.5ms
## and byte-identical draw/prims/objs, because the console's own 1440x1080
## 3D background viewport was never part of that number.
##
## Refreshed on scene change and on every census rather than per entry: the
## walk is the same one _watch_animations() does and a spike burst must not
## pay for it.
var _sub_viewports: Array[SubViewport] = []

## Long-run FPS buckets, one per SUMMARY_MINUTES. Thermal throttling does not
## announce itself - it looks like the same scene getting slower for no
## reason - so the only way to see it is to compare the same measurement
## against itself over time.
## Class counts from the previous census of the current scene, for delta=[].
## Cleared on scene change so the first census of a scene never diffs against
## a different one.
var _last_census_counts: Dictionary = {}

var _bucket_frames: int = 0
var _bucket_ms_total: float = 0.0
var _bucket_worst_ms: float = 0.0
var _time_since_summary: float = 0.0
var _first_bucket_median: float = 0.0

## Frame-time histogram for the interval since the last HEARTBEAT, plus how
## many of those frames landed on an exact multiple of the refresh interval.
var _frame_hist: PackedInt32Array = PackedInt32Array()
var _hist_frames: int = 0
var _hist_aligned: int = 0

## The panel's refresh interval in milliseconds, read once at boot.
##
## Hardcoding 16.67 would have made the histogram lie on any 90Hz or 120Hz
## phone, and "everything is aligned" is exactly the kind of wrong answer that
## reads as a finding. screen_get_refresh_rate() returns a negative value when
## the platform does not know, which is what the fallback covers.
var _refresh_hz: float = 60.0
var _refresh_ms: float = 1000.0 / 60.0

## Whether the log is actually running, as opposed to merely existing.
##
## An autoload is ready before the first scene, so the old shape - read the
## setting once and return - meant a log switched on afterwards could never
## start. That is exactly the case the first-boot row creates.
var _running: bool = false

## Whether the one-time wiring has been done. See _start_logging.
var _wired: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = PROCESS_FIRST

	# Before the gate, not after it. This connection used to sit at the end of
	# _ready, past the early return, so an autoload that started with the log
	# off never heard about the setting changing and could not be woken by
	# anything short of a relaunch. The whole point of the row on the boot
	# screen is that it takes effect on this launch.
	if Settings.has_signal("applied"):
		Settings.applied.connect(_on_settings_applied)

	if not Settings.lullaby_diagnostics_log:
		set_process(false)
		return

	_start_logging()

## Opens the file and wires everything that only makes sense while logging.
##
## Split out of _ready so it can also run later, when the setting is turned on
## mid-session. Everything in here is idempotent-guarded by _running.
func _start_logging() -> void:
	if _running:
		return

	if not _open_log():
		set_process(false)
		return

	_running = true
	set_process(true)

	# Everything below wires the node up, and only the first start may do it:
	# off -> on -> off -> on is reachable from two rows now, and running it
	# twice would add a second _ScriptTail (two brackets around every frame's
	# script timing) and connect ErrorHandler and SceneChanger again, so one
	# error would be logged twice. The file itself is reopened every time,
	# which is the part that has to repeat.
	if _wired:
		_write_header()
		return
	_wired = true

	# Opt-in and cheap (a couple of GPU timestamp queries the driver already
	# supports), but off by default in Godot - without it gpu=/cpu_render=
	# below would just silently read 0 forever, which looks exactly like "GPU
	# idle" and would have been a lie. Only exposed on RenderingServer by
	# viewport RID, not as a Viewport instance method - confirmed in an
	# isolated project after the instance-method call errored on Window.
	#
	# Y encenderlo no garantiza que el driver conteste: hay teléfonos donde la
	# consulta de GPU devuelve 0.00 para siempre con `cpu_render` funcionando
	# al lado. Eso lo detecta `_gpu_timing_unsupported` unas entradas despues
	# y a partir de ahi el campo sale como `n/d` en vez de como un cero.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	var tail := _ScriptTail.new()
	tail.name = "ScriptTail"
	tail.log_node = self
	tail.process_priority = PROCESS_LAST
	add_child(tail)

	_frame_times.resize(WINDOW_SIZE)
	_frame_times.fill(0.0)
	_frame_hist.resize(FRAME_BUCKET_LABELS.size())
	_frame_hist.fill(0)

	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz > 0.0:
		_refresh_hz = hz
		_refresh_ms = 1000.0 / hz

	_session_start_ms = Time.get_ticks_msec()
	_last_entry_ms = _session_start_ms
	_last_memory = OS.get_static_memory_usage()
	_peak_memory = _last_memory
	_last_vram = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))

	_write_header()

	# ErrorHandler is an autoload declared before this one, so it already
	# exists. Both of its entry points are routed here so a crash screen the
	# player dismisses still leaves a record behind.
	if ErrorHandler.has_signal("logged"):
		ErrorHandler.logged.connect(_on_error_logged)

	# And everything ErrorHandler never sees, which is almost everything: every
	# push_error/push_warning and every red error the engine raises. ErrorLog
	# catches those through OS.add_logger() and writes its own always-on file;
	# this puts the same error on THIS timeline, which is the half its file
	# cannot have - "at 60.8s, in the middle of the shop's precache" is what
	# turns an error message into a diagnosis.
	#
	# Declared before this autoload, so it exists. Only first occurrences
	# arrive - ErrorLog counts repeats rather than re-emitting them, so an
	# error firing every frame cannot flood this log either.
	if ErrorLog.has_signal("captured"):
		ErrorLog.captured.connect(_on_error_captured)

	if SceneChanger.has_signal("scene_change_started"):
		SceneChanger.scene_change_started.connect(_on_scene_change_started)
	if SceneChanger.has_signal("scene_change_finished"):
		SceneChanger.scene_change_finished.connect(_on_scene_change_finished)

	# The header records the graphics settings once, at boot - which is before
	# first_boot_settings runs and before the player can touch anything. A log
	# whose header says "High" while the session actually ran on something
	# else is worse than no record at all: it was read as ground truth and
	# sent a whole investigation down the wrong path. Every change is logged
	# again through _on_settings_applied, which is connected in _ready now
	# rather than here, so it is heard even when the log starts switched off.

func _process(delta: float) -> void:
	# Opens the bracket _ScriptTail closes. First statement on purpose: this
	# node has the lowest process_priority in the tree, so everything else
	# that runs this frame runs after this line.
	_script_begin_usec = Time.get_ticks_usec()

	# Y se borran las marcas del fotograma anterior, en el mismo sitio y por la
	# misma razon: si una sonda no corre este fotograma su hueco tiene que salir
	# como `-`, no como la marca vieja, que daria una region negativa o un
	# reparto inventado.
	for i: int in _probe_at.size():
		_probe_at[i] = -1

	# Wall clock, not delta.
	#
	# Godot's process delta is smoothed and clamped, and above roughly 50ms it
	# stops describing the frame at all. Measured against this exact build with
	# OS.delay_msec(): a 300ms frame arrives as 53.1ms, a 1200ms frame as
	# 80.9ms, and a 5000ms frame as 66.7ms - not a ceiling, just unrelated to
	# the truth.
	#
	# Everything shaped from it was therefore fiction wherever it mattered
	# most. The device log's SUMMARY reported worst=166.7ms for a session that
	# contained a measured 11,489ms frame; hist= sorted stalls into buckets
	# that could not hold them, and SPIKE understated every one of the 99 it
	# found. The structural numbers in that log are sound because they come
	# from Time.get_ticks_msec() deltas - took=, the swap marks, the reveal -
	# but every frame-shape statistic was reading a number Godot never
	# promised.
	_step_gpu_split()
	_step_script_split()

	var physics_now: int = Engine.get_physics_frames()
	_physics_steps = physics_now - _last_physics_frames
	_last_physics_frames = physics_now

	var now_usec: int = Time.get_ticks_usec()
	var frame_ms: float = float(now_usec - _last_frame_usec) / 1000.0 if _last_frame_usec > 0 else delta * 1000.0
	_last_frame_usec = now_usec
	_last_frame_wall_ms = frame_ms

	# The frame that spans a resume is the suspension, not a stall, and it has
	# to be caught here - before the median buffer, fps_low, the spike test or
	# SUMMARY's worst= have seen it. See _notification() for why: five of these
	# across three devices, up to 71.7 seconds, every one of them the OS and
	# not the game.
	#
	# The clock is re-armed on the way out so the FOLLOWING frame is not
	# measured from before the suspension either.
	if _suspended_ms > 0:
		_entry("SUSPEND", "la app estuvo suspendida %.1fs (el frame que la cruza mide %.1fms y no es un stall)" % [
			_suspended_ms / 1000.0, frame_ms,
		])
		_suspended_ms = 0
		_last_memory = OS.get_static_memory_usage()
		_last_frame_usec = Time.get_ticks_usec()
		return

	var median: float = _median_frame_ms()
	_frame_times[_frame_index] = frame_ms
	_frame_index = (_frame_index + 1) % WINDOW_SIZE
	_frames_seen += 1

	var fps: int = int(round(1000.0 / maxf(frame_ms, 0.1)))
	if _lowest_fps < 0 or fps < _lowest_fps:
		_lowest_fps = fps

	var memory: int = OS.get_static_memory_usage()
	if memory > _peak_memory:
		_peak_memory = memory

	_record_frame_shape(frame_ms)

	# Wall clock, for the same reason frame_ms is - and this half was missed
	# when 473788e fixed the other one.
	#
	# Every timer below gates something the log emits, and delta stops
	# describing the frame above ~50ms (see the note at the top of this
	# function: a 5000ms frame arrives as 66.7ms). So on exactly the frames
	# worth reporting, these clocks barely advance, and the gates they feed
	# stay shut.
	#
	# It cost the worst frame in the project. In 10152-665dedd4 the shop's
	# first precache contains a single frame of 7787.6ms - SUMMARY caught it,
	# because _bucket_worst_ms is fed from frame_ms - and there is **no SPIKE
	# line for it**: _time_since_spike had gained about 66ms of credit for
	# 7.8 seconds of wall clock and was still inside SPIKE_COOLDOWN_SECONDS.
	# The heartbeat missed it the same way, 30.57s to 44.09s with
	# HEARTBEAT_SECONDS at 5, and again 84.19s to 95.68s across Chimera's.
	#
	# So the log went quiet across both of the longest stalls it has ever
	# been pointed at. Feeding these from the clock costs nothing - frame_ms
	# is already computed - and makes a stall report itself.
	var frame_s: float = frame_ms / 1000.0

	_time_since_heartbeat += frame_s
	_time_since_spike += frame_s

	# Two ways in. The ratio test needs a full window before the median means
	# anything - otherwise the first frames after a load all read as spikes
	# against a near-empty buffer - but a frame past SPIKE_ALWAYS_MS is
	# reported whatever the window thinks. See that constant for what the
	# window-only gate cost: two device logs, two multi-second frames, no
	# SPIKE line for either.
	var warmed: bool = _frames_seen > WINDOW_SIZE
	var huge: bool = frame_ms >= SPIKE_ALWAYS_MS
	if (warmed or huge) and _time_since_spike >= SPIKE_COOLDOWN_SECONDS:
		if huge or (frame_ms >= SPIKE_MIN_MS and frame_ms >= median * SPIKE_FACTOR):
			_time_since_spike = 0.0
			var vram_now: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
			var vram_delta: float = float(vram_now - _last_vram) / 1048576.0
			var since_anim: int = Time.get_ticks_msec() - _last_anim_ms
			var blame: String = ""
			# Only worth quoting if it started essentially on this frame -
			# anything older is coincidence, not cause.
			if not _last_anim.is_empty() and since_anim <= 250:
				blame = "  after %s (%dms ago)" % [_last_anim, since_anim]
			# "(sin ventana)" because during the warmup `median` is the 16.6
			# fallback from _median_frame_ms(), not a measurement - so the
			# multiplier next to it is against an assumption, and a reader
			# comparing two SPIKE lines needs to know which is which.
			_entry("SPIKE", "frame=%.1fms median=%.1fms (%.1fx)%s vram_delta=%+.1fMB%s" % [
				frame_ms, median, frame_ms / maxf(median, 0.001),
				"" if warmed else " (sin ventana)", vram_delta, blame,
			])
			# A stall this long is not jitter, it is work. Worth paying for a
			# census on the spot to see what was in the scene when it happened.
			if Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 >= CENSUS_ON_PROC_MS:
				census("after %.0fms stall" % frame_ms)

	var grew_mb: float = float(memory - _last_memory) / 1048576.0
	if grew_mb >= MEMORY_JUMP_MB:
		_entry("MEMORY", "+%.1f MB in one frame" % grew_mb)
	_last_memory = memory
	_last_vram = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))

	_poll_load_progress()

	_bucket_frames += 1
	_bucket_ms_total += frame_ms
	if frame_ms > _bucket_worst_ms:
		_bucket_worst_ms = frame_ms

	_time_since_summary += frame_s
	if _time_since_summary >= SUMMARY_MINUTES * 60.0:
		_time_since_summary = 0.0
		_write_summary()

	# Every frame on purpose: a 30 second census cannot see a blackout that
	# lasts ten. The list is short, so this is a handful of reads.
	_poll_blackouts()

	_time_since_census += frame_s
	if _time_since_census >= CENSUS_SECONDS:
		_time_since_census = 0.0
		census("periodic")

	if _time_since_heartbeat >= HEARTBEAT_SECONDS:
		_time_since_heartbeat = 0.0
		# Before the entry is written, so bench= describes the same moment the
		# rest of the line does. Counted in self=, like everything else here.
		_run_bench()
		_entry("HEARTBEAT", "fps_now=%d fps_low=%d median=%.1fms %s %s" % [
			fps, _lowest_fps, median, _take_frame_shape(), _light2d_summary(),
		])
		_lowest_fps = -1

	# Last statement, so this covers everything above it - including
	# _poll_blackouts(), which walks the watch list every frame, and the
	# census and heartbeat writes when they land on this one.
	#
	# script= brackets the whole idle-process step, so this node's own work
	# is inside the number it reports and has been landing in rest= unnamed.
	# rest= is Chimera's entire CPU cost - 14.64ms median and 45.20ms at p90
	# against notes at 1.27 and chars at 0.08 - so an unmeasured term inside
	# it is exactly the thing that cannot be left as an assumption. Same
	# mistake shape as the load probe: measure the instrument before reading
	# what the instrument says.
	_self_usec = Time.get_ticks_usec() - _script_begin_usec

## A one-off inventory of what the running scene actually contains. This is
## the entry that answers "why is proc 50ms when draw calls are 120" - the
## per-frame counters say the GPU is idle and something in processing is not,
## but not what. The census names the candidates.
##
## The animation figures are the reason it exists. Restoring ~3305 bone tracks
## that had been silently dropped (they referenced Blender dot-names the .gltf
## exports with underscores) fixed the Collector's and Hex's hands, but a
## dropped track costs nothing and a resolved one is evaluated every frame -
## so that fix is the leading suspect for Chimera's frame time, and this
## measures it instead of guessing. anim_tracks is the total across every
## playing AnimationPlayer; the heaviest few are named individually.
func census(reason: String) -> void:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null or _file == null:
		return

	# Cheap here (the census already walks the whole tree) and it picks up
	# SubViewports that a sequence instantiated after the scene loaded.
	_refresh_sub_viewports()

	var counts: Dictionary = {}
	var players: Array[AnimationPlayer] = []
	# 122_fall's stall lands within a second of two lights turning on
	# (Camera3D/OmniLight3D, Environment/Lights/TvLight, both shadow casters).
	# Godot exposes no shadow-atlas counter, so this is the closest indirect
	# read: how many shadow-casting lights are actually live right now. If
	# this jumps on the same census that catches a stall, a new shadow caster
	# is the leading suspect; if it is already flat well before the stall,
	# that theory is dead and the search moves on - same logic as pipe=.
	## Screen area covered by everything visible, in pixels, and what the
	## single biggest contributor is.
	var overdraw_px: float = 0.0
	var overdraw_items: int = 0
	var overdraw_top_px: float = 0.0
	var overdraw_top: String = ""
	## The biggest contributors, not just the biggest one.
	##
	## `over=` has been the most useful number in this log for 2D scenes and the
	## least actionable. Safety Lullaby measures `gpu=32.48ms` against Chimera's
	## `15.27ms` while drawing 592 primitives to Chimera's 15645 and no 3D at
	## all; the only counter that separates them is `over=5.0x` against `1.1x`,
	## and across the two pure-2D scenes in that log the slope is about 8ms of
	## GPU per screen of 2D fill at 1600x720. So four wasted screens is the
	## whole song's frame budget - and the line named exactly one of them.
	##
	## Named with its alpha, because the trap here is specifically the item that
	## costs a full screen and shows nothing. A ColorRect at `color.a = 0` is
	## still rasterised and still blended; this project has it measured, in
	## `trance_shaders.gd`, at 20.0ms for the identity pass against 6.7ms hidden
	## - and `_alpha_is_knowable()` says when the number cannot be trusted.
	var overdraw_rank: Array = []
	## Visible, opaque, full-frame CanvasItems, deepest last - which is
	## roughly draw order, so the last one named is the one on top.
	var covers: Array[String] = []
	## Screen-covering drawing items whose own pixel alpha the census cannot
	## read - see UNKNOWN_COVERAGE.
	var covers_maybe: Array[String] = []
	var lights_visible: int = 0
	var lights_shadow: int = 0

	## 2D lights, which no counter in this log has ever seen.
	##
	## `lights=` is Light3D only, so Safety Lullaby - a scene with five
	## PointLight2D on stage - reports `lights=0(shadow=0)` on every census. And
	## `over=` cannot cover for it, because a light is not an item: Godot's
	## canvas renderer draws each affected CanvasItem **again, once per light**,
	## so a screen-covering Light2D doubles the fill of everything it touches
	## while adding nothing to the item count.
	##
	## That gap is the current suspect for the song's 32.48ms of GPU on 592
	## primitives. The two pure-2D scenes in log d67addb8 do not lie on one line:
	## credits `over=2.0x -> gpu 7.41ms` against Safety `over=5.0x -> 32.48ms`
	## is 2.5x the items and 4.4x the GPU, and the alley authors one light whose
	## texture is 1049x480 at `texture_scale = 4.0` - a 4196x1920 rect over a
	## 1920x1080 stage - plus two more around 900x700.
	##
	## Reported as count, how many of them reach the frame, and the worst
	## offenders by screen coverage with the number of items each one is masked
	## to pair with. Coverage rather than a plain count because a lamp lighting
	## a doorway and a gradient covering the whole stage are the same node type
	## and nothing like the same cost.
	var lights2d_total: int = 0
	var lights2d_live: int = 0
	var lights2d_rank: Array = []
	# Every prior census of Chimera happened to land during a cutscene, where
	# "playing" AnimationPlayers sat at 5-17 - nowhere near the ~240 the
	# 40-notes-on-screen x 6-AnimationPlayers-each theory implies. That
	# theory is not dead, it was never actually tested: Note.tscn drives 4 of
	# its 6 AnimationPlayers through an AnimationTree state machine, which
	# does not call play() on them and so never shows up as "playing" here -
	# an AnimationTree can be doing real per-frame blend work while every
	# AnimationPlayer beneath it reads is_playing()==false. trees_active
	# and notes_visible are the two counters that were missing to actually
	# catch a dense-note moment instead of another cutscene.
	var trees_total: int = 0
	var trees_active: int = 0
	var notes_total: int = 0
	var notes_visible: int = 0
	## Notes the handlers are holding in the tree between uses. Counted, but
	## deliberately not walked into: they are hidden and process-disabled, so
	## counting their 21 nodes, 5 AnimationPlayers and 3 AnimationTrees each
	## would put up to a few hundred idle mixers into trees= and make every
	## census after this change unreadable against every census before it.
	## The engine's own nodes= still includes them, which is where the cost
	## of keeping them around is supposed to show.
	var notes_parked: int = 0
	## Effect shaders still attached and still drawing, split three ways.
	##
	## Reduce Visual Effects claims to strip every material whose shader is in
	## Settings.EFFECT_SHADER_PATHS, and the log only ever recorded whether the
	## setting was on (sha_fx=), never whether it did anything. Safety Lullaby
	## measures 12.6ms of GPU at 5 draw calls and 42.6ms at 10, with 72 and 80
	## primitives - five extra full-screen passes for 30ms, on a scene that
	## authors exactly three always-on full-screen effect ColorRects. Whether
	## those three are still running with sha_fx=off is the question, and it
	## needs a counter rather than an argument.
	var fx_live: int = 0
	var fx_effect: int = 0
	var fx_fullscreen: int = 0
	## Distinct ShaderMaterial instances behind fx_live - see the comment at
	## the point it is filled.
	var fx_materials: Dictionary = {}
	## AnimationTrees the mixer pump has taken off the engine's callback.
	var trees_manual: int = 0
	## Paths of the shadow-casting lights that are actually visible.
	var shadow_names: Array[String] = []
	## AudioStreamPlayers in the scene, and how many are actually playing.
	##
	## Monochrome authors a voiceline player per line and the shop authors
	## dozens; each playing stream is a mixer channel and each one that is
	## merely *present* still costs a node. audio= in the counter line is
	## Performance.AUDIO_OUTPUT_LATENCY, a device figure that says nothing
	## about how much the scene is asking for.
	var audio_total: int = 0
	var audio_playing: int = 0
	var nodes: Array[Node] = [scene]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()

		if node is RubiconLevelNote and node.process_mode == Node.PROCESS_MODE_DISABLED:
			notes_parked += 1
			continue

		var key: String = node.get_class()
		counts[key] = counts.get(key, 0) + 1
		if node is AnimationPlayer:
			players.append(node)
		if node is AnimationTree:
			trees_total += 1
			if node.active:
				trees_active += 1
			# RubiconMixerPump switches trees to MANUAL and advances them
			# itself for 0.35s after an input, so a tree left on the engine's
			# own callback is one the pump is not managing. active= cannot
			# tell those apart and they cost completely differently.
			if node.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
				trees_manual += 1
		# editor_only lights are not rendered in a running game, so counting
		# one is worse than not counting it: Chimera's
		# Environment/Lights/EditorMoonDoNotDelete is an editor_only
		# DirectionalLight3D with shadows on, and it showed up in shadows=[]
		# looking like one of the song's three shadow casters when the real
		# count is two. tools/audit_gpu_cost.py already had to learn this;
		# the census had not.
		var light2d := node as Light2D
		if light2d != null:
			lights2d_total += 1
			var share: float = _light2d_coverage(light2d)
			if share > 0.0:
				lights2d_live += 1
				lights2d_rank.append([share, "%s@%.2fx mascara=%d" % [
					_scene_relative_path(light2d), share, light2d.range_item_cull_mask,
				]])

		if node is Light3D and node.is_visible_in_tree() and not node.editor_only \
				and _lights_the_main_frame(node):
			lights_visible += 1
			if node.shadow_enabled:
				lights_shadow += 1
				# Named, because "Monochrome has one shadow caster" is not
				# actionable and "Monochrome's one shadow caster is the
				# results screen's DirectionalLight3D, in a SubViewport, for
				# a screen nobody has seen yet" is. Chimera's 30fps ceiling
				# is still pinned on shadow casters that were only ever
				# counted.
				if shadow_names.size() < 4:
					shadow_names.append(_scene_relative_path(node))
		# Material first, visibility second: is_visible_in_tree() walks to the
		# root, and the shop has thousands of CanvasItems against a handful
		# carrying a ShaderMaterial.
		if node is CanvasItem:
			# Anything visible, opaque and big enough to hide the game. The
			# fx= pass above only looks at items carrying a shader, so a
			# plain black ColorRect - which is exactly what Chimera puts over
			# its own song - was invisible to every counter in this log.
			if node.is_visible_in_tree():
				var area: float = _screen_area(node)
				if area > 0.0:
					overdraw_px += area
					overdraw_items += 1
					if area > overdraw_top_px:
						overdraw_top_px = area
						overdraw_top = _scene_relative_path(node)
					_rank_overdraw(overdraw_rank, area, node)

				if _covers_screen(node) and _paints_anything(node):
					var opacity: float = _opaque_coverage(node)
					if opacity >= 0.95:
						covers.append("%s@%.2f" % [_scene_relative_path(node), opacity])
					elif is_equal_approx(opacity, UNKNOWN_COVERAGE):
						# Screen-sized, drawing, and tinted to full alpha, but
						# its own pixels are unreadable from here. Listed
						# separately rather than folded into opaque=, because
						# the whole value of that field is that being on it
						# means something.
						covers_maybe.append(_scene_relative_path(node))

			var mat: Material = node.material
			if mat is ShaderMaterial and mat.shader != null and node.is_visible_in_tree():
				fx_live += 1
				# A unique material per item is a unique bind per item, and
				# nothing batches. Peepers shipped 128 ShaderMaterials that
				# differed only in a parameter the shader could not use, and
				# collapsing them to 6 is half of why Monochrome's draw p90
				# went 283 -> 51. fx=N(uniq=M) makes that ratio visible
				# everywhere instead of only where somebody happened to open
				# the scene: N far above M is fine, N == M on a wall of
				# identical items is the smell.
				fx_materials[mat.get_instance_id()] = true
				if Settings.EFFECT_SHADER_PATHS.has(mat.shader.resource_path):
					fx_effect += 1
					if _covers_screen(node):
						fx_fullscreen += 1
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			audio_total += 1
			if node.playing:
				audio_playing += 1
		if node is RubiconLevelNote:
			notes_total += 1
			if node.is_visible_in_tree():
				notes_visible += 1
		for child in node.get_children():
			nodes.append(child)

	var playing: int = 0
	var total_tracks: int = 0
	var heaviest: Array = []
	for player in players:
		if not player.is_playing():
			continue
		playing += 1
		var anim := player.get_animation(player.current_animation)
		var tracks: int = anim.get_track_count() if anim else 0
		total_tracks += tracks
		# @Ns is the playback position within the current animation, not a
		# timestamp - it is what turns "122_fall was playing" into "7.5s into
		# 122_fall", which is what actually locates a stall against a specific
		# track's keyframe instead of guessing from wall-clock arithmetic.
		heaviest.append([tracks, "%s/%s@%.1fs" % [
			player.name, player.current_animation, player.current_animation_position,
		]])

	heaviest.sort_custom(func(a, b): return a[0] > b[0])
	var top: PackedStringArray = []
	for i in mini(4, heaviest.size()):
		top.append("%s(%d)" % [heaviest[i][1], heaviest[i][0]])

	var by_class: Array = []
	for key in counts:
		by_class.append([counts[key], key])
	by_class.sort_custom(func(a, b): return a[0] > b[0])
	var classes: PackedStringArray = []
	for i in mini(8, by_class.size()):
		classes.append("%s=%d" % [by_class[i][1], by_class[i][0]])

	# What changed since the last census of this same scene, biggest movers
	# first.
	#
	# The absolute counts are a snapshot and the interesting thing is almost
	# always the difference: Monochrome's 136ms stall census reads
	# Sprite2D=154 ColorRect=146 AnimationPlayer=129, which is only
	# meaningful next to the census before it. Reset on scene change so the
	# first census of a scene never diffs against a different one.
	var class_delta: PackedStringArray = []
	if not _last_census_counts.is_empty():
		var moved: Array = []
		for key in counts:
			var change: int = counts[key] - int(_last_census_counts.get(key, 0))
			if change != 0:
				moved.append([absi(change), "%s%+d" % [key, change]])
		for key in _last_census_counts:
			if not counts.has(key):
				moved.append([int(_last_census_counts[key]), "%s-%d" % [key, _last_census_counts[key]]])
		moved.sort_custom(func(a, b): return a[0] > b[0])
		for i in mini(6, moved.size()):
			class_delta.append(moved[i][1])
	_last_census_counts = counts

	_entry("CENSUS", "%s | anim_players=%d playing=%d anim_tracks=%d trees=%d(active=%d manual=%d) notes=%d(visible=%d) parked=%d audio=%d(playing=%d) phys2d=%d/%d lights=%d(shadow=%d) luz2d=%d/%d fx=%d(effect=%d full=%d uniq=%d) opaque=%d maybe=%d over=%.1fx(n=%d top=%s@%.1fx) | %s | top_anims=[%s] | shadows=[%s] | opaque=[%s] | maybe=[%s] | relleno=[%s] | luces2d=[%s] | %s | delta=[%s]" % [
		reason, players.size(), playing, total_tracks, trees_total, trees_active, trees_manual,
		notes_total, notes_visible, notes_parked,
		audio_total, audio_playing,
		# Monochrome and Safety Lullaby are 2D scenes and every touch overlay
		# in the project is 2D, and the log only ever carried the 3D pair -
		# so the shop was measured and the songs were not.
		int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		lights_visible, lights_shadow,
		lights2d_live, lights2d_total,
		fx_live, fx_effect, fx_fullscreen, fx_materials.size(),
		covers.size(), covers_maybe.size(),
		overdraw_px / maxf(1.0, _screen_px()), overdraw_items,
		overdraw_top if not overdraw_top.is_empty() else "-",
		overdraw_top_px / maxf(1.0, _screen_px()),
		_graphics_summary(), ", ".join(top), ", ".join(shadow_names),
		", ".join(covers.slice(0, 6)),
		", ".join(covers_maybe.slice(0, 6)),
		_overdraw_rank_text(overdraw_rank),
		_light2d_rank_text(lights2d_rank),
		" ".join(classes), " ".join(class_delta),
	])

## The 2D lights that reach the frame, biggest first, with the mask each one
## pairs by. Three, same reason `relleno=` stops at six.
##
## `mascara=` is `range_item_cull_mask`, and it is the actionable half: a light
## only costs a second pass on items whose own `light_mask` shares a bit with
## it. The alley authors 257 (bits 1 and 9) on three of its lights and nothing
## at all on the fourth, while nine of its eleven parallax sprites carry
## `light_mask = 3` - so they share bit 1, and every one of those nine is drawn
## again per light. Narrowing either side is the lever; the number is here so
## the next log can say whether it worked.
func _light2d_rank_text(rank: Array) -> String:
	rank.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var parts: PackedStringArray = []
	for i in mini(3, rank.size()):
		parts.append(String(rank[i][1]))
	return ", ".join(parts)

## `luz2d=` for the heartbeat: how many 2D lights are live and how much screen
## they add up to.
##
## The sum is the number that matters and it is not the count. Godot's canvas
## renderer draws each affected CanvasItem AGAIN, once per light touching it,
## so what multiplies the fill is total coverage, not how many lights exist -
## one PointLight2D at texture_scale 4.0 across the whole frame costs more
## than three small ones. `over=` counts items once and cannot see any of it.
##
## Reported every heartbeat, off the per-scene cache, because the census that
## used to be the only source of this missed the whole of Safety Lullaby. See
## _light2d_watch.
func _light2d_summary() -> String:
	var live: int = 0
	var total_cover: float = 0.0
	var top_cover: float = 0.0
	var top_name: String = "-"

	for light: Light2D in _light2d_watch:
		if not is_instance_valid(light):
			continue
		var share: float = _light2d_coverage(light)
		if share <= 0.0:
			continue
		live += 1
		total_cover += share
		if share > top_cover:
			top_cover = share
			top_name = _scene_relative_path(light)

	return "luz2d=%d/%d suma=%.2fx top=%s@%.2fx" % [
		live, _light2d_watch.size(), total_cover, top_name, top_cover,
	]


## How much of the frame this 2D light reaches, as a fraction of one screen.
##
## Zero for a light that cannot cost anything: switched off, hidden, no energy,
## living in a SubViewport rather than the frame the player is looking at, or -
## the common case in this project - positioned in another part of the 2D world.
## Safety Lullaby keeps its ending in the same scene at y=2426 and y=3420 while
## the song's camera sits at y=540, so the huge `Glow` sprite and the `Darkness`
## light down there cost nothing during the song. That was worth measuring
## rather than assuming: they were both about to be blamed for the song's GPU.
##
## Rect the same way `_screen_area()` does it, with the same caveat about
## world-versus-screen space, so the two fields are comparable and wrong in the
## same direction if they are wrong at all. A PointLight2D's reach is its
## texture scaled by `texture_scale` and by the node's own transform;
## DirectionalLight2D reaches everything.
func _light2d_coverage(light: Light2D) -> float:
	if not light.enabled or not light.is_visible_in_tree() or light.energy <= 0.0:
		return 0.0
	if light.get_viewport() != get_tree().root:
		return 0.0

	var screen := Rect2(Vector2.ZERO, light.get_viewport_rect().size)
	if screen.size.x <= 0.0 or screen.size.y <= 0.0:
		return 0.0

	var reach: Rect2 = screen
	var point := light as PointLight2D
	if point != null:
		if point.texture == null:
			return 0.0
		var size: Vector2 = point.texture.get_size() * point.texture_scale
		reach = light.get_global_transform() * Rect2(point.offset - size * 0.5, size)
	elif light is not DirectionalLight2D:
		return 0.0

	return screen.intersection(reach).get_area() / maxf(1.0, _screen_px())

## Keeps the OVERDRAW_RANK biggest contributors, by insertion rather than by
## sorting the whole list: the shop has thousands of visible CanvasItems and
## this runs inside the same walk.
func _rank_overdraw(rank: Array, area: float, node: CanvasItem) -> void:
	var at: int = rank.size()
	while at > 0 and area > float(rank[at - 1][0]):
		at -= 1
	if at >= OVERDRAW_RANK:
		return
	rank.insert(at, [area, node])
	if rank.size() > OVERDRAW_RANK:
		rank.resize(OVERDRAW_RANK)

## `name@1.00x a=0.00` per entry - the share of one screen it paints, and the
## alpha it paints it at. `a=?` where the pixels come from a texture or a shader
## and the census cannot read them, same rule the BLACKOUT line uses.
func _overdraw_rank_text(rank: Array) -> String:
	var parts: PackedStringArray = []
	for pair in rank:
		var node: CanvasItem = pair[1]
		if not is_instance_valid(node):
			continue
		var opacity: float = _opaque_coverage(node)
		var alpha: String = "?" if is_equal_approx(opacity, UNKNOWN_COVERAGE) \
			and not _alpha_is_knowable(node) else "%.2f" % opacity
		parts.append("%s@%.2fx a=%s" % [
			_scene_relative_path(node),
			float(pair[0]) / maxf(1.0, _screen_px()),
			alpha,
		])
	return ", ".join(parts)

## Whether a visible CanvasItem covers most of the frame, which is what makes
## a shader on it a full-screen pass rather than a decoration on one sprite.
## Controls carry a rect; anything else is counted as not full-screen rather
## than guessed at from a texture and a transform.
func _covers_screen(node: CanvasItem) -> bool:
	var control := node as Control
	if control == null:
		return false
	var screen: Vector2 = node.get_viewport_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return false
	var rect: Vector2 = control.get_global_rect().size
	return rect.x >= screen.x * 0.8 and rect.y >= screen.y * 0.8

## Area of the frame this CanvasItem draws over, in pixels, clipped to the
## screen.
##
## Summed across everything visible this gives an overdraw factor: how many
## times the frame is painted. It is the one thing left that can explain
## Safety Lullaby and Chimera sitting at 30fps with 40 draw calls and 890
## primitives, after script, shaders, lights, textures, presentation and
## thermal throttling were each ruled out with numbers - Monochrome carries
## three times the texture weight of Chimera and holds 60.
##
## Watches the handful of nodes that could black out the screen, every frame.
##
## The census already names a full-screen opaque node when it sees one - it
## caught Chimera's Prelude/Black at coverage 1.00 - but it samples every 30
## seconds, so a rect that blacks the screen for ten seconds between two
## samples leaves no trace. The reported bug is exactly that shape: a black
## graphic that comes and goes during a song, invisible in a log whose only
## two censuses of a 40 second Chimera visit both read opaque=[].
##
## Watching every CanvasItem every frame is not affordable. Watching the ones
## that could possibly do it is. They are collected once, and hidden ones are
## collected too - a node authored hidden and switched on by an animation
## track is the whole failure mode, and Chimera has two animations that set
## Prelude/Black visible with no key anywhere that sets it back.
##
## Reports edges, not states: one line when a watched node starts covering the
## screen and one when it stops, with how long it lasted. A log that said
## "still black" sixty times a second would bury what it is reporting.
## Half the screen, not four fifths.
##
## 0.8 was a guess and it cost this bug two rounds. Chimera's black graphic
## measures 960x720 in a 1280x720 viewport - 75% - so it sat under the gate,
## the log stayed quiet through every second of it, and that silence got read
## as the bug being fixed. A partial cover is still a cover; the line prints
## the fraction, so judging it is the reader's job and not the threshold's.
const BLACKOUT_MIN_COVERAGE := 0.5
const BLACKOUT_MAX_LUMA := 0.15

var _blackout_watch: Array[CanvasItem] = []
var _blackout_on: Dictionary = {}

## Every AnimationMixer in the running scene, and the one that drives the
## song's sequences.
##
## Collected in the same walk as the blackout watch, on the same one-second
## delay, for the same reason: taken during load it misses whatever _ready()
## builds.
##
## This is the counter rest= needs. AnimationMixer processing happens in the
## idle step, inside the bracket script= measures, and Chimera carries 69-104
## players with 14 active trees - but the census only samples that every
## thirty seconds, so no spike has ever had a mixer count attached to it. A
## cached list turns "how much animation was running on the frame that cost
## 79.81ms" into a per-frame read of about a hundred is_playing() calls.
var _mixer_watch: Array[AnimationMixer] = []

## Las Light2D de la escena, recogidas una vez por escena en el mismo barrido
## que las demas listas.
##
## Existe porque el censo se perdio la unica ventana que importaba. En el log
## del 2026-08-24 Safety Lullaby corre de 198s a 265s con `gpu` clavado en
## 32ms, y los cuatro censos cayeron a 198.76, 199.60 (intro), 225.03 (intro
## otra vez) y 255.04 (gameover) - ninguno durante la cancion. `luz2d=` y
## `luces2d=` solo salen en el censo, asi que el numero que decide si el
## presupuesto de luces 2D se esta aplicando no se midio.
##
## Subir la frecuencia del censo no era la respuesta: `self=` dice que uno
## cuesta 4.6-15.4ms en esa escena, o sea que medir mas seguido habria metido
## justo el tipo de hipo que estamos persiguiendo. Cachear la lista lo deja en
## un bucle de trece elementos con aritmetica de rectangulos, que sale en cada
## heartbeat sin que se note.
var _light2d_watch: Array[Light2D] = []

## The AnimationPlayer that drives the song's sequences, if the running scene
## has one, so seq= can name the moment every line was written at.
##
## top_anims= already carries this and it is on the CENSUS line, which lands
## every thirty seconds. Every SPIKE in the last device log therefore had to
## be placed in the song by arithmetic across neighbouring lines. Naming the
## sequence and its position on every entry is what turns "a 1829ms frame at
## log second 291" into "1829ms at 122_fall@7.5s" without the reconstruction.
var _sequence_player: AnimationPlayer = null

## The Collector's Shop aim, cached with the rest of the per-scene watches.
##
## Why it is worth a field: the shop's 3D reticle is the only pointer in the
## game with no cursor behind it, and the report that produced this - "no puedo
## apuntar al sombrero del coleccionista, siempre es al medio" - could not be
## resolved by reading the scene. Three readings of it were wrong in a row.
## What was ruled out with numbers: the hat is on the same collision layer as
## the Kollectadex and the board, both desk animations set its `can_interact`
## true, and from the desk camera pose its box is a clean 7.5% of the screen
## above the Collector rather than buried inside him.
##
## What that left is the aim itself, and nothing in the log could see it. The
## same arithmetic says the screen CENTRE at that pose hits neither the hat nor
## the Collector, so `centrada` plus `obj=-` is the shape to look for: the aim
## never left the middle, which means the tap that should have latched it never
## reached MouseController._unhandled_input.
var _aim_controller: Node = null

## Node names that identify the sequence driver, in preference order. Checked
## by name rather than by type because every song scene has dozens of
## AnimationPlayers and only one of them is the timeline.
const SEQUENCE_PLAYER_NAMES: Array[StringName] = [
	&"SequencePlayer", &"AnimationPlayer",
]

## Collected after the scene has settled rather than during load: _ready() and
## the opening animations both move things, and a list taken too early misses
## whatever they build.
func _collect_blackout_watch() -> void:
	_blackout_watch.clear()
	_blackout_on.clear()
	_mixer_watch.clear()
	_light2d_watch.clear()
	_visual3d_watch.clear()
	_particles_watch.clear()

	# Per scene, so every song gets its own unshaded probe - and so a scene
	# change during one cannot leave the viewport stuck in a debug draw mode.
	_sequence_player = null
	_aim_controller = null
	_physics_nodes = 0
	_skeleton_bones = 0
	_skeleton_count = 0
	_surface_count = 0
	_alpha_surface_count = 0
	_material_count = 0
	_process_nodes = 0
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		_probe_names.clear()
		_probe_at.clear()
		_peak_regions.clear()
		return

	_peak_regions.clear()

	var materials_seen: Dictionary = {}
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)

		# One walk, three lists. Splitting them would mean three walks of a
		# tree that runs to nine hundred nodes in a song.
		if node.is_processing():
			_process_nodes += 1
		if node.is_physics_processing():
			_physics_nodes += 1
		if node is GPUParticles2D or node is GPUParticles3D \
				or node is CPUParticles2D or node is CPUParticles3D:
			_particles_watch.append(node)
		var skeleton := node as Skeleton3D
		if skeleton != null:
			_skeleton_count += 1
			_skeleton_bones += skeleton.get_bone_count()
		if _aim_controller == null and node is MouseController:
			_aim_controller = node
		var light2d := node as Light2D
		if light2d != null:
			_light2d_watch.append(light2d)
		var visual := node as VisualInstance3D
		if visual != null:
			_visual3d_watch.append(visual)
			var mesh_node := node as MeshInstance3D
			if mesh_node != null:
				for surface in mesh_node.get_surface_override_material_count():
					_surface_count += 1
					# The override wins when it is set, and the mesh's own
					# material is what is bound otherwise - so ask in that
					# order or a scene that overrides everything reports the
					# meshes' shared materials and looks perfectly batched.
					var mat: Material = mesh_node.get_surface_override_material(surface)
					if mat == null and mesh_node.mesh != null:
						mat = mesh_node.mesh.surface_get_material(surface)
					if mat != null and not materials_seen.has(mat.get_instance_id()):
						materials_seen[mat.get_instance_id()] = true
						_material_count += 1
					# Counted per surface, not per material: what defeats
					# early-Z is how much of the screen discards, and one
					# shared material can be bound to twenty walls.
					var base_mat := mat as BaseMaterial3D
					if base_mat != null and base_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						_alpha_surface_count += 1
		var mixer := node as AnimationMixer
		if mixer != null:
			_mixer_watch.append(mixer)
			var player := mixer as AnimationPlayer
			if player != null and _sequence_rank(player) < _sequence_rank(_sequence_player):
				_sequence_player = player

		var item := node as CanvasItem
		if item == null or not _can_cover_the_screen(item):
			continue
		_blackout_watch.append(item)

	_entry("BLACKWATCH", "vigilando %d rects oscuros, %d mixers, %d visuales 3D, %d particulas, %d nodos con _process, %d con _physics_process en %s (seq=%s) | superficies=%d(no_opacas=%d) materiales_unicos=%d esqueletos=%d(huesos=%d)" % [
		_blackout_watch.size(), _mixer_watch.size(), _visual3d_watch.size(),
		_particles_watch.size(), _process_nodes, _physics_nodes,
		_current_scene_name(),
		_sequence_player.name if _sequence_player != null else "-",
		_surface_count, _alpha_surface_count, _material_count,
		_skeleton_count, _skeleton_bones,
	])

	# DESPUES del recuento, no antes: una sonda define `_process`, asi que Godot
	# le enciende el procesado sola y se contaria a si misma en _process_nodes.
	_install_probes(scene)
	_entry("PROBES", "%d regiones instaladas en %s: %s" % [
		_probe_names.size(), _current_scene_name(),
		", ".join(_probe_names) if not _probe_names.is_empty() else "ninguna"])

## Times the same shot three ways and writes GPUSPLIT.
##
## `viewport_get_measured_render_time_gpu()` is **one frame behind**, so each
## step reads the frame the previous step set up:
##
##   step 0   read = a normal frame      -> base        then draw UNSHADED
##   step 1   read = the unshaded frame  -> unshaded    then draw OVERDRAW
##   step 2   read = the overdraw frame  -> overdraw    then restore, emit
##
## Only in a scene that has a 3D camera and something visible in it - the two
## 2D songs and every menu would report the 2D canvas three times over and say
## nothing.
func _step_gpu_split() -> void:
	if not is_inside_tree():
		return
	if _gpu_split_state == 0:
		if not Settings.diagnostics_gpu_split:
			return
		_time_since_gpu_split += _last_frame_wall_ms
		if _time_since_gpu_split < GPU_SPLIT_SECONDS * 1000.0:
			return
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera == null or _visual3d_load() <= 0:
			return
		_time_since_gpu_split = 0.0
		_gpu_split_base = _viewport_gpu_ms()
		get_viewport().debug_draw = (Viewport.DEBUG_DRAW_OVERDRAW
			if _gpu_split_overdraw_turn else Viewport.DEBUG_DRAW_UNSHADED)
		_gpu_split_state = 1
		return

	var probed: float = _viewport_gpu_ms()
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	_gpu_split_state = 0
	var was_overdraw: bool = _gpu_split_overdraw_turn
	_gpu_split_overdraw_turn = not _gpu_split_overdraw_turn

	# A driver that will not answer reports 0.00 for both, and two zeroes are
	# not a measurement - see the GPUTIMING note.
	if _gpu_split_base <= 0.0:
		return

	var mpx: float = _mpx_3d()
	if was_overdraw:
		_entry("GPUSPLIT", "base=%.2fms overdraw=%.2fms | relleno=%.0f%% mpx3d=%.3f" % [
			_gpu_split_base, probed,
			100.0 * probed / _gpu_split_base, mpx,
		])
		return

	var lighting: float = maxf(_gpu_split_base - probed, 0.0)
	_entry("GPUSPLIT", "base=%.2fms sin_luz=%.2fms | luz=%.2fms(%.0f%%) mpx3d=%.3f luz_por_mpx=%.1f" % [
		_gpu_split_base, probed, lighting,
		100.0 * lighting / _gpu_split_base, mpx,
		lighting / maxf(mpx, 0.0001),
	])


## Times the idle step twice and writes SCRIPTSPLIT. See SCRIPT_SPLIT_SECONDS.
##
## `_script_usec` is the bracket this node opens and `_ScriptTail` closes, so
## when `_process` runs it still holds the PREVIOUS frame's total - the same
## one-frame lag the GPU timing read has, and it lines up the same way. Frame
## A reads the frame before it (mixers running) and then switches them off;
## the mixers process later in frame A, so frame A is the frame without them;
## frame B reads frame A and puts them back.
func _step_script_split() -> void:
	if not is_inside_tree():
		return

	if _script_split_state == 0:
		if not Settings.diagnostics_gpu_split:
			return
		_time_since_script_split += _last_frame_wall_ms
		if _time_since_script_split < SCRIPT_SPLIT_SECONDS * 1000.0:
			return
		var mixers: Array[AnimationMixer] = _active_mixers()
		if mixers.is_empty():
			# Nothing to subtract. Reset the clock anyway so a scene with no
			# animation does not walk its tree on every single frame.
			_time_since_script_split = 0.0
			return
		_time_since_script_split = 0.0
		_script_split_base = float(_script_usec) / 1000.0
		_script_split_paused = mixers
		for mixer: AnimationMixer in mixers:
			mixer.active = false
		_script_split_state = 1
		return

	var probed: float = float(_script_usec) / 1000.0
	for mixer: AnimationMixer in _script_split_paused:
		if is_instance_valid(mixer):
			mixer.active = true
	var paused: int = _script_split_paused.size()
	_script_split_paused.clear()
	_script_split_state = 0

	# A base of zero is not a measurement, same rule as GPUSPLIT's.
	if _script_split_base <= 0.0:
		return

	var animation: float = maxf(_script_split_base - probed, 0.0)
	_entry("SCRIPTSPLIT", "base=%.2fms sin_anim=%.2fms | anim=%.2fms(%.0f%%) mixers=%d" % [
		_script_split_base, probed, animation,
		100.0 * animation / _script_split_base, paused,
	])

## Every AnimationMixer in the current scene that is currently active.
##
## Walked at the sample rather than cached at the scene change: this runs once
## every twenty seconds, and a cache would have to be invalidated by every
## AnimationPlayer the sequences add and free mid-song - Chimera's census moves
## between 69 and 104 of them.
func _active_mixers() -> Array[AnimationMixer]:
	var out: Array[AnimationMixer] = []
	var scene: Node = get_tree().current_scene
	if scene == null:
		return out
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var mixer := node as AnimationMixer
		if mixer != null and mixer.active:
			out.append(mixer)
		for child in node.get_children():
			stack.append(child)
	return out

## The main viewport's last measured GPU frame, in milliseconds. Zero when the
## driver does not answer - which the GPUTIMING latch elsewhere reports once
## and which GPUSPLIT treats as "no measurement" rather than as three zeroes.
func _viewport_gpu_ms() -> float:
	if not is_inside_tree():
		return 0.0
	return RenderingServer.viewport_get_measured_render_time_gpu(
		get_viewport().get_viewport_rid())

## Megapixels the 3D pass actually renders: the render target times the render
## scale, squared. Printed rather than left to be reconstructed by hand from
## `vp=` and the window line, which is arithmetic this file has got wrong in
## writing more than once - including here, in the line below.
##
## **Not `get_visible_rect()`.** Under `canvas_items` stretch, which is what
## this project ships, that returns the BASE resolution - a constant 1920x1080
## whatever the phone is - because it is the rect 2D is laid out in. The thing
## the GPU actually fills is the window, letterboxed to the aspect: 1280x720 on
## the g53's 1600x720 panel. So the old line reported
##
##     1920 x 1080 x 0.50^2 = 0.5184 Mpx
##
## for a pass that renders 1280 x 720 x 0.50^2 = 0.2304 Mpx. Every figure in
## this repo quoted in ms/Mpx - the 90.8 slope, the 6-8 lights-per-fragment
## reading taken off it, `luz_por_mpx` in GPUSPLIT - is 2.25x low as a result,
## and the number was steady at 0.518 across two devices and every preset
## precisely because it never depended on either.
##
## `get_texture().get_size()` is the render target. scene_shot.gd measured the
## same thing from the other side and says so in its own header: at 1600x720
## with aspect KEEP it is 1280x720, already free of the pillarbox.
func _mpx_3d() -> float:
	if not is_inside_tree():
		return 0.0
	var viewport: Viewport = get_viewport()
	var target: ViewportTexture = viewport.get_texture()
	if target == null:
		return 0.0
	var size: Vector2i = target.get_size()
	var scale: float = viewport.scaling_3d_scale
	return float(size.x) * float(size.y) * scale * scale / 1000000.0

## How good a candidate this player is for being the sequence driver: lower
## wins, and anything not on the list loses to everything on it.
func _sequence_rank(player: AnimationPlayer) -> int:
	if player == null:
		return SEQUENCE_PLAYER_NAMES.size() + 1
	var index: int = SEQUENCE_PLAYER_NAMES.find(player.name)
	return index if index >= 0 else SEQUENCE_PLAYER_NAMES.size()

## What the sequence driver is playing and how far into it, or "-".
##
## Position within the animation rather than a wall clock: "122_fall@7.5s"
## locates a stall against one of that sequence's 31 tracks, which is the
## thing a timestamp cannot do.
func _sequence_state() -> String:
	if _sequence_player == null or not is_instance_valid(_sequence_player):
		return "-"
	if not _sequence_player.is_playing():
		return "(parado)"
	return "%s@%.1fs" % [
		_sequence_player.current_animation,
		_sequence_player.current_animation_position,
	]

## How many of the scene's AnimationMixers are actually running, split into
## players and trees.
##
## AnimationTree never calls play() on the players underneath it, so a tree
## driving four sub-players reads as one active mixer and four idle ones -
## which is exactly the trap the note scene set for the old census, where 40
## notes x 6 AnimationPlayers read as zero. Counting trees separately is what
## keeps that visible.
## What the viewport is really configured with, read off the viewport rather
## than off Settings.
##
## This is the bug class that has bitten this project more times than any
## other. Four separate times a quality preset turned out not to lower the
## thing it claimed to: render scale existed only on Very Low, Medium's shadow
## cost was identical to High's, anisotropic filtering and mesh LOD were never
## wired up at all, and positional_shadow_atlas_size does not cover
## DirectionalLight3D, which renders into a completely separate atlas. Every
## one of those was found by reading code, months late. Reading the viewport
## back is how a preset that does not apply becomes one line in the log.
##
## All property names were checked against the 4.7.1 binary with
## ClassDB.class_get_property_list rather than written from memory - the iOS
## preset work is a standing reminder that half a dozen plausible option names
## do not exist.
## How the scene expects to be lit: bake modes of its lights and its meshes.
##
## The field this whole hunt needed and did not have. Six of Chimera's seven
## lights are authored `light_bake_mode = 1` (BAKE_STATIC), which means their
## contribution to static geometry lives **only in the lightmap** - at runtime
## they light nothing by themselves. So if the bake fails to apply on a device,
## six of seven lights go with it and the house is black, while `lights=10` and
## `vis3d=78/96` both keep reporting a perfectly healthy scene. That is exactly
## the shape of the ninety black seconds.
##
## Meshes are counted the same way: GI_MODE_STATIC is a mesh that expects the
## bake, GI_MODE_DISABLED one that cannot receive it at all.
func _bake_modes() -> String:
	var light_static: int = 0
	var light_dynamic: int = 0
	var light_off: int = 0
	var mesh_static: int = 0
	var mesh_dynamic: int = 0
	var mesh_off: int = 0
	for node in _visual3d_watch:
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var light := node as Light3D
		if light != null:
			match light.light_bake_mode:
				Light3D.BAKE_STATIC: light_static += 1
				Light3D.BAKE_DYNAMIC: light_dynamic += 1
				_: light_off += 1
			continue
		var geo := node as GeometryInstance3D
		if geo == null:
			continue
		match geo.gi_mode:
			GeometryInstance3D.GI_MODE_STATIC: mesh_static += 1
			GeometryInstance3D.GI_MODE_DYNAMIC: mesh_dynamic += 1
			_: mesh_off += 1
	return "luces=est%d/din%d/off%d mallas=est%d/din%d/off%d" % [
		light_static, light_dynamic, light_off, mesh_static, mesh_dynamic, mesh_off]

## How many visible lights actually reach the camera, and the nearest one.
##
## `lights=10(shadow=1)` counts lights that exist and are visible, which is a
## different question from whether any of them lights where the camera is
## standing. Chimera spends ninety seconds at x=-15 in a closet whose only
## light is authored `visible = false`; the census reported ten lights the
## whole time and every one of them was back in the house.
##
## Directional lights reach everywhere by construction and are counted apart.
func _light_reach() -> String:
	var main: Viewport = get_viewport() if is_inside_tree() else null
	var camera: Camera3D = main.get_camera_3d() if main != null else null
	if camera == null:
		return "-"
	var eye: Vector3 = camera.global_position
	var reaching: int = 0
	var directional: int = 0
	var phantom: int = 0
	var names: PackedStringArray = []
	var nearest: float = INF
	var nearest_name: String = "-"
	for node in _visual3d_watch:
		if not is_instance_valid(node):
			continue
		var light := node as Light3D
		if light == null or not light.is_visible_in_tree():
			continue

		# Two kinds of light this counted and the GPU never draws. Chimera
		# read `dir=2` for ninety heartbeats and BOTH were these, which made
		# the per-fragment light count - the one number that sets this
		# scene's whole frame cost - read 6 when it is 4.
		#
		# editor_only is removed from the render at runtime; the engine keeps
		# the node, so is_visible_in_tree() stays true. Chimera's
		# EditorMoonDoNotDelete is one.
		#
		# And a light under a SubViewport lights that viewport's world, not
		# this one. The results screen ships a shadow-casting
		# DirectionalLight3D inside its own SubViewport, which every song
		# instances - and which the log itself shows is not even rendering
		# (`sub=0/1` on 41 of 43 Chimera heartbeats).
		if light.editor_only or light.get_viewport() != main:
			phantom += 1
			continue

		if light.light_energy <= 0.0:
			continue
		if light is DirectionalLight3D:
			directional += 1
			continue

		# Cast, never get(). Chimera's CrawlSpaceLight is an AreaLight3D -
		# neither omni nor spot - so `light.get("spot_range")` returns null,
		# and assigning null to a typed float aborts the function. This runs
		# while building every log line, so that one null took HEARTBEAT,
		# CENSUS and FRAME out of the log with it and left no error behind.
		var range_units: float = 0.0
		var omni := light as OmniLight3D
		var spot := light as SpotLight3D
		if omni != null:
			range_units = omni.omni_range
		elif spot != null:
			range_units = spot.spot_range
		else:
			continue
		var distance: float = eye.distance_to(light.global_position)
		if distance < nearest:
			nearest = distance
			nearest_name = light.name
		if distance <= range_units:
			reaching += 1
			names.append(light.name)

	# Named, not just counted. Forward Mobile evaluates every light that
	# reaches a fragment in that fragment's shader, so this list IS the
	# frame's cost - measured at about 15ms per light over a full 1600x720 -
	# and knowing which ones they are is the difference between cutting the
	# right one and guessing.
	var who: String = ",".join(names) if not names.is_empty() else "-"

	# `apagadas=` is the count LightBudget is holding at cull mask 0, and it is
	# here because the loop above cannot report it: this function has skipped
	# `light_energy <= 0.0` since it was written, so a light switched on at zero
	# energy was never in `reaching` - while the renderer paired and evaluated
	# it on every fragment in range all along. That gap is the difference
	# between the four lights this field reported for Chimera's wide shots and
	# the ~6 per fragment its 90.8 ms/Mpx slope implies. Without this number a
	# pass that fired and a pass that found no candidate read identically.
	var dark: String = ""
	var budget: Node = get_node_or_null(^"/root/LightBudget")
	if budget != null and budget.has_method("dark_culled_count"):
		dark = " apagadas=%d" % budget.call("dark_culled_count")

	if nearest == INF:
		return "0alcanzan dir=%d fant=%d%s [%s]" % [directional, phantom, dark, who]
	return "%dalcanzan dir=%d fant=%d%s [%s] cerca=%s@%.1f" % [
		reaching, directional, phantom, dark, who, nearest_name, nearest]

## Where the shop's 3D pointer is aiming, and what is under it.
##
## `-` in every scene without a MouseController, which is every scene but the
## Collector's Shop.
##
##     mira=[estado=2 pos=960,540 centrada obj=- clic=no toque=si]
##
## `centrada` vs `fijada`: the aim is the screen centre until a tap latches
## `touch_aim`, and it is reset to the centre on every shop state change. So
## `centrada` on a FOCUSED line means no tap has landed since the camera moved.
## Read with `obj=`: centred AND nothing under it is the reported bug, because
## at the desk pose the centre of the screen is empty - the Collector stands
## left of it and his hat above that.
##
## `clic=` is `colliding and can_click`, i.e. whether a confirm would do
## anything right now, which is also what turns the reticle from idle to hover.
## `toque=` is is_touch_controls_active(), so a desktop run says `no` and the
## whole field can be read as "mouse, ignore the latching".
func _aim_summary() -> String:
	if _aim_controller == null or not is_instance_valid(_aim_controller):
		return "-"

	var state: int = -1
	var root_node: Object = _aim_controller.get("root")
	if root_node != null and "state" in root_node:
		state = root_node.get("state")

	var pos: Vector2 = Vector2.ZERO
	if _aim_controller.has_method("get_aim_position"):
		pos = _aim_controller.call("get_aim_position")

	var latched: bool = _aim_controller.get("touch_aim") != Vector2.INF

	# The collider the ray is on, not the one the last tap chose: this is
	# sampled while the log line is written, so it is the live answer to "is
	# the pointer on the hat".
	var target: String = "-"
	var ray: Object = _aim_controller.get("ray_cast")
	if ray != null and ray.has_method("is_colliding") and ray.call("is_colliding"):
		var collider: Object = ray.call("get_collider")
		if collider != null and "name" in collider:
			target = String(collider.get("name"))

	var touch: bool = _aim_controller.has_method("is_touch_controls_active") \
		and _aim_controller.call("is_touch_controls_active")

	return "[estado=%d pos=%d,%d %s obj=%s clic=%s toque=%s]" % [
		state, roundi(pos.x), roundi(pos.y),
		"fijada" if latched else "centrada", target,
		"si" if bool(_aim_controller.get("colliding")) and bool(_aim_controller.get("can_click")) else "no",
		"si" if touch else "no",
	]

## Whether the LightmapGI in this scene actually has a bake to apply.
##
## The prime suspect once the frame was measured black with 78 of 96 meshes
## visible, ten lights, no overlay and no shader: nothing is covering the
## screen, so the surfaces are simply not lit - and in Chimera the closet the
## camera sits in for that whole stretch has ClosetLight authored
## `visible = false` and nothing turning it on, in the port and in the pck
## alike. Which leaves the bake as the only thing that was ever lighting it.
func _lightmap_state() -> String:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return "-"
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var lm := node as LightmapGI
		if lm != null:
			var data: LightmapGIData = lm.light_data
			if data == null:
				return "sin_datos"
			var tex: TextureLayered = data.light_texture
			# Cuantas de las mallas visibles ahora mismo estan realmente
			# registradas en el bake. Un bake sano que no cubre lo que la
			# camara mira es indistinguible de un bake roto si solo se cuenta
			# el total.
			var users: Dictionary = {}
			for i in data.get_user_count():
				users[String(data.get_user_path(i))] = true
			var visible_users: int = 0
			var visible_meshes: int = 0
			for node2 in _visual3d_watch:
				if not is_instance_valid(node2):
					continue
				var geo := node2 as GeometryInstance3D
				if geo == null or not geo.is_visible_in_tree():
					continue
				visible_meshes += 1
				if users.has(String(lm.get_path_to(geo))):
					visible_users += 1
			return "%s tex=%s users=%d vis=%d/%d sh=%s" % [
				"on" if lm.is_visible_in_tree() else "OCULTO",
				"%dx%dx%d" % [tex.get_width(), tex.get_height(), tex.get_layers()] if tex != null else "NULA",
				data.get_user_count(), visible_users, visible_meshes,
				data.is_using_spherical_harmonics(),
			]
		for child in node.get_children():
			stack.append(child)
	return "ninguno"

func _viewport_config() -> String:
	if not is_inside_tree():
		return "-"
	var vp: Viewport = get_viewport()
	return "mode%d@%.2f msaa%d ssaa%d aniso%d lod%.1f atlas%d%s%s%s" % [
		vp.scaling_3d_mode, vp.scaling_3d_scale, vp.msaa_3d, vp.screen_space_aa,
		vp.anisotropic_filtering_level, vp.mesh_lod_threshold,
		vp.positional_shadow_atlas_size,
		" 16bit" if vp.positional_shadow_atlas_16_bits else "",
		" occl" if vp.use_occlusion_culling else "",
		" taa" if vp.use_taa else "",
	]

## Engine-wide knobs that are supposed to be constant, printed so drift is
## visible.
##
## The 60-to-40 frame rate flip cost this project a long investigation before
## the tester found it only happens when not screen recording, i.e. it is the
## CPU governor. The first thing checked was whether anything in the game was
## touching max_fps - nothing was, but proving that took a repo-wide sweep
## that a single field would have answered. time_scale is here for the same
## reason: it silently rescales every delta in the game and nothing reports it.
func _engine_config() -> String:
	return "ts%.2f fps%d hz%d steps%d" % [
		Engine.time_scale, Engine.max_fps,
		Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame,
	]

## The Control that currently has keyboard focus, if any.
##
## The reverted shader prewarm revealed hidden nodes, which gave focus to the
## Codes tab's LineEdit and opened the Android keyboard twice on a screen the
## player never chose. It took a device session to work that out. A focused
## LineEdit named in every line would have said it immediately, and it is the
## kind of thing only a device can show.
func _focus_state() -> String:
	if not is_inside_tree():
		return "-"
	var focused: Control = get_viewport().gui_get_focus_owner()
	return "-" if focused == null else "%s:%s" % [focused.get_class(), focused.name]

## Which per-pixel features the active 3D environment actually has on.
##
## Every one of these is paid for every pixel of every frame, and not one has
## ever appeared in this log. The quality presets set some of them and the
## scenes author others, so "Very Low" is not evidence that glow is off - the
## WorldEnvironment inside the console's SubViewport ships fog and a
## DirectionalLight3D regardless of preset. Reported as the letters that are
## on, so an empty string means the environment costs nothing extra.
func _environment_state() -> String:
	if not is_inside_tree():
		return "-"
	var world: World3D = get_viewport().find_world_3d()
	var env: Environment = world.environment if world != null else null
	if env == null:
		return "none"
	var on: PackedStringArray = []
	if env.glow_enabled:
		on.append("glow")
	if env.ssao_enabled:
		on.append("ssao")
	if env.ssil_enabled:
		on.append("ssil")
	if env.ssr_enabled:
		on.append("ssr")
	if env.sdfgi_enabled:
		on.append("sdfgi")
	if env.fog_enabled:
		on.append("fog")
	if env.volumetric_fog_enabled:
		on.append("volfog")
	# El ambiente, que es lo que decide si una superficie sin luz sale negra o
	# solo oscura. `limpio` solo decia que no hay glow ni niebla, y en una
	# escena que se apaga entera esa es la mitad menos interesante.
	var ambient: String = "amb%d@%.2f" % [env.ambient_light_source, env.ambient_light_energy]
	var background: String = "bg%d@%.2f" % [env.background_mode, env.background_energy_multiplier]
	var effects: String = "+".join(on) if not on.is_empty() else "limpio"
	return "%s %s %s" % [effects, ambient, background]

## How many particle systems are on screen, of those the scene has.
func _particles_live() -> int:
	var live: int = 0
	for node in _particles_watch:
		if node == null or not is_instance_valid(node):
			continue
		var visible_now: bool = false
		var item := node as CanvasItem
		if item != null:
			visible_now = item.is_visible_in_tree()
		else:
			var spatial := node as Node3D
			visible_now = spatial != null and spatial.is_visible_in_tree()
		if visible_now and node.get("emitting"):
			live += 1
	return live

## Times a fixed amount of arithmetic, so wall-clock costs elsewhere can be
## read against the speed the CPU was actually running at.
##
## Integer work on locals on purpose: no allocation, no property lookups, no
## engine calls, nothing whose cost depends on the scene. The sink is kept in
## a member so the optimiser cannot decide the loop is dead.
func _run_bench() -> void:
	var started: int = Time.get_ticks_usec()
	var acc: int = 0
	for i in BENCH_ITERATIONS:
		acc = (acc + i * 3) % 65521
	_bench_sink = acc
	_bench_usec = Time.get_ticks_usec() - started

## How many of the scene's 3D visuals are on screen right now.
##
## is_visible_in_tree() rather than visible, because a cutscene group hidden
## at the top switches off everything under it and counting those as visible
## is what made PhoneGlow look like an always-on shadow caster.
func _visual3d_load() -> int:
	var shown: int = 0
	for item in _visual3d_watch:
		if item != null and is_instance_valid(item) and item.is_visible_in_tree():
			shown += 1
	return shown

## The active 3D camera's field of view and where it is looking from.
##
## The sharpest unexplained thing in this project is that Chimera's GPU cost
## tracks which shot is on screen at a constant light and shadow count - 19.5ms
## on one sequence and 46.5ms on another. That is a statement about what fills
## the frame, and nothing in the log has ever recorded where the camera was.
func _camera_state() -> String:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return "-"
	var pos: Vector3 = camera.global_position
	return "fov%.0f@%.1f,%.1f,%.1f" % [camera.fov, pos.x, pos.y, pos.z]

func _anim_load() -> Array:
	var players_playing: int = 0
	var trees_active: int = 0
	for mixer in _mixer_watch:
		if mixer == null or not is_instance_valid(mixer):
			continue
		var tree := mixer as AnimationTree
		if tree != null:
			if tree.active:
				trees_active += 1
			continue
		var player := mixer as AnimationPlayer
		if player != null and player.is_playing():
			players_playing += 1
	return [players_playing, trees_active]

## Whether this item is the kind of thing that could paint a large solid area.
##
## The watch used to accept ColorRect and nothing else, which is the second
## reason Chimera's black graphic went unreported for two rounds: if the thing
## covering the screen is a TextureRect, a Panel, a Sprite2D or a
## SubViewportContainer showing a viewport that never rendered, it was never
## even on the list. The census already saw further than this - its covers_maybe
## named the results screen's Vingette, a TextureRect - so the watch was the
## narrower of the two instruments while being the one reporting edges.
##
## A ColorRect still has to be dark, because its colour is authored and
## readable and a bright one is not a blackout. Everything else is watched
## whatever it looks like: its pixels come from a texture or a shader, the
## census cannot read them (see _alpha_is_knowable), and refusing to watch what
## cannot be judged is how this was missed. _poll_blackouts prints the coverage
## and the alpha it measured, so a false positive costs one line to dismiss.
func _can_cover_the_screen(item: CanvasItem) -> bool:
	var rect := item as ColorRect
	if rect != null:
		if maxf(rect.color.r, maxf(rect.color.g, rect.color.b)) > BLACKOUT_MAX_LUMA:
			return false
		return rect.size.x * rect.size.y > 0.0

	if item is TextureRect or item is Panel or item is SubViewportContainer:
		return (item as Control).size.x * (item as Control).size.y > 0.0

	return item is Sprite2D and (item as Sprite2D).texture != null

func _poll_blackouts() -> void:
	if _blackout_watch.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for item in _blackout_watch:
		if not is_instance_valid(item):
			continue

		# _screen_area() answers in pixels, not as a fraction. The first
		# version compared it straight against BLACKOUT_MIN_COVERAGE, so any
		# rect larger than 0.8 square pixels passed and the area test filtered
		# nothing at all - the device log came back naming Chimera's 242px
		# letterbox bars, its pause-menu bars and the cinematic bars as
		# screen-covering blackouts. Divided by the screen now, which is what
		# the census does with the same helper.
		var covered: float = _screen_area(item) / maxf(1.0, _screen_px())
		var opacity: float = _opaque_coverage(item)
		var covering: bool = item.is_visible_in_tree() \
			and covered >= BLACKOUT_MIN_COVERAGE \
			and opacity >= BLACKOUT_MIN_COVERAGE
		var was: bool = _blackout_on.has(item)
		if covering and not was:
			_blackout_on[item] = now
			# The rect, because that is what named this bug in the end: a
			# screenshot showed 960x720 inside a 1280x720 viewport, and a 4:3
			# hole in a 16:9 screen says more about which node it is than any
			# coverage fraction does. "?" on the alpha where the pixels come
			# from a texture or a shader and the census cannot read them.
			var alpha_text: String = "?" if is_equal_approx(opacity, UNKNOWN_COVERAGE) \
				and not _alpha_is_knowable(item) else "%.2f" % opacity
			var box: Rect2 = _screen_rect_of(item)
			_entry("BLACKOUT", "%s tapa la pantalla (cubre=%.2f alpha=%s %dx%d en %d,%d)" % [
				_scene_relative_path(item), covered, alpha_text,
				int(box.size.x), int(box.size.y), int(box.position.x), int(box.position.y),
			])
		elif was and not covering:
			_entry("BLACKOUT", "%s deja de taparla tras %.1fs" % [
				_scene_relative_path(item), (now - int(_blackout_on[item])) / 1000.0,
			])
			_blackout_on.erase(item)


## Whether this light contributes anything to the frame the player is looking
## at, rather than just existing somewhere in the tree.
##
## The census counted every Light3D anywhere, and the results screen's
## DirectionalLight3D - shadow_enabled, inside a SubViewport - therefore
## appeared in shadows=[] on every single census of every song. Chimera looked
## like it had three shadow casters where it has one, and a whole afternoon
## went into the wrong lead on the strength of it.
##
## Two things disqualify a light. Its viewport is not the root, which is the
## same filter _screen_area() already applies for the same reason; and that
## viewport has its own World3D, so its lights are in a scene the main camera
## cannot see at all. The results screen is both: own_world_3d = true and
## render_target_update_mode = DISABLED, so it renders nothing, lights nothing,
## and costs nothing.
func _lights_the_main_frame(light: Light3D) -> bool:
	var viewport: Viewport = light.get_viewport()
	if viewport == null or not is_inside_tree():
		return false
	if viewport == get_tree().root:
		return true
	# A SubViewport that shares the main world still lights it, so long as it
	# is actually rendering.
	var sub := viewport as SubViewport
	if sub == null:
		return false
	return not sub.own_world_3d \
		and sub.render_target_update_mode != SubViewport.UPDATE_DISABLED

## Geometry only, deliberately: alpha is not folded in, because a sprite at
## 10% alpha still costs a full blend on a tile GPU and hiding it behind a
## weighting would under-report the exact thing being hunted.
## The modulate alpha this item actually draws with, multiplied down the
## CanvasItem chain the way Godot does. Stops at the first non-CanvasItem
## parent, which is where a CanvasLayer or the scene root ends the chain.
func _inherited_modulate_alpha(node: CanvasItem) -> float:
	var alpha: float = 1.0
	var walk: Node = node
	while walk != null:
		var item := walk as CanvasItem
		if item == null:
			break
		alpha *= item.modulate.a
		if alpha <= 0.0:
			return 0.0
		walk = walk.get_parent()
	return alpha

func _screen_area(node: CanvasItem) -> float:
	# Only what the main frame pays for. An item inside a SubViewport is
	# measured against that viewport's rect and then divided by the root's
	# pixel count, which mixes two render targets into one ratio - the shop's
	# whole opaque=[] list came back as SidemenuSubViewport and Kollectadex
	# children, none of which touch the frame the player is looking at.
	if node.get_viewport() != get_tree().root:
		return 0.0

	if not _paints_anything(node):
		return 0.0

	# Godot skips a CanvasItem whose *inherited* modulate alpha is zero - the
	# whole subtree, before it reaches the rasteriser. Measured on the phone's
	# path with eight full-screen rects: modulate.a = 0 is 0.79ms, draws=0,
	# prims=0, against 28.8ms opaque. So a transparent layer is not a layer,
	# and counting it made this field describe the scene tree instead of the
	# frame.
	#
	# That is not hypothetical - it is what this field was reporting. Training
	# logged `over=7.2x top=.../MissVignette@1.0x` for a full-rect vignette
	# sitting at `modulate = Color(1, 1, 1, 0)` between misses, i.e. a layer
	# the GPU never touched. It also explains why every reading of `over=`
	# here failed to correlate with `gpu=`: 3.0x at 33.4ms against 3.1x at
	# 18.2ms was partly counting layers that were never drawn.
	#
	# `self_modulate` and a ColorRect's `color` are deliberately NOT part of
	# this test - both are per-item and Godot draws the item anyway, and the
	# same bench measured `color.a = 0` at 30.5ms, *more* than opaque. Only
	# the inherited `modulate` chain culls.
	if _inherited_modulate_alpha(node) <= 0.0:
		return 0.0

	var screen: Rect2 = Rect2(Vector2.ZERO, node.get_viewport_rect().size)
	if screen.size.x <= 0.0 or screen.size.y <= 0.0:
		return 0.0

	var rect: Rect2
	var control := node as Control
	if control != null:
		rect = control.get_global_rect()
	elif node.has_method("get_rect"):
		# Sprite2D and friends report a local rect; the transform puts it on
		# the screen and gives its axis-aligned bounds.
		rect = node.get_global_transform() * (node.call("get_rect") as Rect2)
	else:
		# A Node2D with no rect of its own draws through its children, which
		# are walked separately - counting it too would double up.
		return 0.0

	return rect.intersection(screen).get_area()

## The on-screen box _screen_area() measures the area of, for the one caller
## that needs the shape rather than the size. Split out rather than returning
## both, because every other caller wants a single number to compare.
func _screen_rect_of(node: CanvasItem) -> Rect2:
	var control := node as Control
	if control != null:
		return control.get_global_rect()
	if node.has_method("get_rect"):
		return node.get_global_transform() * (node.call("get_rect") as Rect2)
	return Rect2()

## Whether this CanvasItem puts any pixels on screen itself.
##
## A bare Control and every layout Container draw nothing at all - they place
## their children and that is the whole job - so counting their rect adds the
## screen several times over for nodes that never touch a pixel. The first
## version of over= did exactly that, and the device log shows the damage:
## first_boot_settings, a scene with a background and a few rows, reported
## over=7.1x with CenterContainer named as a full-screen cover, and every
## song reported top=ResultsScreen/LullabyResultsScreen - a bare Control.
##
## Anything with its own _draw() counts, whatever class it is: that is how a
## scripted Control that really does paint gets through, and it is the only
## honest way to tell one from a layout node, since both report get_class()
## as "Control".
func _paints_anything(node: CanvasItem) -> bool:
	if node.has_method("_draw"):
		return true

	var control := node as Control
	if control == null:
		# Node2D-side: a bare Node2D draws through its children, which are
		# walked separately. Anything with a rect of its own paints.
		return node.has_method("get_rect")

	# SubViewportContainer paints its viewport's texture, and PanelContainer
	# its stylebox; every other Container is pure layout.
	if control is Container:
		return control is SubViewportContainer or control is PanelContainer

	# A Control with nothing but children is layout too.
	return control.get_class() != "Control"

## The frame's own area, for turning a pixel sum into a multiple of it.
func _screen_px() -> float:
	var size: Vector2 = get_tree().root.get_visible_rect().size
	return size.x * size.y

## How completely a CanvasItem hides what is behind it, 0-1.
##
## The product of every alpha that applies: the item's own modulate and
## self_modulate, a ColorRect's colour, and every ancestor's modulate up to
## the scene root - because a rect at full alpha inside a parent faded to
## zero hides nothing, and the log would otherwise report it as a cover.
##
## Anything with a material is reported at face value; a shader can do
## whatever it likes with the alpha it is handed, and guessing is worse than
## saying what the scene asked for.
func _opaque_coverage(node: CanvasItem) -> float:
	if not _paints_anything(node):
		return 0.0

	var alpha: float = node.modulate.a * node.self_modulate.a
	var rect := node as ColorRect
	if rect != null:
		alpha *= rect.color.a

	var parent: Node = node.get_parent()
	while parent is CanvasItem:
		alpha *= (parent as CanvasItem).modulate.a
		parent = parent.get_parent()

	# Modulate is only half of an image's alpha and this used to report the
	# half it could see as the whole answer. The results screen's Vingette is
	# a full-rect TextureRect at modulate 1.0, so it was listed as a total
	# cover over the song - and its texture is a radial gradient running from
	# alpha 0.0 at the centre to 0.588 at the edge, which covers nothing and
	# never reaches opaque anywhere. Reading the texture per frame is far too
	# expensive for a census, so the honest answer is that this is unknown
	# rather than a number that looked like proof.
	if alpha >= 0.95 and not _alpha_is_knowable(node):
		return UNKNOWN_COVERAGE

	return alpha

## Reported instead of 1.0 for an item whose own pixels the census cannot see.
## Deliberately just under the threshold that counts as a cover, so an unknown
## never gets named as one - it shows up in covers_maybe= instead.
const UNKNOWN_COVERAGE := 0.94

## Whether this item's alpha is fully described by its modulate chain.
##
## A ColorRect carries its colour and a Panel its stylebox, so those are
## answerable. Anything drawing a texture, a font or a shader is not: the
## pixels decide, and the census only sees the tint applied over them.
func _alpha_is_knowable(node: CanvasItem) -> bool:
	if node is ColorRect:
		return node.material == null
	return false

## Reports how far a threaded load has got, at a few fixed fractions. Cheap
## enough to poll every frame: load_threaded_get_status() on a path that is
## not loading returns immediately, and the checkpoint counter means each
## fraction is only ever logged once.
func _poll_load_progress() -> void:
	if _loading_path.is_empty() or _load_checkpoints_done >= LOAD_CHECKPOINTS.size():
		return

	var progress: Array = [0.0]
	var status: int = ResourceLoader.load_threaded_get_status(_loading_path, progress)
	if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return

	# The old scene is unloaded before the request goes out, so by the time
	# the loader reports any progress at all its tree is gone and anything
	# still cached is being held by something else.
	_report_cache_residue()

	# One budget's worth per frame until the graph is exhausted, so deps=N/M
	# counts the whole scene rather than whatever fitted in the first 120ms.
	_continue_incoming_walk()
	# Shares the same window on purpose: both only run while a load is in
	# flight, which is when the loading screen is up and the frame has room.
	_continue_retained_sweep()

	var fraction: float = progress[0]

	# A line a second for as long as the load runs, whatever the fraction is
	# doing.
	#
	# The checkpoints answer "how far did it get", and on the shop's warm
	# load that turned out not to be enough: 50% at 1991ms and 51% at
	# 17933ms, so 15.9 seconds of the 18.0-second load sit inside one
	# checkpoint interval with nothing recorded in between. What is recorded
	# either side says it is not stuck - vram climbs 62->145MB across it and
	# the loading screen keeps rendering - so the shape of that climb is the
	# measurement, and only a fixed-interval sample can draw it. Every entry
	# already carries ram/vram/res, so this is one extra line per second and
	# no new counters.
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_loading_entry_ms >= LOADING_ENTRY_MS:
		_last_loading_entry_ms = now_ms
		var cached_before: int = _incoming_cached.size()
		var progress_text: String = _incoming_progress()

		# Same fraction as last sample? Bank it. Different? Report the run
		# that just ended, if it was long enough to matter.
		if is_equal_approx(fraction, _stall_fraction):
			_stall_samples += 1
		else:
			_flush_stall(now_ms, cached_before)
			_stall_fraction = fraction
			_stall_since_ms = now_ms
			_stall_samples = 1
			_stall_cached_at_start = cached_before

		_entry("LOADING", "%.1f%% at %dms %s status=%s" % [
			fraction * 100.0, now_ms - _scene_change_started_ms, progress_text,
			THREAD_STATUS_NAMES[status] if status >= 0 and status < THREAD_STATUS_NAMES.size() else str(status),
		])
	while (_load_checkpoints_done < LOAD_CHECKPOINTS.size()
			and fraction >= LOAD_CHECKPOINTS[_load_checkpoints_done]):
		var elapsed: int = Time.get_ticks_msec() - _scene_change_started_ms
		_entry("LOAD", "%.0f%% at %dms" % [LOAD_CHECKPOINTS[_load_checkpoints_done] * 100.0, elapsed])
		_load_checkpoints_done += 1

## Names what the scene we just left is still holding in the loader cache.
##
## Runs once per load, on the first frame the loader reports progress, which
## is after unload_current_scene(). Everything it touches is a lookup:
## get_dependencies() reads the file's dependency header without loading it
## (this is how the shop crash and the Hex animation bug were both found),
## and has_cached() is a hash lookup. One level deep on purpose - the
## recursive walk of a song is thousands of paths and this runs on a frame
## that is already loading.
##
## Reads as `RESIDUE <scene> packed=yes deps=412/517 ...` - the first three
## still-cached dependencies are named because "412 of 517" says how much is
## held and the names say by what.
func _report_cache_residue() -> void:
	if _residue_reported or _outgoing_scene_path.is_empty():
		return
	_residue_reported = true

	var packed_cached: bool = ResourceLoader.has_cached(_outgoing_scene_path)

	# Breadth-first over the whole graph, not just the scene's own header.
	# One level deep said 21000 resources are held and named none of them,
	# because a song's direct dependencies are a few dozen scenes and the
	# resources are inside those. RESIDUE_MAX_PATHS is what keeps this from
	# turning into the recursive walk it deliberately was not: the cap is
	# reported, so a truncated answer never reads as a complete one.
	var started: int = Time.get_ticks_usec()
	var seen: Dictionary = {}
	var queue: Array[String] = [_outgoing_scene_path]
	seen[_outgoing_scene_path] = true
	var visited: int = 0
	var cached: int = 0
	var capped: bool = false
	var by_kind: Dictionary = {}
	var examples: Array[String] = []

	while not queue.is_empty() and visited < RESIDUE_MAX_PATHS:
		# Same time budget as the incoming walk, and for the same reason: this
		# runs on a frame that is already loading.
		if Time.get_ticks_usec() - started > PROBE_BUDGET_USEC:
			capped = true
			break
		var path: String = queue.pop_front()
		visited += 1

		if ResourceLoader.has_cached(path):
			cached += 1
			# Grouped by extension because that is what says *what* is being
			# held: .res is the texture importer's output, .tscn/.scn a
			# scene, .tres a resource someone authored. "1400 textures still
			# cached" and "3 scenes still cached" are different bugs.
			var kind: String = path.get_extension()
			by_kind[kind] = by_kind.get(kind, 0) + 1
			if examples.size() < 4 and path != _outgoing_scene_path:
				examples.append(path.get_file())

		# get_dependencies() reads the file's own header; it does not load
		# it, and it works on paths whose resources are not importable here.
		for dep in ResourceLoader.get_dependencies(path):
			# Entries are "uid::type::path" or a bare path; path is last.
			var dep_path: String = dep.get_slice("::", dep.count("::"))
			if dep_path.is_empty() or seen.has(dep_path):
				continue
			seen[dep_path] = true
			queue.append(dep_path)

	var kinds: Array = []
	for kind in by_kind:
		kinds.append([by_kind[kind], kind])
	kinds.sort_custom(func(a, b): return a[0] > b[0])
	var kind_parts: PackedStringArray = []
	for i in mini(5, kinds.size()):
		kind_parts.append("%s=%d" % [kinds[i][1], kinds[i][0]])

	_residue_walk_usec = Time.get_ticks_usec() - started
	_probe_usec += _residue_walk_usec
	_probe_residue_usec += _residue_walk_usec

	_entry("RESIDUE", "%s packed=%s cached=%d/%d%s walk=%.1fms [%s] %s" % [
		_outgoing_scene_path.get_file(),
		"yes" if packed_cached else "no",
		cached,
		visited,
		" (capped)" if capped or visited >= RESIDUE_MAX_PATHS else "",
		_residue_walk_usec / 1000.0,
		" ".join(kind_parts),
		", ".join(examples),
	])
	_start_retained_sweep()

## Asks the engine which resources in the whole project are still cached once a
## scene is gone, and reports them grouped.
##
## RESIDUE answers a narrower question and cannot be widened to this one: it
## walks the outgoing scene's declared dependencies, of which Monochrome has
## 64, and the device log shows 21,279 resources surviving that unload. The
## overwhelming majority of what stays is therefore not a declared dependency
## of the scene that brought it in, and no walk starting from the scene will
## ever find it.
##
## Nor can it be found off-device. Run against this checkout the standing tool
## reports Monochrome mounting 4,914 resources and retaining 62 - against
## 23,589 and 21,279 on the phone. The gap is the imported textures, which a
## developer checkout does not have, so the objects that leak there are never
## created here. The measurement has to happen on the device.
##
## Godot exposes no enumeration of the resource cache to GDScript - there is no
## get_cached_resources() - but has_cached() answers per path and
## list_directory() walks res://. Asking every file in the project is therefore
## possible, just not free: it is thousands of hash lookups, so it is budgeted
## per frame and resumable, exactly like the incoming-dependency probe.
##
## It runs immediately after an unload, which is when the loading screen is up
## and the main thread has 18 to 28 seconds of nothing to do. Once per unload,
## and it stops itself the moment the next scene arrives.
const SWEEP_BUDGET_USEC := 2_000
const SWEEP_SKIP_DIRS := [".godot", "reference", "precompiled_astc_imports",
	"precompiled_texture_imports", "precompiled_lightmap_imports"]

var _sweep_dirs: Array[String] = []
var _sweep_files: Array[String] = []
var _sweep_cached: Dictionary = {}

## A sample of the retained paths themselves, capped. See the sweep loop.
const SWEEP_MAX_NAMES := 24
var _sweep_names: PackedStringArray = PackedStringArray()
var _sweep_seen: int = 0
var _sweep_active: bool = false
var _sweep_usec: int = 0

func _start_retained_sweep() -> void:
	_sweep_dirs = ["res://"]
	_sweep_files = []
	_sweep_cached = {}
	_sweep_names = PackedStringArray()
	_sweep_seen = 0
	_sweep_usec = 0
	_sweep_active = true

func _continue_retained_sweep() -> void:
	if not _sweep_active:
		return

	var started: int = Time.get_ticks_usec()

	# Files first, and only until the budget is out. has_cached() is 0.6
	# microseconds measured, so this is thousands of paths per call.
	while not _sweep_files.is_empty():
		if Time.get_ticks_usec() - started >= SWEEP_BUDGET_USEC:
			_sweep_usec += Time.get_ticks_usec() - started
			return
		var path: String = _sweep_files.pop_back()
		_sweep_seen += 1
		if ResourceLoader.has_cached(path):
			# Grouped as it goes. Keeping 21,000 paths to group at the end
			# would cost more memory than the thing being measured.
			var key: String = _sweep_key(path)
			_sweep_cached[key] = int(_sweep_cached.get(key, 0)) + 1
			# Names too, up to a cap, because the counts have run out of what
			# they can say. Four rounds of static reasoning failed to find what
			# holds these - preloads are 22 files and 1.1MB, the gdanimate
			# statics are counters cleared on every read, the debug autoload is
			# 19 files, the gameover module keeps metadata - so the question is
			# no longer how many but which.
			#
			# Scripts excluded: GDScript keeps every script it ever loaded, 136
			# of them are expected, and listing those would spend the cap on the
			# one group already understood.
			if _sweep_names.size() < SWEEP_MAX_NAMES and not path.ends_with(".gd"):
				_sweep_names.append(path.trim_prefix("res://"))

	if _sweep_dirs.is_empty():
		_sweep_usec += Time.get_ticks_usec() - started
		_finish_retained_sweep()
		return

	# Exactly one directory per call, whatever the budget says.
	#
	# A listing cannot be split part way, and the first version treated one as
	# a free action inside the budgeted loop - it checked the clock before
	# taking a directory and then ran the whole listing regardless of how long
	# that took. A directory of a few thousand entries then blew a 2ms budget
	# to 358ms in one frame, which is precisely the stall this sweep is
	# supposed to be quiet enough to measure. One listing is bounded by the
	# largest directory in the project, measured at 9.6ms.
	var dir: String = _sweep_dirs.pop_back()
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			var name: String = entry.trim_suffix("/")
			if not SWEEP_SKIP_DIRS.has(name):
				_sweep_dirs.append(dir.path_join(name))
		else:
			_sweep_files.append(dir.path_join(entry))

	_sweep_usec += Time.get_ticks_usec() - started

func _finish_retained_sweep() -> void:
	_sweep_active = false

	var total: int = 0
	var rows: Array = []
	for key in _sweep_cached:
		total += int(_sweep_cached[key])
		rows.append([int(_sweep_cached[key]), key])
	rows.sort_custom(func(a, b): return a[0] > b[0])

	var parts: PackedStringArray = PackedStringArray()
	for i in mini(10, rows.size()):
		parts.append("%s=%d" % [rows[i][1], rows[i][0]])

	# Says so when the next scene arrived first. A partial sweep is still worth
	# reading - the grouping is the finding, not the total - but a partial
	# total read as a whole one would understate the retention.
	var incomplete: bool = not _sweep_files.is_empty() or not _sweep_dirs.is_empty()
	_entry("RETAINED", "%d/%d examinados siguen cacheados tras soltar %s%s sweep=%.0fms [%s]" % [
		total, _sweep_seen, _outgoing_scene_path.get_file(),
		" (incompleto)" if incomplete else "",
		_sweep_usec / 1000.0, " ".join(parts),
	])
	if not _sweep_names.is_empty():
		_entry("RETAINEDBY", "%s" % " ".join(_sweep_names))

## Folder plus extension, which is the grouping that names a subsystem rather
## than a file. "songs/monochrome:png" says where to look; a list of 3,000
## filenames does not.
func _sweep_key(path: String) -> String:
	var rel: String = path.trim_prefix("res://")
	var parts: PackedStringArray = rel.split("/")
	var folder: String = "/".join(parts.slice(0, mini(2, parts.size() - 1)))
	return "%s:%s" % [folder if not folder.is_empty() else ".", path.get_extension()]

## Files one frame into the histogram and checks it against the refresh clock.
##
## Two counters, both cheap enough to run every frame - a compare chain and an
## fmod - which is the point: a histogram assembled from sampled frames would
## miss exactly the tail it exists to describe.
func _record_frame_shape(frame_ms: float) -> void:
	if _frame_hist.size() != FRAME_BUCKET_LABELS.size():
		_frame_hist.resize(FRAME_BUCKET_LABELS.size())
		_frame_hist.fill(0)

	var bucket: int = FRAME_BUCKET_EDGES.size()
	for i in FRAME_BUCKET_EDGES.size():
		if frame_ms < FRAME_BUCKET_EDGES[i]:
			bucket = i
			break
	_frame_hist[bucket] += 1
	_hist_frames += 1

	# Rounded to the nearest whole interval, so 33.3ms is "two intervals" and
	# 25ms is not near any of them. Frames faster than one interval are not
	# counted as aligned - the compositor cannot have paced those.
	var intervals: float = roundf(frame_ms / _refresh_ms)
	if intervals >= 1.0 and absf(frame_ms - intervals * _refresh_ms) <= VSYNC_TOLERANCE_MS:
		_hist_aligned += 1

## Renders the histogram and clears it for the next interval.
##
## Empty buckets are left out. A HEARTBEAT at a solid 60fps then reads
## `hist=[12-20:300] vsync=99%@60Hz` - one bucket, everything aligned - and a
## scene that is genuinely working too hard spreads across three or four with
## vsync well under half. Those are the two answers this was built to tell
## apart, and the difference is visible without reading a single number.
func _take_frame_shape() -> String:
	var parts: PackedStringArray = []
	for i in mini(_frame_hist.size(), FRAME_BUCKET_LABELS.size()):
		if _frame_hist[i] > 0:
			parts.append("%s:%d" % [FRAME_BUCKET_LABELS[i], _frame_hist[i]])

	var aligned_pct: float = 0.0
	if _hist_frames > 0:
		aligned_pct = 100.0 * float(_hist_aligned) / float(_hist_frames)

	var shape: String = "hist=[%s] vsync=%.0f%%@%.0fHz" % [" ".join(parts), aligned_pct, _refresh_hz]

	_frame_hist.fill(0)
	_hist_frames = 0
	_hist_aligned = 0
	return shape

## Compares this stretch of the session against the first one. A phone that
## has warmed up runs the same scene slower, and that shows up here as the
## median drifting upward with nothing else in the log changing - which is
## the difference between "this scene is heavy" and "this device is hot".
func _write_summary() -> void:
	if _bucket_frames == 0:
		return

	var mean_ms: float = _bucket_ms_total / float(_bucket_frames)
	if _first_bucket_median <= 0.0:
		_first_bucket_median = mean_ms

	var drift: float = (mean_ms / _first_bucket_median - 1.0) * 100.0
	_entry("SUMMARY", "frames=%d mean=%.1fms (%.0f fps) worst=%.1fms vs_first=%+.0f%%" % [
		_bucket_frames, mean_ms, 1000.0 / maxf(mean_ms, 0.001), _bucket_worst_ms, drift,
	])

	_bucket_frames = 0
	_bucket_ms_total = 0.0
	_bucket_worst_ms = 0.0

## Subscribes to every AnimationPlayer in the new scene so a stall can name
## what began on it. Connections are dropped implicitly when the old scene is
## freed; the array is only cleared so it does not hold freed references.
func _watch_animations() -> void:
	_watched_players.clear()
	_last_anim = ""

	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return

	var nodes: Array[Node] = [scene]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		var player := node as AnimationPlayer
		if player != null:
			_watched_players.append(player)
			if not player.animation_started.is_connected(_on_animation_started):
				player.animation_started.connect(_on_animation_started.bind(player))
		for child in node.get_children():
			nodes.append(child)

	_refresh_sub_viewports()

## Collects the scene's SubViewports and enables the same GPU/CPU timestamp
## queries the main viewport already has. Off by default per viewport, so
## without this the sums below would read a flat 0 and look like "no
## SubViewport cost", which is the failure mode this whole field exists to
## stop repeating.
func _refresh_sub_viewports() -> void:
	_sub_viewports.clear()

	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return

	var nodes: Array[Node] = [scene]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		var viewport := node as SubViewport
		if viewport != null:
			_sub_viewports.append(viewport)
			RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		for child in node.get_children():
			nodes.append(child)

## Where a node sits relative to the current scene root, for the log.
##
## sub_top= used to print viewport.name, and "SubViewport" is what every one
## of them is called. Monochrome's log named a live SubViewport(256x256) that
## matches nothing authored anywhere in its tree - the only SubViewport in
## any scene it can reach is the results screen's, which is the Godot default
## 512x512 (checked against the 4.7.1 binary, not from memory) and ships
## UPDATE_DISABLED. A name cannot be looked up; a path can.
func _scene_relative_path(node: Node) -> String:
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene == null or not scene.is_ancestor_of(node):
		return str(node.get_path())
	return str(scene.get_path_to(node))

func _on_animation_started(anim: StringName, player: AnimationPlayer) -> void:
	_last_anim = "%s/%s" % [player.name, anim]
	_last_anim_ms = Time.get_ticks_msec()

## The graphics settings actually in force, as one line.
##
## Every one of these is a per-pixel cost, which is what matters now that
## gpu= has shown Chimera to be GPU-bound rather than CPU-bound: the frame
## is 38ms and the GPU accounts for 38.8ms of it, while draw calls and
## primitives barely correlate with it. Knowing which of shadows / MSAA /
## post-processing / render scale was on turns "the GPU was busy" into
## "the GPU was busy doing X".
func _graphics_summary() -> String:
	var msaa_names := ["off", "2x", "4x", "8x"]
	var msaa: int = clampi(int(Settings.graphics_msaa_3d_quality), 0, 3)
	var preset = Settings.get_quality_preset()
	var aniso_names := ["off", "2x", "4x", "8x", "16x"]
	var aniso: int = clampi(int(Settings.graphics_anisotropic_filtering), 0, 4)
	# screen_space_aa es un pase de pantalla completa y es campo del preset
	# (SMAA en High, FXAA en Medium, apagado en Low y Very Low) - y no estaba
	# en esta linea. En `dcb37c09` un jugador barrio la pestaña de Graficos
	# fila a fila en la tienda y a los 171.72s el `vp=` del log paso de
	# `ssaa2 aniso2` a `ssaa1 aniso1` de golpe, mientras esta linea solo podia
	# informar de la mitad: `aniso=4x -> 2x`. El frame bajo 3.4ms en ese paso
	# y no hay forma de saber cual de las dos filas lo hizo. En una pantalla
	# de 2.66 Mpx el pase de SMAA no es lo pequeño de los dos.
	var ssaa_names := ["off", "fxaa", "smaa"]
	var ssaa: int = clampi(int(Settings.graphics_screen_space_aa_quality), 0, 2)
	# aniso/lod/light_fade are logged because they are only ever set by a
	# preset - on Custom they sit at their defaults and do nothing, which is
	# invisible otherwise and made a whole run unattributable once.
	return "preset=%s scale=%s aspect=%s msaa=%s ssaa=%s shadows=%s atlas=%d filter=%d ssao=%s ssil=%s post=%d sha_fx=%s aniso=%s lod=%.1f light_fade=%.1f phys_hz=%d target_fps=%d flashing=%s" % [
		preset.name if preset != null else "Custom",
		_render_scale(),
		"Wide" if Settings.display_screen_aspect == Window.ContentScaleAspect.CONTENT_SCALE_ASPECT_EXPAND else "Normal",
		msaa_names[msaa],
		ssaa_names[ssaa],
		"on" if Settings.graphics_shadows_enabled else "off",
		Settings.graphics_positional_shadow_atlas_size,
		Settings.graphics_positional_shadow_filter_quality,
		"on" if Settings.graphics_ssao else "off",
		"on" if Settings.graphics_ssil else "off",
		int(Settings.graphics_post_processing),
		"off" if Settings.graphics_disable_shader_effects else "on",
		aniso_names[aniso],
		Settings.graphics_mesh_lod_threshold,
		Settings.graphics_light_distance_fade,
		Engine.physics_ticks_per_second,
		Settings.display_target_fps,
		# The one setting that decides whether four full-screen black
		# ColorRects are suppressed, and it has never appeared in a log.
		#
		# flashing_check.gd hides its node only when this is off. Chimera
		# carries it on CameraFlash, BlackBoxofAwesomeness, UIBlack and Black2 -
		# three of them 1920x1080 rects whose animations key visible=true with a
		# single key at t=0, and whose colour track reads opaque black for the
		# first three minutes of the song because Godot holds a track's first
		# value for everything before it.
		#
		# So with this on, the reported black graphic is the data behaving as
		# authored and the suppressor is doing nothing; with it off, the
		# suppressor should make it impossible. Two opposite diagnoses from one
		# symptom, and no log so far could tell them apart.
		"on" if Settings.get(&"game_flashing_lights") else "off",
	]

## Settings.applied fires on every option row the player touches, so this
## rate-limits to actual changes - otherwise scrolling the console would
## bury the log in identical lines.
func _on_settings_applied() -> void:
	# The row on the boot screen, and the one in the console's Misc tab, both
	# land here. Turning the log on has to start it on this launch or the row
	# is a lie: an autoload is ready before the first scene, so by the time
	# anyone can touch a setting this node has long since decided.
	#
	# What it cannot do is recover what already happened. A log started here
	# opens with its header and this SETTINGS line and nothing before them, so
	# the boot it missed stays missing. The row is still the only place the log
	# can be armed in time to record a shop load, and the gap is visible in the
	# file rather than implied.
	if Settings.lullaby_diagnostics_log:
		_start_logging()
	elif _running:
		_stop_logging()
		return

	if not _running:
		return

	var summary: String = _graphics_summary()
	if summary == _last_graphics_summary:
		return
	_last_graphics_summary = summary
	_entry("SETTINGS", summary)

## Closes the file and stops the per-frame work, leaving the node able to start
## again if the setting comes back on.
func _stop_logging() -> void:
	if not _running:
		return

	_entry("SHUTDOWN", "log apagado desde los ajustes")
	_running = false
	set_process(false)

	# Same order as the teardown in _notification, and for the same reason:
	# stop() joins the sampler thread, so it has to finish writing before the
	# file it writes beside is closed. It also has to happen at all - _open_log
	# makes a new sampler every time, so leaving this one running would have
	# each on/off cycle stack another thread writing another .mem trace.
	if _sampler != null:
		_sampler.stop()
		_sampler = null

	if _file != null:
		_file.flush()
		_file.close()
		_file = null

## Public so anything can drop a marker into the log - e.g. a mechanic
## starting, or a cutscene the player says "it breaks here".
func mark(what: String) -> void:
	_entry("MARK", what)

## Rebuilds every watch list against whatever is current_scene now.
##
## Normally this happens a second after SceneChanger reports a scene change
## finished, which covers the game. It does not cover a scene put into the tree
## by hand - tools/harness/scene_probe.tscn does exactly that, and without this
## the autoload profiles the harness instead: no BLACKWATCH, no BLACKOUT, and a
## log that reads like "nothing covers the screen" when the truth is "nothing
## was looked at".
func rescan_scene() -> void:
	_collect_blackout_watch()

func _on_error_logged(kind: String, message: String, err: int) -> void:
	_entry(kind.to_upper(), "%s (error %d)" % [message.replace("\n", " | "), err])

## From ErrorLog: an engine error or a push_error/push_warning, first
## occurrence only. `where` is the C++ file, line and function that raised it,
## which is what separates "our bug" from "the driver's".
func _on_error_captured(kind: String, where: String, message: String) -> void:
	_entry(kind, "%s  [%s]" % [message.replace("\n", " | "), where])

func _on_scene_change_started(path: String) -> void:
	_scene_change_started_ms = Time.get_ticks_msec()
	_dep_ms = {}
	_dep_count = {}
	_dep_clock = _scene_change_started_ms
	_scene_change_memory = OS.get_static_memory_usage()
	_loading_path = path
	_load_checkpoints_done = 0
	var outgoing: Node = get_tree().current_scene if is_inside_tree() else null
	_outgoing_scene_path = outgoing.scene_file_path if outgoing != null else ""
	_residue_reported = _outgoing_scene_path.is_empty()
	_last_loading_entry_ms = Time.get_ticks_msec()
	_last_census_counts.clear()
	_stall_fraction = -1.0
	_stall_samples = 0
	_stall_cached_at_start = 0
	_probe_usec = 0
	_residue_walk_usec = 0
	_probe_walk_usec = 0
	_probe_progress_usec = 0
	_probe_residue_usec = 0
	_collect_incoming_deps(path)
	# deps=/walk= are what this file costs the load it is measuring. Named on
	# the way out as well as the way in, because the walk happens here and a
	# load that never finishes still records what the walk took.
	_entry("SCENE_OUT", "%s deps=%d walk=%.1fms%s" % [
		path, _incoming_deps.size(), _incoming_walk_usec / 1000.0,
		" (capped)" if _incoming_deps.size() >= INCOMING_MAX_PATHS
			or _incoming_walk_usec > PROBE_BUDGET_USEC else "",
	])

func _on_scene_change_finished(path: String) -> void:
	# Before _loading_path is cleared, so a load that stalled and then simply
	# finished still reports the window.
	_flush_stall(Time.get_ticks_msec(), _incoming_cached.size())
	var took: int = Time.get_ticks_msec() - _scene_change_started_ms
	var delta_mb: float = float(OS.get_static_memory_usage() - _scene_change_memory) / 1048576.0
	_loading_path = ""
	# probe= is every microsecond this file spent measuring the load, against
	# took= for the load itself. The one number that says whether the
	# diagnostics are part of what they are reporting.
	# Reported before the new scene starts allocating, or its resources would
	# be counted as the old one's residue.
	if _sweep_active:
		_finish_retained_sweep()

	# Split three ways, plus the sweep, which was never in probe= at all.
	#
	# graph= is the breadth-first walk over get_dependencies() that builds the
	# deps=N/M denominator; prog= is the once-a-second has_cached() pass over
	# what is still missing; res= is the outgoing scene's residue walk; and
	# sweep= is _continue_retained_sweep, which reports separately on RETAINED
	# and so read as free on this line. On Chimera that hidden one is another
	# 597ms next to probe=1507ms, so the honest total was never printed.
	_entry("SCENE_IN", "%s took=%dms probe=%.1fms(graph=%.0f prog=%.0f res=%.0f) sweep=%.0fms memory_delta=%+.1fMB sys=%s" % [
		path, took, _probe_usec / 1000.0,
		_probe_walk_usec / 1000.0, _probe_progress_usec / 1000.0,
		_probe_residue_usec / 1000.0, _sweep_usec / 1000.0,
		delta_mb, _sys_mem(),
	])
	# Which part of the scene the wall time went to. The shop opens 397 files
	# in 17.9s and Monochrome 197 in 4.2s with more megabytes, so the cost is
	# per file - and console.tscn is 97 of the shop's 397 while the log shows
	# the console not switching on until 3.5s after the scene is up.
	_entry("DEPCOST", "%s %s" % [path.get_file(), _dep_breakdown()])
	_watch_swap(path)
	# The frame window is meaningless across a load, and every frame after one
	# would otherwise read as a spike against the pre-load median.
	_frames_seen = 0
	_frame_times.fill(0.0)
	# Deferred twice over: the scene is swapped in but its own _ready() work
	# (and anything it starts playing) has not run yet on this frame.
	# Both deferred by a second: current_scene is not set on the frame the
	# change happens, so call_deferred() ran against the old scene and the
	# watcher silently subscribed to nothing - which is why not one SPIKE in
	# the last device log carried an "after ..." attribution.
	get_tree().create_timer(1.0).timeout.connect(census.bind("after load"), CONNECT_ONE_SHOT)
	# Same delay and the same reason: the tree has to have settled.
	get_tree().create_timer(1.0).timeout.connect(_collect_blackout_watch, CONNECT_ONE_SHOT)
	get_tree().create_timer(1.0).timeout.connect(_watch_animations, CONNECT_ONE_SHOT)

## Splits the one window this log cannot currently see into three.
##
## SCENE_IN is emitted from LullabySceneChanger._complete(), two lines before
## it calls change_scene_to_packed(). On the Collector's Shop in a release
## build that is the last line the log ever writes: the process is gone
## before the CENSUS a second later, and since every entry is flushed as it
## is written, that is where it died and not merely where the buffer ended.
##
## change_scene_to_packed() is atomic from the outside and does three things
## that fail in completely different ways - it instantiates the PackedScene
## (CPU and RAM: 1698 resources at once), it puts that tree in the scene tree
## (every _ready() in the scene runs), and then the first frame draws it (the
## GPU cost this project already measured at 35.6 seconds and 154 pipelines).
## An out-of-memory kill, a script fault and a driver fault are all consistent
## with the log as it stands, and they need three different fixes.
##
## So: node_added fires as the new tree is installed, which cannot happen
## until instantiate() has returned, and process_frame fires once the whole
## tree's _ready() has run. Which of the three marks is missing names the
## phase.
##
##     SCENE_IN, then nothing            -> died inside instantiate()
##     SCENE_IN INSTANCED, then nothing  -> died in some node's _ready()
##     SCENE_IN INSTANCED SCENE_UP, then nothing -> died on the first draw
##
## Both connections are one-shot. node_added fires for every node in the
## scene - thousands of them here - and a listener left attached would cost
## more than what it is measuring.
func _watch_swap(path: String) -> void:
	_swap_path = path
	_swap_requested_ms = Time.get_ticks_msec()
	get_tree().node_added.connect(_on_swap_node_added, CONNECT_ONE_SHOT)

func _on_swap_node_added(node: Node) -> void:
	# Named rather than assumed. The first node added after the request should
	# be the new scene's root, but if some other node happens to arrive first
	# the entry says so instead of quietly mislabelling the phase.
	_entry("INSTANCED", "%s first=%s (%s) after=%dms sys=%s" % [
		_swap_path.get_file(), node.name, node.get_class(),
		Time.get_ticks_msec() - _swap_requested_ms, _sys_mem(),
	])
	get_tree().process_frame.connect(_on_swap_frame, CONNECT_ONE_SHOT)

func _on_swap_frame() -> void:
	_entry("SCENE_UP", "%s ready+drawn after=%dms nodes=%d res=%d sys=%s" % [
		_swap_path.get_file(), Time.get_ticks_msec() - _swap_requested_ms,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		_sys_mem(),
	])
	_swap_path = ""

## Two levels below res://, which is the grain that names a subsystem.
func _dep_owner(path: String) -> String:
	var rel: String = path.trim_prefix("res://")
	var parts: PackedStringArray = rel.split("/")
	if parts.size() <= 1:
		return "."
	return "/".join(parts.slice(0, mini(3, parts.size() - 1)))

## Where a load's wall time went, by subsystem, worst first, plus the tail as
## one number.
##
## The cap used to be a flat top 6, and that turned a truncation into a wrong
## conclusion. The Collector's Shop load of 2026-08-25 took 36.9s and printed:
##
##     assets/collector=5.9s/186 scripts/lullaby=2.2s/73 resources/audio=1.8s/44
##     resources/animations=1.1s/28 assets/menus=0.8s/38 resources/shaders=0.5s/11
##
## Six rows adding up to 12.3 seconds against a 36.9 second load, which reads
## as "24.6 seconds unaccounted for" - it was the first thing I concluded from
## it - when most or all of that was simply rows 7 and beyond, never printed.
## That is the difference between "something invisible is eating two thirds of
## the load" and "the cost is spread across a long tail", and those two want
## opposite fixes: hunt a culprit, or merge files.
##
## So: every bucket worth at least 1% of the load gets a row, everything below
## that collapses into `resto=`, and `suma=` closes the question the top 6
## left open - bounded output that reconciles against `took=` by itself.
##
## `suma=` is not decoration. _incoming_progress() charges each poll interval
## to whatever arrived in it and charges an interval where NOTHING arrived to
## nobody, so the sum is a lower bound on the load, not an identity. If
## `suma=` comes back well under `took=`, the gap is time the loader thread
## spent producing nothing - a stall to explain, not a bucket to merge - and
## until now there was no way to tell that apart from truncation.
func _dep_breakdown() -> String:
	if _dep_ms.is_empty():
		return "-"
	var rows: Array = []
	var total: float = 0.0
	for owner in _dep_ms:
		var ms: float = float(_dep_ms[owner])
		total += ms
		rows.append([ms, owner, int(_dep_count.get(owner, 0))])
	rows.sort_custom(func(a, b): return a[0] > b[0])

	var floor_ms: float = total * 0.01
	var parts: PackedStringArray = PackedStringArray()
	var tail_ms: float = 0.0
	var tail_n: int = 0
	for row in rows:
		if float(row[0]) >= floor_ms:
			parts.append("%s=%.1fs/%d" % [row[1], float(row[0]) / 1000.0, int(row[2])])
		else:
			tail_ms += float(row[0])
			tail_n += int(row[2])
	if tail_n > 0:
		parts.append("resto=%.1fs/%d en %d" % [tail_ms / 1000.0, tail_n, rows.size() - parts.size()])
	parts.append("suma=%.1fs" % [total / 1000.0])
	return " ".join(parts)

## The render scale the viewport is actually using, and the setting beside it
## when they disagree.
##
## Both places that printed a scale read Settings.graphics_render_scale, which
## is what the setting asks for and not what the window does. settings.gd
## applies it with window.scaling_3d_scale, so anything that recreates or
## resets that state leaves the log confidently printing 0.50 over a viewport
## rendering at full size - and the difference between 800x360 and 1600x720 is
## four times the pixels, which is the order of the gap this is being used to
## explain.
##
## Chimera holds gpu= at 34ms where the shop sits at 14 with more meshes, more
## lights and ASTC on all 553 MPx of its textures, and 288k pixels at 7x
## overdraw is not 34ms of an Adreno 619. Whether it is really rendering at
## the scale it claims is the cheapest remaining thing to rule out, and it
## cannot be ruled out by reading a setting.
## is_inside_tree() rather than get_tree() as the guard, here and at the six
## other places this file asks for the current scene.
##
## get_tree() does not return null quietly - Node::get_tree() is an
## ERR_FAIL_NULL_V, so it prints "Parameter data.tree is null" and then returns
## null. Guarding a get_tree() call with another get_tree() call therefore
## prevents the crash and causes the error message twice over. Build #115's log
## carried seventeen of them, one per headless run, all from this file, and
## none of them in #114 - which is what a new one-line mistake looks like from
## the outside. On device it is one more error line in the log this whole
## system exists to make readable.
## Splits the frame's draw work between the 3D pass, shadow rendering and the
## 2D canvas.
##
## `draw=`/`prims=`/`objs=` are `Performance.RENDER_TOTAL_*` - one number for
## everything the frame drew - and "everything" spans two renderers with
## completely different cost models. **The 3D runs at `scaling_3d_scale` and
## the canvas does not.** On this device at 0.50 that is 800x360 against
## 1600x720, so one full-screen 2D layer covers 4x the pixels of the entire 3D
## pass. A frame of 39 3D calls and 16 canvas calls is a different problem from
## the reverse, and until this there was nothing in the log that could tell
## those two apart - every question about "is it the 2D or the 3D" came back
## unanswerable.
##
## It is also the field the counter-based dead ends were missing. `objs`,
## `draw` and `prims` correlate with `gpu` at +0.16, +0.24 and +0.26, and the
## most expensive frame of Chimera draws *fewer* objects than the cheapest -
## but those are totals, so a 3D pass shrinking while a 2D overlay grows reads
## as "no change" in all three.
##
## Free. These are counters the renderer already keeps per viewport - not a
## readback, not a second pass, no debug draw mode. Verified against the real
## renderer under Xvfb: a scene with one cube and one ColorRect reports
## 3d=1 draw / 2d=1 draw and `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` = 2.
##
## Order in each group is draw/prims/objs, matching the order the standalone
## `draw=`, `prims=` and `objs=` fields appear in the line.
func _render_split() -> String:
	if not is_inside_tree():
		return "-"
	var rid: RID = get_viewport().get_viewport_rid()
	var parts: PackedStringArray = PackedStringArray()
	for pair in [
		[RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, "3d"],
		[RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, "sha"],
		[RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, "2d"],
	]:
		var kind: int = pair[0]
		parts.append("%s=%d/%d/%d" % [
			pair[1],
			RenderingServer.viewport_get_render_info(rid, kind,
				RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, kind,
				RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, kind,
				RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		])
	return " ".join(parts)

func _render_scale() -> String:
	var actual: float = 1.0
	var root_window: Window = get_tree().root if is_inside_tree() else null
	if root_window != null:
		actual = root_window.scaling_3d_scale
	var asked: float = Settings.graphics_render_scale
	if is_equal_approx(actual, asked):
		return "%.2f" % actual
	return "%.2f(pedido %.2f)" % [actual, asked]

func _median_frame_ms() -> float:
	if _frames_seen < WINDOW_SIZE:
		return 16.6
	var sorted: Array = Array(_frame_times)
	sorted.sort()
	return sorted[WINDOW_SIZE / 2]

## Running total of GPU render pipelines the engine has had to compile.
##
## This is the field that settles the cutscene stalls. `frame` is clamped by
## Godot at 150ms so it cannot show a real freeze, `proc` showed 1878ms on
## `122_fall` but covers the whole process step, and every other counter
## stayed flat through it - vram_delta was +0.0MB (so not texture upload) and
## ram was flat (so not loading). Compiling a pipeline is the one remaining
## candidate and, until 4.7 exposed these, the one thing the log could not
## see at all.
##
## Summed across all five sources rather than logged separately: the question
## is only "did the engine stop to build pipelines on this frame, and how
## many", and one number per line keeps the entry readable. A jump on exactly
## the stall frames confirms it; a flat 0 kills it and the search moves on.
## The five pipeline-compilation counters Godot exposes, in print order.
## Named rather than inlined because both the total and the per-source
## breakdown walk the same list.
const PIPELINE_SOURCES: Array[Dictionary] = [
	{&"label": "can", &"info": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS},
	{&"label": "mesh", &"info": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH},
	{&"label": "surf", &"info": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE},
	{&"label": "draw", &"info": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW},
	{&"label": "spec", &"info": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION},
]

## Per-source pipeline totals at the previous entry, for the deltas.
var _last_pipeline_sources: PackedInt32Array = PackedInt32Array()

func _pipeline_compilations() -> int:
	var total: int = 0
	for source in PIPELINE_SOURCES:
		total += int(RenderingServer.get_rendering_info(source[&"info"]))
	return total

## Which kind of pipeline the engine compiled since the last entry.
##
## pipe=N(+D) says the engine stopped to build D pipelines and never which
## D. That matters because the two open pipeline questions have opposite
## answers: the multi-second cutscene stalls should be mesh/surface work
## (a skinned character with morph targets drawn for the first time), while
## the Collector's Shop compiling +134 pipelines on its *second* load -
## more than the +53 its first load cost, for a scene whose materials the
## process has already seen - should be canvas if it is the console's 2D UI
## and mesh if it is the room. One counter cannot tell those apart; five
## can.
func _pipeline_breakdown() -> String:
	if _last_pipeline_sources.size() != PIPELINE_SOURCES.size():
		_last_pipeline_sources.resize(PIPELINE_SOURCES.size())
		_last_pipeline_sources.fill(0)

	var parts: PackedStringArray = []
	for i in PIPELINE_SOURCES.size():
		var now: int = int(RenderingServer.get_rendering_info(PIPELINE_SOURCES[i][&"info"]))
		parts.append("%s+%d" % [PIPELINE_SOURCES[i][&"label"], now - _last_pipeline_sources[i]])
		_last_pipeline_sources[i] = now
	return " ".join(parts)

## Every entry carries the whole counter set. It makes lines long, but it
## means a single line answers "what was happening", instead of having to
## correlate it against the nearest heartbeat.
## `gpu` y `sub_gpu` con el pestillo puesto. Un cero de un driver que no
## contesta y un cero de un frame que no dibuja son el mismo texto, y el
## primero ha pasado por medida en todos los analisis cruzados de este
## proyecto. `n/d` no lo puede leer nadie como una medida.
func _gpu_field(value: float) -> String:
	return "n/d" if _gpu_timing_unsupported else "%.2f" % value


func _entry(kind: String, detail: String) -> void:
	if _file == null:
		return

	var seconds: float = float(Time.get_ticks_msec() - _session_start_ms) / 1000.0
	var pipelines: int = _pipeline_compilations()
	var pipe_delta: int = pipelines - _last_pipelines
	_last_pipelines = pipelines
	# Must be read once per entry and in this order - it stores its own
	# per-source baseline, so calling it twice would zero the second read.
	var pipe_sources: String = _pipeline_breakdown()

	# Frames the engine actually drew against frames it processed. Godot can
	# run a process step without presenting - and everything else in this
	# line is per-frame, so a stretch where those two diverge makes every
	# other counter mean something different. It is also the only read the
	# log has on the governor: a phone that has dropped its clocks processes
	# and draws in lockstep at a lower rate, a phone that is blocked on the
	# GPU or on vsync does not.
	var frames_drawn: int = Engine.get_frames_drawn()
	var frames_processed: int = int(Engine.get_process_frames())
	var drawn_delta: int = frames_drawn - _last_frames_drawn
	var processed_delta: int = frames_processed - _last_frames_processed
	_last_frames_drawn = frames_drawn
	_last_frames_processed = frames_processed
	# proc= is the whole engine process step and cannot tell "the CPU was
	# busy building draw commands" from "the CPU was blocked waiting on the
	# GPU" from "GDScript was slow" - three very different fixes. These two
	# are Godot's own GPU timestamp queries (viewport reports what the
	# hardware measured, one frame behind), so a stall with proc high and
	# gpu high is a real GPU cost (e.g. a shadow atlas repack or a pipeline
	# compiling), while proc high and gpu flat points back at the CPU side
	# (skinning, culling/octree inserts, instancing) - which "pipe=" alone
	# could not distinguish from.
	var gpu_ms: float = 0.0
	var cpu_render_ms: float = 0.0
	if is_inside_tree():
		var vp_rid: RID = get_viewport().get_viewport_rid()
		gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu_render_ms = RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
	# Y hay teléfonos donde esa consulta no contesta. Cuando eso pasa el campo
	# sale a 0.00 y se lee como "la GPU no hizo nada", que es exactamente al
	# reves de lo que hay que concluir: en `dcb37c09` (Mali-G76, driver
	# 1.1.131) son 984 latidos a `gpu=0.00ms` con `cpu_render` normal, y toda
	# lectura cruzada entre dispositivos que se apoye en `gpu` se lleva ese
	# cero como si fuera una medida. A partir del pestillo se escribe `n/d`.
	if not _gpu_timing_unsupported:
		if gpu_ms <= 0.0 and cpu_render_ms > 0.0:
			_gpu_zero_entries += 1
			if _gpu_zero_entries >= GPU_TIMING_UNSUPPORTED_ENTRIES:
				_gpu_timing_unsupported = true
				_file.store_line(
					"[%9.2fs] %-10s este dispositivo no contesta a viewport_get_measured_render_time_gpu (%d entradas seguidas a 0.00 con cpu_render por encima de 0) - a partir de aqui gpu= y sub_gpu= salen como n/d"
					% [seconds, "GPUTIMING", GPU_TIMING_UNSUPPORTED_ENTRIES])
		else:
			_gpu_zero_entries = 0

	# What note churn cost since the previous entry. nodes= and orphans=
	# swinging against each other already showed that notes were streaming in
	# and out of the tree in bulk, but not what it was worth in milliseconds,
	# and neither proc= nor cpu_render= can be made to say: the first is a
	# per-second maximum over the whole process step, the second only counts
	# building the render commands. spawn/despawn is a count of notes, churn
	# the total time in the handlers' spawn block, and churn_max the worst
	# single frame in the interval - which is the one that matches a stutter.
	#
	# Two of these should sit at a known value once a song is running, and are
	# worth checking before reading anything else into a line:
	#   inst= should be 0. Anything else is a note that missed the prewarmed
	#         pool and had to instantiate mid-song.
	#   park= should equal spawn=. Anything less is a note that had to be put
	#         back into the tree instead of being reused where it stood.
	#
	# churn is a RATE, in ms per second of wall clock. It was a total at
	# first, which turned out to be unreadable: every _entry() clears the
	# counters and entries do not arrive on a fixed cadence - a spike or a
	# census lands between two heartbeats and takes most of the interval with
	# it - so churn=100ms and churn=5ms could be the same cost measured over
	# very different windows, and one log had exactly that pair four seconds
	# apart. churn_max is per frame and was always unambiguous.
	var churn: Dictionary = RubiconLevelNoteHandler.take_churn_stats()
	var now_ms: int = Time.get_ticks_msec()
	var window_s: float = float(now_ms - _last_entry_ms) / 1000.0
	_last_entry_ms = now_ms
	var churn_rate: float = 0.0
	if window_s > 0.0:
		churn_rate = (float(churn[&"usec"]) / 1000.0) / window_s

	# Same rate, same reason, for the whole _process of every note and lane
	# rather than just the churn block inside it. Read against script=: if
	# notes= is a small part of it, whatever is making Monochrome's frames
	# expensive is not the notes, and the next thing to time is somewhere
	# else entirely.
	var note_rate: float = 0.0
	var lane_rate: float = 0.0
	# The two sub-blocks of a lane's _process that are not churn - the chart
	# bounds walk and the mixer pump. lanes= minus churn= minus these two is
	# what is genuinely left in the rest of the function.
	var bounds_rate: float = 0.0
	var pump_rate: float = 0.0
	if window_s > 0.0:
		note_rate = (float(churn[&"note_usec"]) / 1000.0) / window_s
		lane_rate = (float(churn[&"lane_usec"]) / 1000.0) / window_s
		bounds_rate = (float(churn[&"bounds_usec"]) / 1000.0) / window_s
		pump_rate = (float(churn[&"pump_usec"]) / 1000.0) / window_s

	# The 2D atlas animations, same rate and the same reason as notes=.
	#
	# notes= answered its question: 100-170ms/s in Monochrome, so 1.7-2.3ms of
	# a 16.7ms frame. Real, but nowhere near enough to explain script_max at
	# 11-36ms on every heartbeat of a song whose GPU sits at 11ms with 5ms to
	# spare. gdanimate is the other large per-frame thing in that scene, and
	# three of the nine spikes name Gold's atlas library.
	#
	# rebuild= vs cached= is the part that matters: the cached path returns
	# almost immediately, the rebuild path frees every canvas item RID the
	# symbol owns and walks the whole symbol tree again. If rebuild_ms is
	# most of anim2d and anim2d is most of script, that is the fix, and it is
	# a fix inside one addon rather than in gameplay code.
	var anim: Dictionary = AnimateSymbol.take_draw_stats()
	var anim_rate: float = 0.0
	var anim_rebuild_rate: float = 0.0
	if window_s > 0.0:
		anim_rate = (float(anim[&"usec"]) / 1000.0) / window_s
		anim_rebuild_rate = (float(anim[&"rebuild_usec"]) / 1000.0) / window_s

	var script_ms: float = float(_script_usec) / 1000.0
	var script_peak_ms: float = float(_script_peak_usec) / 1000.0
	var peak_note_ms: float = float(_peak_note_usec) / 1000.0
	var peak_lane_ms: float = float(_peak_lane_usec) / 1000.0
	var peak_bounds_ms: float = float(_peak_bounds_usec) / 1000.0
	var peak_pump_ms: float = float(_peak_pump_usec) / 1000.0
	var peak_char_ms: float = float(_peak_char_usec) / 1000.0
	# Everything in that frame that none of the named counters claim. This is
	# the number to watch: if it is most of script_max, whatever owns the spike
	# has still never been timed.
	#
	# notes= and chars= are the only two subtracted, and that is not an
	# oversight: lanes=, bounds= and pump= are all measured *inside* the note
	# total, so subtracting them as well would remove the same microseconds two
	# and three times over and report a remainder smaller than the truth. They
	# are printed as a breakdown of notes=, not as siblings of it.
	# self= is subtracted like notes= and chars=, because it is a sibling of
	# them and not a breakdown of anything: it is this node's own _process,
	# measured end to end, and it sits inside the same bracket.
	var peak_self_ms: float = float(_peak_self_usec) / 1000.0
	var peak_seq: String = _peak_seq
	var peak_players: int = _peak_players
	var peak_trees: int = _peak_trees
	var anim_now: Array = _anim_load()
	var seq_now: String = _sequence_state()
	# self= is already out of script_peak_ms - the record is ranked on the
	# remainder - so subtracting it here as well would remove the same
	# microseconds twice and report a rest= smaller than the truth.
	var peak_rest_ms: float = maxf(0.0, script_peak_ms - peak_note_ms - peak_char_ms)
	var peak_chars: int = _peak_chars
	_script_peak_usec = 0
	_peak_self_usec = 0
	_peak_seq = "-"
	_peak_players = 0
	_peak_trees = 0
	_peak_note_usec = 0
	_peak_lane_usec = 0
	_peak_bounds_usec = 0
	_peak_pump_usec = 0
	_peak_char_usec = 0
	_peak_chars = 0

	# The characters' running total, as a rate, same contract as notes=.
	var char_stats: Dictionary = RubiconCharacter.take_process_stats()
	var char_rate: float = 0.0
	if window_s > 0.0:
		char_rate = (float(char_stats[&"usec"]) / 1000.0) / window_s

	# The other half of gpu=, and the half that was missing. A SubViewport
	# whose update mode is DISABLED is not rendering this frame and is left
	# out of both sums, which is what makes sub_px= readable as "pixels the
	# GPU is actually being asked for on top of the main viewport".
	var sub_gpu_ms: float = 0.0
	var sub_live: int = 0
	var sub_pixels: int = 0
	# Which one is the biggest, by name. sub_px= says how many pixels the
	# SubViewports cost in total and never which of them spends them: the
	# shop authors three, 0.48 Mpx between them once the render scale has
	# been applied, and the device measures 1.0-1.4 Mpx across four to six
	# live ones - so half of it comes from viewports inside instanced
	# sub-scenes that no gate in the room scene can see. A total cannot be
	# acted on; a name can.
	## The live SubViewports by pixel count, biggest first.
	##
	## sub_top used to name only the largest, which was enough to find the
	## shop's Home-tab icon viewport but not enough to see what else is on:
	## the shop authors seven and runs four to six of them, and one name out
	## of six leaves the rest anonymous. Three is where the line stops
	## growing faster than it informs.
	var live_viewports: Array = []
	for viewport: SubViewport in _sub_viewports:
		if not is_instance_valid(viewport):
			continue
		if viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			continue
		sub_live += 1
		var pixels: int = viewport.size.x * viewport.size.y
		sub_pixels += pixels
		live_viewports.append([pixels, "%s(%dx%d)" % [
			_scene_relative_path(viewport), viewport.size.x, viewport.size.y,
		]])
		sub_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())

	live_viewports.sort_custom(func(a, b): return a[0] > b[0])
	var top_viewports: PackedStringArray = []
	for i in mini(3, live_viewports.size()):
		top_viewports.append(live_viewports[i][1])
	var biggest_name: String = "-" if top_viewports.is_empty() else ",".join(top_viewports)

	_file.store_line("[%9.2fs] %-10s %s | ram=%s peak=%s vram=%s buf=%s video=%s scale=%s draw=%d prims=%d objs=%d rend=[%s] nodes=%d orphans=%s res=%d pipe=%d(+%d %s) drawn=%d/%d in=%d(touch=%d key=%d act=%d oth=%d idle=%.1fs) mix=%.1fms proc=%.2fms phys=%.2fms nav=%.2fms audio=%.1fms gpu=%sms cpu_render=%.2fms sub=%d/%d sub_gpu=%sms sub_px=%.2fM sub_top=%s seq=%s anim=%d/%d procn=%d vis3d=%d/%d parts=%d/%d tweens=%d msgq=%s focus=%s vp=[%s] eng=[%s] alat=%.1f/%.1fms env=%s lm=%s luz=%s mira=%s bake=[%s] cam=%s psteps=%d bench=%dus physn=%d bones=%d mat3d=%d/%d script=%.2fms script_max=%.2fms(notes=%.2f lanes=%.2f bounds=%.2f pump=%.2f chars=%.2f/%d self=%.2f rest=%.2f at=%s anim=%d/%d) spawn=%d despawn=%d park=%d inst=%d churn=%.2fms/s churn_max=%.2fms notes=%.2fms/s(lanes=%.2f bounds=%.2f pump=%.2f) chars=%.2fms/s anim2d=%.2fms/s(rebuild=%.2fms/s x%d peak=%.2fms cached=%d sym=%d atlas=%d/%d worst=%s@%.2fms) p3d_objs=%d p3d_pairs=%d scene=%s" % [
		seconds,
		kind,
		detail,
		_mb(OS.get_static_memory_usage()),
		_mb(_peak_memory),
		_mb(int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))),
		_mb(int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))),
		_mb(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
		_render_scale(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		_render_split(),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		# Node::orphan_node_count is DEBUG_ENABLED-only, so this is a flat 0 in
		# a release build - and 0 orphans is exactly what a healthy note pool
		# is NOT (it should read ~2400 after prewarm_pool). Reporting n/a
		# keeps anyone from reading the absence as a result.
		(str(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
			if OS.is_debug_build() else "n/a"),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		pipelines,
		pipe_delta,
		pipe_sources,
		drawn_delta,
		processed_delta,
		_in_touch + _in_key + _in_action + _in_other,
		_in_touch,
		_in_key,
		_in_action,
		_in_other,
		float(Time.get_ticks_msec() - _last_input_ms) / 1000.0,
		# How long since the audio thread last mixed a buffer. It runs off
		# the main thread, so on a frame the main thread has blocked this
		# keeps ticking normally - and when it does NOT, the block is
		# somewhere both threads contend on (a loader mutex, the allocator)
		# rather than in rendering or script. The load stall is exactly the
		# case where that distinction decides where to look next: eleven
		# seconds with nothing uploading and nothing allocating is either a
		# thread waiting on I/O or a thread waiting on a lock, and audio is
		# the only clock in this log that is not the main thread's.
		AudioServer.get_time_since_last_mix() * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.AUDIO_OUTPUT_LATENCY) * 1000.0,
		_gpu_field(gpu_ms),
		cpu_render_ms,
		sub_live,
		_sub_viewports.size(),
		_gpu_field(sub_gpu_ms),
		float(sub_pixels) / 1048576.0,
		biggest_name,
		seq_now, anim_now[0], anim_now[1], _process_nodes,
		_visual3d_load(), _visual3d_watch.size(),
		_particles_live(), _particles_watch.size(),
		get_tree().get_processed_tweens().size() if is_inside_tree() else 0,
		_mb(int(Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX))),
		_focus_state(), _viewport_config(), _engine_config(),
		AudioServer.get_output_latency() * 1000.0,
		AudioServer.get_time_to_next_mix() * 1000.0,
		_environment_state(),
		_lightmap_state(),
		_light_reach(),
		_aim_summary(),
		_bake_modes(),
		_camera_state(), _physics_steps, _bench_usec,
		_physics_nodes, _skeleton_bones, _material_count, _surface_count,
		script_ms,
		script_peak_ms,
		peak_note_ms, peak_lane_ms, peak_bounds_ms, peak_pump_ms,
		peak_char_ms, peak_chars, peak_self_ms, peak_rest_ms, peak_seq, peak_players, peak_trees,
		int(churn[&"spawned"]),
		int(churn[&"despawned"]),
		int(churn[&"unparked"]),
		int(churn[&"instantiated"]),
		churn_rate,
		float(churn[&"peak_usec"]) / 1000.0,
		note_rate,
		lane_rate,
		bounds_rate,
		pump_rate,
		char_rate,
		anim_rate,
		anim_rebuild_rate,
		int(anim[&"rebuilds"]),
		float(anim[&"peak_usec"]) / 1000.0,
		int(anim[&"cached"]),
		int(anim[&"symbols"]),
		# atlas=A/S: A distinct atlases drew, and S is the most symbols sharing
		# any one of them. use_backbuffer_cache lives on the atlas, so S above 1
		# means a symbol advancing a frame drags the others into a full rebuild.
		int(anim.get(&"atlases", 0)),
		int(anim.get(&"shared_max", 0)),
		anim[&"worst"] if not String(anim[&"worst"]).is_empty() else "-",
		float(anim[&"worst_usec"]) / 1000.0,
		# Read across the project's 33 logs after this landed: median
		# p3d_objs=0 in both env_collector_shop.tscn and sng_chimera.tscn, and
		# pairs comparable (shop median 10/max 52, Chimera median 0/max 31).
		# The "10-25x, suspected enable_object_picking" this comment used to
		# say was never actually true - the shop's own aim raycast is a
		# single RayCast3D in mouse_controller.gd, not per-Area3D picking, and
		# there is no property named enable_object_picking on Viewport (the
		# real one is physics_object_picking, unset anywhere in this project).
		# Kept for the same reason as before: cheap to log, no separate
		# investigation needed - just no longer a live suspicion.
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		_current_scene_name(),
	])

	# Quien se come rest=, por subarbol, del MISMO fotograma que gano el record.
	#
	# En linea aparte y no dentro del formato de arriba a proposito: esa cadena
	# ya lleva noventa argumentos posicionales y meter uno mas en medio es la
	# clase de cambio que desplaza los demas sin que nada avise.
	#
	# Se ordena por coste y se cortan las regiones por debajo de 0.1ms, que solo
	# alargarian la linea. Un `-` es un subarbol que NO estampo: proceso apagado,
	# no coste cero.
	# Solo en los censos. `_entry()` escribe una linea por CADA entrada -errores,
	# avisos, cambios de escena- y colgar esto de todas ellas duplicaria el log
	# para repetir el mismo reparto.
	if kind.begins_with("CENSUS") and not _probe_names.is_empty():
		_file.store_line("[%9.2fs] %-10s script_max=%.2fms rest=%.2fms | %s" % [
			seconds, "REGIONS",
			float(_script_peak_usec) / 1000.0,
			float(maxi(0, _script_peak_usec - _peak_note_usec - _peak_lane_usec
				- _peak_bounds_usec - _peak_pump_usec - _peak_char_usec)) / 1000.0,
			_regions_text()])
	# Counts, not rates, and cleared here so each line covers the interval
	# since the previous one - same contract as churn= and anim2d=. idle= is
	# deliberately not cleared: it is a timestamp, not a tally.
	_in_touch = 0
	_in_key = 0
	_in_action = 0
	_in_other = 0

	# Flushed every entry on purpose: the whole point is to survive a crash or
	# a force-close, and a buffered tail is exactly the part worth reading.
	_file.flush()

## Guarded because the last entry is written from NOTIFICATION_PREDELETE, by
## which point the node is already out of the tree - reading current_scene
## there threw on every shutdown and cost the log its final line's context.
##
## Asked with is_inside_tree() rather than by null-checking get_tree(), which
## prints an engine error of its own before returning null and so traded one
## noisy shutdown line for another.
func _current_scene_name() -> String:
	if not is_inside_tree():
		return "-"

	var tree: SceneTree = get_tree()
	if tree == null:
		return "-"

	var scene: Node = tree.current_scene
	return scene.scene_file_path.get_file() if scene and not scene.scene_file_path.is_empty() else "?"

func _mb(bytes: int) -> String:
	# Measured against the real 4.7.1 export templates rather than assumed:
	# Godot's memory accounting is compiled out of a release template.
	# MEMORY_STATIC, MEMORY_STATIC_MAX, OS.get_static_memory_usage() and
	# OS.get_static_memory_peak_usage() all return exactly 0 there, while
	# OBJECT_COUNT, OBJECT_RESOURCE_COUNT and OBJECT_NODE_COUNT survive.
	#
	# Printing that 0 as "0MB" would be worse than printing nothing: a log
	# reading ram=0MB peak=0MB reads as "this build uses no memory", and this
	# project has already lost time to a counter that was quietly lying (gpu=
	# covering only the main viewport, for months). n/a says the number does
	# not exist in this build.
	if bytes <= 0 and not OS.is_debug_build():
		return "n/a"
	return "%.0fMB" % (bytes / 1048576.0)

## One value out of /proc, in kB, or -1.
##
## FileAccess.get_as_text() cannot read /proc: those files report a length of
## zero and get_as_text() trusts it, so it hands back an empty string from a
## file that has plenty to say. get_line() reads until it actually runs out,
## which works - measured here against /proc/self/status before being relied
## on, not assumed from the docs.
func _proc_kb(path: String, key: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var found: int = -1
	while true:
		var line: String = file.get_line()
		if line.is_empty():
			break
		if not line.begins_with(key):
			continue
		for token in line.split(" ", false):
			if token.is_valid_int():
				found = int(token)
				break
		break
	file.close()
	return found

## Process and system memory, which - unlike everything _mb() reports -
## survives a release template.
##
## Godot's own accounting is compiled out of release, so every device log so
## far reads ram=n/a peak=n/a, and that is the blind spot that matters right
## now: the shop dies on release only, and "the kernel killed us for memory"
## cannot be told apart from "we faulted" without a number.
##
## Not OS.get_memory_info(). That is the obvious answer and it does not work
## here - this file already carries a note that its "physical" field reports
## zero on Android, and the device log proves it, printing "(not reported by
## OS)" in its own header. Guessing that "available" survives where
## "physical" does not would have shipped another n/a.
##
## /proc does work, and says more. VmRSS is what this process is actually
## holding, VmHWM is the highest it ever held - which outlives the moment, so
## a log line written after a spike still reports the spike - and MemAvailable
## is what the kernel still has to give before it starts killing things to get
## it. An out-of-memory kill has a signature in those three that nothing else
## has.
##
## Returns "-" off Linux, rather than inventing a zero.
func _sys_mem() -> String:
	var rss: int = _proc_kb("/proc/self/status", "VmRSS:")
	if rss < 0:
		return "-"
	var peak: int = _proc_kb("/proc/self/status", "VmHWM:")
	var avail: int = _proc_kb("/proc/meminfo", "MemAvailable:")
	return "rss=%dMB peak=%dMB avail=%s" % [
		rss / 1024, peak / 1024,
		"%dMB" % (avail / 1024) if avail >= 0 else "?",
	]

## The package this build actually runs under.
##
## Godot exposes no API for it, but user:// resolves to
## /data/user/0/<package>/files on Android, so it can be read back from
## there. Hardcoding it meant a build exported under any other package name
## pointed its log at a directory scoped storage forbids it from writing to,
## silently falling through to user://logs - internal storage, unreachable
## without root, i.e. no log at all. Falls back to the constant off-device
## or if the path ever stops matching that shape.
func _android_package() -> String:
	var parts: PackedStringArray = OS.get_user_data_dir().split("/", false)
	var idx: int = parts.find("files")
	if idx > 0:
		return parts[idx - 1]
	return ANDROID_PACKAGE

## Walks the preference list and takes the first directory that can actually
## be created and written to. make_dir_recursive_absolute() returning OK is
## not proof on its own - a path can appear to succeed and still reject the
## file - so each candidate is confirmed by opening a real file in it.
func _pick_log_dir() -> String:
	var candidates: Array[String] = []
	if OS.get_name() == "Android":
		candidates.append(ANDROID_APP_LOG_DIR_FMT % _android_package())
	candidates.append(FALLBACK_LOG_DIR)

	for candidate in candidates:
		if _is_writable(candidate):
			return candidate

	push_warning("diagnostics: no writable log directory found")
	return FALLBACK_LOG_DIR

func _is_writable(dir_path: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dir_path) != OK and not DirAccess.dir_exists_absolute(dir_path):
		return false

	var probe: String = dir_path.path_join(".write_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true

func _open_log() -> bool:
	_log_dir = _pick_log_dir()
	_rotate()

	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	log_path = "%s/lullaby_%s.log" % [_log_dir, stamp]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_warning("diagnostics: cannot open %s" % log_path)
		return false

	# Started here rather than in _ready() so it is already sampling during
	# boot, which is the only way its trace and this log share a baseline.
	_sampler = MemorySampler.new()
	if not _sampler.start("%s/lullaby_%s.mem" % [_log_dir, stamp]):
		_sampler = null
	return true

## Keeps the newest MAX_LOG_FILES. Without this a phone accumulates one file
## per launch forever, and the player is the one paying for the space.
func _rotate() -> void:
	var dir := DirAccess.open(_log_dir)
	if dir == null:
		return

	var files: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".log"):
			files.append(f)
	files.sort()

	var excess: int = files.size() - (MAX_LOG_FILES - 1)
	for i in maxi(excess, 0):
		DirAccess.remove_absolute(_log_dir.path_join(files[i]))

func _write_header() -> void:
	if _file == null:
		return
	_file.store_line("Lullaby diagnostics log")
	_file.store_line("date      : %s" % Time.get_datetime_string_from_system())
	# application/config/version is unset in this project, so fall back to the
	# Android version code, which the build pipeline does bump.
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if version.is_empty():
		version = "code %s" % ProjectSettings.get_setting("application/config/version_code", "?")
	_file.store_line("version   : %s" % version)
	_file.store_line("godot     : %s" % Engine.get_version_info()["string"])
	# Which engine template this APK carries, which is NOT the same question
	# as which key signed it. Every build before this one exported
	# --export-debug and was then re-signed with the release keystore, so the
	# APK on the phone was a debug engine wearing a release signature - and a
	# debug template runs GDScript with its per-instruction bookkeeping for
	# line numbers and stack traces. Two logs are only comparable if each
	# says which one it came from, and nothing in the header did.
	_file.store_line("template  : %s" % ("debug" if OS.is_debug_build() else "release"))
	_file.store_line("os        : %s %s" % [OS.get_name(), OS.get_version()])
	_file.store_line("model     : %s" % OS.get_model_name())
	# get_processor_name() returns "" on Android; the thread count still works
	# and is the part that matters for judging what can be threaded.
	var cpu: String = OS.get_processor_name()
	_file.store_line("cpu       : %s(%d threads)" % ["" if cpu.is_empty() else cpu + " ", OS.get_processor_count()])
	_file.store_line("gpu       : %s" % RenderingServer.get_video_adapter_name())
	_file.store_line("renderer  : %s" % RenderingServer.get_current_rendering_method())
	_file.store_line("driver    : %s" % RenderingServer.get_video_adapter_api_version())
	# Pipelines already built by the time the first scene is up. A baseline
	# matters because the per-entry pipe=N(+D) delta is only meaningful
	# against it - and if this is already in the thousands, the cutscene
	# stalls are a small tail of a much larger compile budget.
	_file.store_line("pipelines : %d compiled at boot" % _pipeline_compilations())
	# The driver's pipeline cache identity, which decides whether the worst
	# stall in the project is paid once per install or once per launch.
	# 122_fall@6.8s costs frame=1911.7ms for `spec+8` with RAM and VRAM flat,
	# and Godot's pipeline cache (on by default, not overridden here) is meant
	# to write those to disk so the next launch reuses them. The UUID is the
	# *driver's*: it changes on a driver update and invalidates the cache. So
	# two logs with different UUIDs explain a stall that came back on its own,
	# and two with the same UUID mean the cache should have held - if the stall
	# is still there, it is not being written or not being read.
	# Null under GL Compatibility, which has no RenderingDevice.
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	_file.store_line("pipe_cache: %s" % (
		device.get_device_pipeline_cache_uuid() if device != null else "(sin RenderingDevice)"))
	# get_memory_info()["physical"] reports 0 on Android, which is why this line
	# read "(not reported by OS)" in every device log so far. /proc answers
	# where the engine does not - see _sys_mem(). The raw dictionary goes out
	# alongside it so the next log settles whether any of its fields are usable
	# on this device rather than leaving that a guess.
	var total_kb: int = _proc_kb("/proc/meminfo", "MemTotal:")
	_file.store_line("memory    : %s" % ("%d MB total, %s" % [total_kb / 1024, _sys_mem()]
		if total_kb > 0 else "(not reported by OS)"))
	_file.store_line("os_memory : %s" % OS.get_memory_info())
	_file.store_line("max_fps   : %d  vsync=%d" % [Engine.max_fps, DisplayServer.window_get_vsync_mode()])
	# Boot-time snapshot only - first_boot_settings and the player can both
	# change these afterwards, which is why _on_settings_applied() logs a
	# SETTINGS entry on every real change rather than trusting this line.
	_file.store_line("graphics  : %s (at boot)" % _graphics_summary())
	# Stated either way, and this line is why the split can afford to ship off.
	#
	# It shipped on because a log with no GPUSPLIT lines is indistinguishable
	# from an instrument nobody remembered to switch on, and two device passes
	# were lost to that. But paying for it in a visible flash every 20 seconds
	# in both 3D scenes - which is what the player reported off 27868ddd - is
	# the wrong side of that trade. Saying so in the header costs nothing and
	# removes the ambiguity the default was covering for.
	_file.store_line("gpu_split : %s%s" % [
		"on" if Settings.diagnostics_gpu_split else "off",
		"" if Settings.diagnostics_gpu_split
			else "  (sin GPUSPLIT/SCRIPTSPLIT en este log; la fila esta en la consola)",
	])
	_file.store_line("window    : %s" % DisplayServer.window_get_size())
	_file.store_line("path      : %s" % ProjectSettings.globalize_path(log_path))
	_file.store_line("dir_used  : %s" % _log_dir)
	# Named here so the trace is not a file nobody knows to collect. It is the
	# half of a crash report this log cannot write, because it is still being
	# written while this thread is blocked.
	_file.store_line("mem_trace : %s" % (_sampler.get_path() if _sampler != null
		else "(no disponible: /proc no legible)"))
	_file.store_line("")
	_file.flush()

func _notification(what: int) -> void:
	# Android suspending the app is not a frame, and since frame_ms went to the
	# wall clock it looks exactly like one.
	#
	# Three logs from three devices on 10154-8d1ee1ac carry "frames" of
	# 71738.6ms, 17070.0ms, 16905.2ms, 14082.6ms and 4405.6ms - every one of
	# them in the shop, at rest, with pipe+0, vram_delta=+0.0MB, RAM flat and
	# **no log line at all** for the whole window. A process that is running
	# writes a heartbeat every five seconds; one that writes nothing for 74
	# seconds is not running. That is the OS, not the game, and reporting it as
	# the worst frame in the session buries whatever the real worst frame was.
	#
	# PAUSED/RESUMED rather than focus: focus also fires for a notification
	# shade pull, where the app keeps rendering, and that frame IS real.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_paused_at_msec = Time.get_ticks_msec()
	elif what == NOTIFICATION_APPLICATION_RESUMED and _paused_at_msec > 0:
		_suspended_ms = Time.get_ticks_msec() - _paused_at_msec
		_paused_at_msec = 0

	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		# Stopped before the log closes, not after: stop() joins the sampler
		# thread, and a thread still writing while the engine tears down its
		# FileAccess subsystem is a crash in the crash reporter.
		if _sampler != null:
			_sampler.stop()
			_sampler = null
		if _file != null:
			_entry("SHUTDOWN", "session ended")
			_file.close()
			_file = null
