extends Node
## Ports funkin/backend/system/Conductor.hx — the base CodenameEngine
## timing/beat-tracking singleton (confirmed against its public source,
## github.com/CodenameCrew/CodenameEngine, since Conductor is a base-engine
## class, not something the Holy Quintet mod itself overrides, so it was
## never part of this port's own mod-source extraction). Named HQConductor
## rather than Conductor purely to match this port's own autoload naming
## convention (HQSaves/HQOptions/HQTransition) — the real class has no such
## prefix, it's just a plain global.
##
## Scope, clearly bounded: the real class also builds a whole bpmChangeMap
## from a chart's own "BPM Change"/"Time Signature Change"/"Continuous BPM
## Change" events (mapBPMChanges/mapEvent, plus continuous-change log/pow
## interpolation math), has Charter (chart editor) integration, and an
## IBeatReceiver interface that walks every FlxState's substate chain to
## call stepHit()/beatHit()/measureHit() directly on states that implement
## it. None of that is ported: this port has no ChartData, no chart events,
## no Charter, no gameplay/PlayState yet — inventing empty stand-ins for
## all of it now, with nothing real to drive it, would be speculative
## rather than a verified port. What IS ported is the part that's true
## regardless of whether any BPM-change map exists at all: with no chart
## loaded, the real class's own getBpm()/getStepCrochet()/etc. all fall
## through to a single flat, constant bpm (startingBPM) — exactly the case
## implemented here. Real onBeatHit/onStepHit/onMeasureHit are already
## plain FlxTypedSignals (a separate, more modern mechanism than the
## IBeatReceiver walk) — ported as real Godot signals, the natural
## equivalent, so any node just .connect()s instead of implementing an
## interface Godot has no equivalent concept for.
## When real chart/song playback gets built later, extend change_bpm()
## into a real bpm-change timeline instead of replacing this — the
## always-flat case should keep behaving exactly as it does today.

signal step_hit(step: int)
signal beat_hit(beat: int)
signal measure_hit(measure: int)
signal bpm_changed(new_bpm: float)

var bpm: float = 100.0
var beats_per_measure: float = 4.0
var steps_per_beat: int = 4

## Milliseconds. Real: Conductor.songPosition.
var song_position: float = 0.0
var cur_step: int = 0
var cur_beat: int = 0
var cur_measure: int = 0
var cur_step_float: float = 0.0
var cur_beat_float: float = 0.0
var cur_measure_float: float = 0.0

## The screen/menu currently driving song_position — set this to whatever
## AudioStreamPlayer is the "active music", the role FlxG.sound.music plays
## for the real global Conductor. null = no live clock (song_position stays
## wherever reset() left it, same as the real class with no music loaded).
var music_player: AudioStreamPlayer

var crochet: float:
	get:
		return 15000.0 * steps_per_beat / bpm
var step_crochet: float:
	get:
		return 15000.0 / bpm


func _ready() -> void:
	reset()


func reset() -> void:
	song_position = 0.0
	cur_step = 0
	cur_beat = 0
	cur_measure = 0
	cur_step_float = 0.0
	cur_beat_float = 0.0
	cur_measure_float = 0.0
	change_bpm()


func change_bpm(new_bpm: float = 100.0, new_beats_per_measure: float = 4.0, new_steps_per_beat: int = 4) -> void:
	bpm = new_bpm
	beats_per_measure = new_beats_per_measure
	steps_per_beat = new_steps_per_beat
	bpm_changed.emit(bpm)


func _process(_delta: float) -> void:
	if is_instance_valid(music_player) and music_player.playing:
		song_position = music_player.get_playback_position() * 1000.0

	var old_step := cur_step
	var old_beat := cur_beat
	var old_measure := cur_measure

	# Real update()'s "no BPM changes mapped" branch exactly: with a single
	# flat bpm, curStepFloat/curBeatFloat/curMeasureFloat are just
	# songPosition divided down through stepCrochet/stepsPerBeat/
	# beatsPerMeasure, no bpmChangeMap lookup needed.
	cur_step_float = song_position / step_crochet
	cur_beat_float = cur_step_float / steps_per_beat
	cur_measure_float = cur_beat_float / beats_per_measure

	cur_step = floori(cur_step_float)
	cur_beat = floori(cur_beat_float)
	cur_measure = floori(cur_measure_float)

	if cur_step != old_step:
		if cur_step > old_step:
			for i in range(old_step, cur_step):
				step_hit.emit(i + 1)
		else:
			step_hit.emit(cur_step)
	if cur_beat != old_beat:
		if cur_beat > old_beat:
			for i in range(old_beat, cur_beat):
				beat_hit.emit(i + 1)
		else:
			beat_hit.emit(cur_beat)
	if cur_measure != old_measure:
		if cur_measure > old_measure:
			for i in range(old_measure, cur_measure):
				measure_hit.emit(i + 1)
		else:
			measure_hit.emit(cur_measure)
