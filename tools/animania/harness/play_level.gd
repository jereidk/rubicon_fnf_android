# Runs songs/phone-call/phone_call.tscn for real and reports what happened.
#
# The level clock reads its time straight off RubiconLevelClock/AnimationPlayer's
# current_animation_position, so that player IS the song's timeline - which means this can
# seek anywhere in the song instead of waiting for it, and that the animation's length is
# what decides when the song ends.
#
# Both sides are forced to autoplay here: the player side normally waits for input, and a
# headless run has none, so without this it would report 195 misses and say nothing about
# whether the chart is wired up.
#
#   godot --headless --path . --script tools/animania/harness/play_level.gd -- [start] [seconds]
extends SceneTree

const LEVEL := "res://songs/phone-call/phone_call.tscn"

## 512 samples at 44100 Hz, which is what every non-zero desync reading here turns out to
## be a multiple of.
const MIX_BUFFER_MS := 512.0 / 44100.0 * 1000.0

var _level: Node
var _clock: Node
var _song: Node
var _controllers: Dictionary = {}
var _start: float = 11.5
var _duration: float = 30.0
var _elapsed: float = 0.0
var _seeked: bool = false
var _worst_desync: Dictionary = {}
var _worst_at: Dictionary = {}
var _over_threshold: int = 0
var _worst_frame: float = 0.0
var _last_trace: float = 0.0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_start = float(args[0])
	if args.size() > 1:
		_duration = float(args[1])

	_level = load(LEVEL).instantiate()
	root.add_child(_level)

	_clock = _level.get_node("RubiconLevelClock")
	_song = _level.get_node("RubiconLevelSongModule")
	for side: String in ["Opponent", "Player"]:
		var controller: Node = _level.get_node("UILayer/UI/%s" % side)
		controller.autoplay = true
		_controllers[side] = controller

	print("OUT timeline %.3fs, %d lanes por lado" % [
		_clock.animation_player.get_animation(&"scene").length,
		_controllers["Player"].get_child_count()])
	for side: String in _controllers:
		print("OUT %-8s chart notes=%d" % [side, _count_notes(_controllers[side].chart)])

	process_frame.connect(_tick)


func _count_notes(chart: Resource) -> int:
	var total: int = 0
	for section: Resource in chart.sections:
		for row: Resource in section.rows:
			total += row.starts.size()
	return total


func _tick() -> void:
	if not _seeked:
		_seeked = true
		_clock.animation_player.seek(_start, true)
		for player: AudioStreamPlayer in _song.audio_players:
			if player.playing:
				player.seek(_start)
		return

	_elapsed += root.get_process_delta_time()

	# The three tracks are checked against each other, not just against the reference:
	# check_for_desync() only watches sync_reference_player, so a vocal drifting away from
	# the OTHER vocal while both stay near the instrumental is invisible to the engine.
	# The first second is skipped - a seek and a stream start both read as a large drift
	# for a frame or two, and that transient is not what this is looking for.
	# Skipped once the instrumental has stopped: at the very last frame it reports 0 while
	# the vocals still report 142.1s, which reads as a 142-second desync and is nothing of
	# the kind.
	if _elapsed > 1.0 and _song.sync_reference_player.playing:
		var reference: float = _song.sync_reference_player.get_playback_position()
		var vocals: Array[float] = []
		for player: AudioStreamPlayer in _song.audio_players:
			if player == _song.sync_reference_player or not player.playing:
				continue
			vocals.append(player.get_playback_position())
			var drift: float = absf(player.get_playback_position() - reference)
			if drift > float(_worst_desync.get(player.name, 0.0)):
				_worst_desync[player.name] = drift
				_worst_at[player.name] = _clock.time_milliseconds / 1000.0
			if drift > 0.045:
				_over_threshold += 1
		if vocals.size() == 2:
			var between: float = absf(vocals[0] - vocals[1])
			if between > float(_worst_desync.get("entre voces", 0.0)):
				_worst_desync["entre voces"] = between
				_worst_at["entre voces"] = _clock.time_milliseconds / 1000.0

	_worst_frame = maxf(_worst_frame, root.get_process_delta_time())

	# A trace, not just a maximum: drift that climbs steadily is the two streams running at
	# different rates, and drift that spikes and recovers is the frame pacing of a headless
	# run. They need different answers, and a single worst-case number cannot tell them apart.
	if _elapsed - _last_trace >= 10.0:
		_last_trace = _elapsed
		var line: String = "OUT traza t=%6.1fs" % [_clock.time_milliseconds / 1000.0]
		var base: float = _song.sync_reference_player.get_playback_position()
		for player: AudioStreamPlayer in _song.audio_players:
			if player == _song.sync_reference_player:
				continue
			var drift_ms: float = (player.get_playback_position() - base) * 1000.0
			line += "  %s %+7.1f ms (%.0f buffers)" % [
				player.name.trim_prefix("Vocals"), drift_ms,
				roundf(drift_ms / MIX_BUFFER_MS)]
		print(line)

	if _elapsed < _duration:
		return

	print("OUT corrio %.1fs desde t=%.1f, reloj en %.2fs (compas %.1f, beat %.1f)" % [
		_elapsed, _start, _clock.time_milliseconds / 1000.0,
		_clock.time_measure, _clock.time_beat])

	for side: String in _controllers:
		var controller: Node = _controllers[side]
		print("OUT %-8s perfect=%d great=%d good=%d okay=%d bad=%d miss=%d combo=%d" % [
			side, controller.performance_hits_perfect, controller.performance_hits_great,
			controller.performance_hits_good, controller.performance_hits_okay,
			controller.performance_hits_bad, controller.performance_hits_miss,
			controller.performance_combo_value])

	for track_name: String in _worst_desync:
		print("OUT desfase maximo %-14s %6.1f ms  en t=%.1fs" % [
			track_name, float(_worst_desync[track_name]) * 1000.0,
			float(_worst_at.get(track_name, -1.0))])
	# Every non-zero reading is a whole number of these. get_playback_position() reports on
	# mix-buffer boundaries, so reading three players in the same frame can catch them a
	# buffer or two apart with nothing actually out of sync.
	print("OUT %d muestras por encima de 45 ms, frame mas largo %.1f ms, un buffer = %.2f ms" % [
		_over_threshold, _worst_frame * 1000.0, MIX_BUFFER_MS])

	for character_name: String in ["Tadano", "Komi"]:
		var character: Node = _level.find_child(character_name, true, false)
		var player: AnimationPlayer = character.animation_player
		print("OUT %-8s animacion=%s estado=%d" % [
			character_name, player.current_animation, character.state])

	quit(0)
