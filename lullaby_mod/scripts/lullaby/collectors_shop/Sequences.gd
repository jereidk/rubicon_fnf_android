@tool
class_name ShopSequences
extends Node

@export_group("Voiceline Sync")

## Sequence voicelines, keyed by animation name and held as paths.
##
## These used to be `Dictionary[String, AudioStream]`, which puts an
## ExtResource in the scene and loads the audio when the room does.
## sequence_intro alone is a megabyte and plays once in a save's lifetime;
## sequence_outro is another half. The shop's cold load is bound by per-file
## cost, so anything that can arrive later should.
@export var voiceline_paths: Dictionary[String, String] = {}

## Still honoured for any scene holding direct references, same reasoning as
## VoicelineEntry: a format that ignores a field somebody filled in is worse
## than one that accepts both.
@export var voicelines: Dictionary[String, AudioStream] = {}
@export var voiceline_offset: float = 0.0
@export var voiceline_desync_threshold: float = 0.045

var animation_player: AnimationPlayer:
	get:
		return _animation_player
var _animation_player: AnimationPlayer

var voiceline: AudioStreamPlayer3D:
	get:
		return _voiceline
var _voiceline: AudioStreamPlayer3D

func _ready() -> void :
	update_children()
	update_configuration_warnings()

func _process(_delta: float) -> void :
	if not Engine.is_editor_hint():
		_warm_one()

	sync_players()
	sync_voiceline()

## Resolved audio, once something has asked for it.
var _resolved: Dictionary[String, AudioStream] = {}

## The voiceline for an animation, loading it if this is the first time it is
## needed. Null when the animation has none, which is most of them.
func get_voiceline(anim: String) -> AudioStream:
	if voicelines.has(anim):
		return voicelines[anim]
	if _resolved.has(anim):
		return _resolved[anim]
	if not voiceline_paths.has(anim):
		return null

	var stream: AudioStream = load(voiceline_paths[anim]) as AudioStream
	_resolved[anim] = stream
	return stream

## Pulls in one unresolved voiceline per frame once the room is running.
##
## Without this the first frame of a sequence would pay for its own load, and
## a sequence is exactly where a hitch is most visible. There are only three,
## so they are all resident within three frames of the room appearing.
func _warm_one() -> void:
	for anim in voiceline_paths:
		if not _resolved.has(anim):
			get_voiceline(anim)
			return

func _notification(what: int) -> void :
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		update_children()
		update_configuration_warnings()

func update_children() -> void :
	_animation_player = get_child(0) as AnimationPlayer if get_child_count() > 0 else null
	_voiceline = get_child(1) as AudioStreamPlayer3D if get_child_count() > 1 else null

func sync_players() -> void :
	if animation_player == null:
		update_children()
		return

	var anim: = animation_player.current_animation
	if anim == "":
		return

func sync_voiceline() -> void :
	if animation_player == null or voiceline == null:
		return

	if not animation_player.is_playing():
		return

	var anim: = animation_player.current_animation

	if anim == "":
		voiceline.stop()
		return

	var stream: AudioStream = get_voiceline(anim)
	if stream == null:
		return

	if voiceline.stream != stream:
		voiceline.stop()
		voiceline.stream = stream

	var target_time: = animation_player.current_animation_position + voiceline_offset

	if target_time < 0.0:
		voiceline.stop()
		return

	var stream_length: = stream.get_length()

	if stream_length > 0.0 and target_time >= stream_length:
		voiceline.stop()
		return

	voiceline.stream_paused = false

	if not voiceline.playing:
		voiceline.play(target_time)
		return

	if abs(voiceline.get_playback_position() - target_time) > voiceline_desync_threshold:
		voiceline.seek(target_time)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []

	if animation_player == null:
		warnings.append("ShopSequences requires its first child to be an AnimationPlayer.")

	if voiceline == null:
		warnings.append("ShopSequences expects its second child to be an AudioStreamPlayer3D.")

	return warnings
