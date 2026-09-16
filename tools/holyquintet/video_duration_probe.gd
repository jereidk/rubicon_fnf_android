extends Node
# Measures the REAL playback duration Godot's VideoStreamPlayer reports for
# each HQIntro video, by starting playback and polling stream_position every
# frame until the 'finished' signal fires. This is the only measure that
# actually matters for the _on_yes_video_finished()/_on_no_video_finished()
# scene-transition timing in intro_screen.gd — ffprobe's Ogg duration/frame-
# count estimates proved unreliable for this content (sseof seeking fails
# outright on these files, and container 'duration' metadata undercounts
# trailing held frames).
#
# EXPECTED_TRUE_DURATION below is each video's real duration measured by
# fully decoding the ORIGINAL .mp4 source (ffprobe -count_frames + last
# frame's pts_time), before HEVC->Theora conversion. Ogg Theora's own
# duplicate-frame collapsing already makes every one of these play a little
# short of that true figure (a pre-existing gap, not introduced by re-
# encoding); this probe exists to catch a NEW regression that makes the
# gap meaningfully worse (confirmed: raising the keyframe interval to
# smooth out wasted keyframe bytes is safe for intro_start/intro_no, but
# cuts ~0.8s off intro_yes because of its long trailing static hold, so
# intro_yes intentionally keeps its original tighter keyframe interval).
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/holyquintet/video_duration_probe.tscn

const FILES := [
	"res://holyquintet_mod/source/videos/intro_start.ogv",
	"res://holyquintet_mod/source/videos/intro_yes.ogv",
	"res://holyquintet_mod/source/videos/intro_no.ogv",
]

const EXPECTED_TRUE_DURATION := {
	"res://holyquintet_mod/source/videos/intro_start.ogv": 12.679333,
	"res://holyquintet_mod/source/videos/intro_yes.ogv": 16.533183,
	"res://holyquintet_mod/source/videos/intro_no.ogv": 2.769433,
}

var _player: VideoStreamPlayer
var _index: int = 0
var _start_ticks: int = 0
var _max_reported_pos: float = 0.0


func _ready() -> void:
	_player = VideoStreamPlayer.new()
	_player.expand = true
	add_child(_player)
	_next_file()


func _next_file() -> void:
	if _index >= FILES.size():
		print("VIDEO_DURATION_PROBE: all done")
		get_tree().quit()
		return
	var path: String = FILES[_index]
	_player.stream = load(path)
	_max_reported_pos = 0.0
	_start_ticks = Time.get_ticks_msec()
	if _player.finished.is_connected(_on_finished):
		_player.finished.disconnect(_on_finished)
	_player.finished.connect(_on_finished)
	_player.play()
	print("PROBE_START: ", path)


func _process(_delta: float) -> void:
	if _player.stream == null or not _player.is_playing():
		return
	_max_reported_pos = max(_max_reported_pos, _player.stream_position)


func _on_finished() -> void:
	var path: String = FILES[_index]
	var expected: float = EXPECTED_TRUE_DURATION[path]
	var shortfall: float = expected - _max_reported_pos
	print("PROBE_FINISHED: ", path,
		" played=", _max_reported_pos,
		" expected_true=", expected,
		" shortfall=", shortfall)
	_index += 1
	_next_file()
