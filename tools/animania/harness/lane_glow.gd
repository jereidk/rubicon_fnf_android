# Measures how long an AUTOPLAYED lane stays lit, which is the only way to tell a lane that
# glows on taps from one that also glows through a sustain.
#
# The opponent is autoplayed, and the clear that resets an autoplayed lane reads the note
# BEHIND note_hit_index - which does not advance while a hold is live. So mid-hold it was
# reading the note before the sustain, seeing a completed hit, and clearing: komi's side lit
# on every tap and never on a hold. A still cannot show this and neither can a frame count;
# what shows it is the longest continuous run of LANE_STATE_HIT.
#
# The window covers a 592ms sustain on the opponent's `right` lane at 28.03s, so a pass is a
# run comfortably past a single frame on that lane.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/lane_glow.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
const WATCH_FROM := 21.0
const WATCH_TO := 31.0
const WIND_SPEED := 20.0

var _level: Node
var _lanes: Array[Node] = []
var _longest: Array[float] = []
var _current: Array[float] = []
var _frames: int = 0
var _wound: bool = false


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true
	for lane: Node in _level.get_node("UILayer/UI/Opponent").get_children():
		if lane.has_method(&"get_mode_id"):
			_lanes.append(lane)
			_longest.append(0.0)
			_current.append(0.0)


func _process(delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	var player: AnimationPlayer = _level.get_node("RubiconLevelClock").animation_player
	if not _wound:
		if player.current_animation_position < WATCH_FROM:
			player.speed_scale = WIND_SPEED
			return
		player.speed_scale = 1.0
		_wound = true

	for i: int in _lanes.size():
		# LANE_STATE_HIT is 2; PUSH is 1 and NEUTRAL is 0.
		if int(_lanes[i].lane_state) == 2:
			_current[i] += delta
			_longest[i] = maxf(_longest[i], _current[i])
		else:
			_current[i] = 0.0

	if player.current_animation_position >= WATCH_TO:
		for i: int in _lanes.size():
			print("OUT carril %d del oponente: encendido %.0f ms seguidos como maximo"
				% [int(_lanes[i].lane_id), _longest[i] * 1000.0])
		get_tree().quit()
