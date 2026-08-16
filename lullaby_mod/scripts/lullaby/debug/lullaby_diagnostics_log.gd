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

## A census walks the whole scene tree, so it is far too expensive to do per
## frame - every 30s is enough to see a trend without becoming part of the
## problem it measures.
const CENSUS_SECONDS := 30.0
const CENSUS_ON_PROC_MS := 300.0

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

func _close_script_bracket(now_usec: int) -> void:
	_script_usec = now_usec - _script_begin_usec
	if _script_usec <= _script_peak_usec:
		return

	# The frame that beats the record is the only one whose breakdown is
	# worth keeping. script_max= has been the biggest unattributed number in
	# this log for days - 19.52ms against a 4.76ms median - and the
	# sub-counters beside it are rates, which cannot hold a spike: an average
	# of 1.86ms/frame looks the same whether the cost is flat or whether one
	# frame in sixty costs everything. Snapshotting here turns that one
	# number into a list of names plus a remainder.
	_script_peak_usec = _script_usec
	_peak_note_usec = RubiconLevelNoteHandler.frame_note_usec
	_peak_lane_usec = RubiconLevelNoteHandler.frame_lane_usec
	_peak_bounds_usec = RubiconLevelNoteHandler.frame_bounds_usec
	_peak_pump_usec = RubiconLevelNoteHandler.frame_pump_usec
	_peak_char_usec = RubiconCharacter.frame_process_usec
	_peak_chars = RubiconCharacter.frame_process_count

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

## Wall-clock ceiling on either graph walk, in microseconds.
##
## Both run on the main thread, on the frame a load starts, and both read a
## file header per path - which for an imported resource means parsing its
## .import as well. A cap on the number of paths does not bound that, because
## the per-path cost is a device-side unknown; a cap on time does. Truncation
## is reported, so a short answer never reads as a complete one.
const PROBE_BUDGET_USEC := 120_000

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
	_probe_usec += Time.get_ticks_usec() - started

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = PROCESS_FIRST

	if not Settings.lullaby_diagnostics_log:
		set_process(false)
		return

	if not _open_log():
		set_process(false)
		return

	# Opt-in and cheap (a couple of GPU timestamp queries the driver already
	# supports), but off by default in Godot - without it gpu=/cpu_render=
	# below would just silently read 0 forever, which looks exactly like "GPU
	# idle" and would have been a lie. Only exposed on RenderingServer by
	# viewport RID, not as a Viewport instance method - confirmed in an
	# isolated project after the instance-method call errored on Window.
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

	if SceneChanger.has_signal("scene_change_started"):
		SceneChanger.scene_change_started.connect(_on_scene_change_started)
	if SceneChanger.has_signal("scene_change_finished"):
		SceneChanger.scene_change_finished.connect(_on_scene_change_finished)

	# The header records the graphics settings once, at boot - which is before
	# first_boot_settings runs and before the player can touch anything. A log
	# whose header says "High" while the session actually ran on something
	# else is worse than no record at all: it was read as ground truth and
	# sent a whole investigation down the wrong path. Log them again whenever
	# they change, so every entry can be attributed to the settings in force.
	if Settings.has_signal("applied"):
		Settings.applied.connect(_on_settings_applied)

func _process(delta: float) -> void:
	# Opens the bracket _ScriptTail closes. First statement on purpose: this
	# node has the lowest process_priority in the tree, so everything else
	# that runs this frame runs after this line.
	_script_begin_usec = Time.get_ticks_usec()

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
	var now_usec: int = Time.get_ticks_usec()
	var frame_ms: float = float(now_usec - _last_frame_usec) / 1000.0 if _last_frame_usec > 0 else delta * 1000.0
	_last_frame_usec = now_usec

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

	_time_since_heartbeat += delta
	_time_since_spike += delta

	# Needs a full window before the median means anything, otherwise the
	# first frames after a load all read as spikes against a near-empty
	# buffer.
	if _frames_seen > WINDOW_SIZE and _time_since_spike >= SPIKE_COOLDOWN_SECONDS:
		if frame_ms >= SPIKE_MIN_MS and frame_ms >= median * SPIKE_FACTOR:
			_time_since_spike = 0.0
			var vram_now: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
			var vram_delta: float = float(vram_now - _last_vram) / 1048576.0
			var since_anim: int = Time.get_ticks_msec() - _last_anim_ms
			var blame: String = ""
			# Only worth quoting if it started essentially on this frame -
			# anything older is coincidence, not cause.
			if not _last_anim.is_empty() and since_anim <= 250:
				blame = "  after %s (%dms ago)" % [_last_anim, since_anim]
			_entry("SPIKE", "frame=%.1fms median=%.1fms (%.1fx) vram_delta=%+.1fMB%s" % [
				frame_ms, median, frame_ms / maxf(median, 0.001), vram_delta, blame,
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

	_time_since_summary += delta
	if _time_since_summary >= SUMMARY_MINUTES * 60.0:
		_time_since_summary = 0.0
		_write_summary()

	# Every frame on purpose: a 30 second census cannot see a blackout that
	# lasts ten. The list is short, so this is a handful of reads.
	_poll_blackouts()

	_time_since_census += delta
	if _time_since_census >= CENSUS_SECONDS:
		_time_since_census = 0.0
		census("periodic")

	if _time_since_heartbeat >= HEARTBEAT_SECONDS:
		_time_since_heartbeat = 0.0
		_entry("HEARTBEAT", "fps_now=%d fps_low=%d median=%.1fms %s" % [
			fps, _lowest_fps, median, _take_frame_shape(),
		])
		_lowest_fps = -1

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
	var scene: Node = get_tree().current_scene if get_tree() else null
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
	## Visible, opaque, full-frame CanvasItems, deepest last - which is
	## roughly draw order, so the last one named is the one on top.
	var covers: Array[String] = []
	## Screen-covering drawing items whose own pixel alpha the census cannot
	## read - see UNKNOWN_COVERAGE.
	var covers_maybe: Array[String] = []
	var lights_visible: int = 0
	var lights_shadow: int = 0
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
		if node is Light3D and node.is_visible_in_tree() and not node.editor_only:
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

	_entry("CENSUS", "%s | anim_players=%d playing=%d anim_tracks=%d trees=%d(active=%d manual=%d) notes=%d(visible=%d) parked=%d audio=%d(playing=%d) phys2d=%d/%d lights=%d(shadow=%d) fx=%d(effect=%d full=%d uniq=%d) opaque=%d maybe=%d over=%.1fx(n=%d top=%s@%.1fx) | %s | top_anims=[%s] | shadows=[%s] | opaque=[%s] | maybe=[%s] | %s | delta=[%s]" % [
		reason, players.size(), playing, total_tracks, trees_total, trees_active, trees_manual,
		notes_total, notes_visible, notes_parked,
		audio_total, audio_playing,
		# Monochrome and Safety Lullaby are 2D scenes and every touch overlay
		# in the project is 2D, and the log only ever carried the 3D pair -
		# so the shop was measured and the songs were not.
		int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		lights_visible, lights_shadow,
		fx_live, fx_effect, fx_fullscreen, fx_materials.size(),
		covers.size(), covers_maybe.size(),
		overdraw_px / maxf(1.0, _screen_px()), overdraw_items,
		overdraw_top if not overdraw_top.is_empty() else "-",
		overdraw_top_px / maxf(1.0, _screen_px()),
		_graphics_summary(), ", ".join(top), ", ".join(shadow_names),
		", ".join(covers.slice(0, 6)),
		", ".join(covers_maybe.slice(0, 6)),
		" ".join(classes), " ".join(class_delta),
	])

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
const BLACKOUT_MIN_COVERAGE := 0.8
const BLACKOUT_MAX_LUMA := 0.15

var _blackout_watch: Array[CanvasItem] = []
var _blackout_on: Dictionary = {}

## Collected after the scene has settled rather than during load: _ready() and
## the opening animations both move things, and a list taken too early misses
## whatever they build.
func _collect_blackout_watch() -> void:
	_blackout_watch.clear()
	_blackout_on.clear()
	var scene: Node = get_tree().current_scene if get_tree() else null
	if scene == null:
		return

	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var rect := node as ColorRect
		if rect == null or not _alpha_is_knowable(rect):
			continue
		# Dark enough to read as a blackout, judged on the authored colour
		# because that is what it paints when something switches it on.
		if maxf(rect.color.r, maxf(rect.color.g, rect.color.b)) > BLACKOUT_MAX_LUMA:
			continue
		if rect.size.x * rect.size.y <= 0.0:
			continue
		_blackout_watch.append(rect)

	if not _blackout_watch.is_empty():
		_entry("BLACKWATCH", "vigilando %d rects oscuros en %s" % [
			_blackout_watch.size(), _current_scene_name(),
		])

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
		var covering: bool = item.is_visible_in_tree() \
			and covered >= BLACKOUT_MIN_COVERAGE \
			and _opaque_coverage(item) >= BLACKOUT_MIN_COVERAGE
		var was: bool = _blackout_on.has(item)
		if covering and not was:
			_blackout_on[item] = now
			_entry("BLACKOUT", "%s tapa la pantalla (cubre=%.2f alpha=%.2f)" % [
				_scene_relative_path(item), covered, item.modulate.a,
			])
		elif was and not covering:
			_entry("BLACKOUT", "%s deja de taparla tras %.1fs" % [
				_scene_relative_path(item), (now - int(_blackout_on[item])) / 1000.0,
			])
			_blackout_on.erase(item)

## Geometry only, deliberately: alpha is not folded in, because a sprite at
## 10% alpha still costs a full blend on a tile GPU and hiding it behind a
## weighting would under-report the exact thing being hunted.
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

	var scene: Node = get_tree().current_scene if get_tree() else null
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

	var scene: Node = get_tree().current_scene if get_tree() else null
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
	var scene: Node = get_tree().current_scene if get_tree() else null
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
	# aniso/lod/light_fade are logged because they are only ever set by a
	# preset - on Custom they sit at their defaults and do nothing, which is
	# invisible otherwise and made a whole run unattributable once.
	return "preset=%s scale=%.2f aspect=%s msaa=%s shadows=%s atlas=%d filter=%d ssao=%s ssil=%s post=%d sha_fx=%s aniso=%s lod=%.1f light_fade=%.1f phys_hz=%d target_fps=%d" % [
		preset.name if preset != null else "Custom",
		Settings.graphics_render_scale,
		"Wide" if Settings.display_screen_aspect == Window.ContentScaleAspect.CONTENT_SCALE_ASPECT_EXPAND else "Normal",
		msaa_names[msaa],
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
	]

## Settings.applied fires on every option row the player touches, so this
## rate-limits to actual changes - otherwise scrolling the console would
## bury the log in identical lines.
func _on_settings_applied() -> void:
	var summary: String = _graphics_summary()
	if summary == _last_graphics_summary:
		return
	_last_graphics_summary = summary
	_entry("SETTINGS", summary)

## Public so anything can drop a marker into the log - e.g. a mechanic
## starting, or a cutscene the player says "it breaks here".
func mark(what: String) -> void:
	_entry("MARK", what)

func _on_error_logged(kind: String, message: String, err: int) -> void:
	_entry(kind.to_upper(), "%s (error %d)" % [message.replace("\n", " | "), err])

func _on_scene_change_started(path: String) -> void:
	_scene_change_started_ms = Time.get_ticks_msec()
	_dep_ms = {}
	_dep_count = {}
	_dep_clock = _scene_change_started_ms
	_scene_change_memory = OS.get_static_memory_usage()
	_loading_path = path
	_load_checkpoints_done = 0
	var outgoing: Node = get_tree().current_scene if get_tree() else null
	_outgoing_scene_path = outgoing.scene_file_path if outgoing != null else ""
	_residue_reported = _outgoing_scene_path.is_empty()
	_last_loading_entry_ms = Time.get_ticks_msec()
	_last_census_counts.clear()
	_stall_fraction = -1.0
	_stall_samples = 0
	_stall_cached_at_start = 0
	_probe_usec = 0
	_residue_walk_usec = 0
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

	_entry("SCENE_IN", "%s took=%dms probe=%.1fms memory_delta=%+.1fMB sys=%s" % [
		path, took, _probe_usec / 1000.0, delta_mb, _sys_mem(),
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

## Where a load's wall time went, by subsystem, worst first.
func _dep_breakdown() -> String:
	if _dep_ms.is_empty():
		return "-"
	var rows: Array = []
	for owner in _dep_ms:
		rows.append([float(_dep_ms[owner]), owner, int(_dep_count.get(owner, 0))])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var parts: PackedStringArray = PackedStringArray()
	for i in mini(6, rows.size()):
		parts.append("%s=%.1fs/%d" % [rows[i][1], rows[i][0] / 1000.0, rows[i][2]])
	return " ".join(parts)

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
	var peak_rest_ms: float = maxf(0.0, script_peak_ms - peak_note_ms - peak_char_ms)
	var peak_chars: int = _peak_chars
	_script_peak_usec = 0
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

	_file.store_line("[%9.2fs] %-10s %s | ram=%s peak=%s vram=%s buf=%s video=%s scale=%.2f draw=%d prims=%d objs=%d nodes=%d orphans=%s res=%d pipe=%d(+%d %s) drawn=%d/%d in=%d(touch=%d key=%d act=%d oth=%d idle=%.1fs) mix=%.1fms proc=%.2fms phys=%.2fms nav=%.2fms audio=%.1fms gpu=%.2fms cpu_render=%.2fms sub=%d/%d sub_gpu=%.2fms sub_px=%.2fM sub_top=%s script=%.2fms script_max=%.2fms(notes=%.2f lanes=%.2f bounds=%.2f pump=%.2f chars=%.2f/%d rest=%.2f) spawn=%d despawn=%d park=%d inst=%d churn=%.2fms/s churn_max=%.2fms notes=%.2fms/s(lanes=%.2f bounds=%.2f pump=%.2f) chars=%.2fms/s anim2d=%.2fms/s(rebuild=%.2fms/s x%d peak=%.2fms cached=%d sym=%d worst=%s@%.2fms) p3d_objs=%d p3d_pairs=%d scene=%s" % [
		seconds,
		kind,
		detail,
		_mb(OS.get_static_memory_usage()),
		_mb(_peak_memory),
		_mb(int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))),
		_mb(int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))),
		_mb(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
		Settings.graphics_render_scale,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
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
		gpu_ms,
		cpu_render_ms,
		sub_live,
		_sub_viewports.size(),
		sub_gpu_ms,
		float(sub_pixels) / 1048576.0,
		biggest_name,
		script_ms,
		script_peak_ms,
		peak_note_ms, peak_lane_ms, peak_bounds_ms, peak_pump_ms,
		peak_char_ms, peak_chars, peak_rest_ms,
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
		anim[&"worst"] if not String(anim[&"worst"]).is_empty() else "-",
		float(anim[&"worst_usec"]) / 1000.0,
		# The shop's physics cost runs 10-25x Chimera's on nothing but
		# enable_object_picking's per-frame Area3D raycasts - these two were
		# flagged as worth measuring and never were, so they ride along here
		# rather than costing a separate investigation later.
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		_current_scene_name(),
	])
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
