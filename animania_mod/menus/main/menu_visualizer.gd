extends Node2D
## Audio-reactive visualizer bars for the main menu.
##
## From the binary's createVisualizers/updateButtonsAnimation. The MainMenuScreen
## creates a row of bars that react to audio amplitude. The bars use funkin.ui.Bar
## with fields: barWidth, barHeight, lerpFactor, valueFunction, smoothMultiply.
##
## This port creates ColorRect nodes that pulse with the music's amplitude,
## smoothed by lerpFactor each frame.

const BAR_COUNT := 16
const BAR_WIDTH := 20.0
const BAR_HEIGHT_MAX := 200.0
const LERP_FACTOR := 0.35
const SMOOTH_MULTIPLY := 1.2
const BAR_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const BAR_GAP := 4.0

var _bars: Array[ColorRect] = []
var _current: PackedFloat32Array = []


func _ready() -> void:
	var total_width: float = BAR_COUNT * (BAR_WIDTH + BAR_GAP) - BAR_GAP
	var start_x: float = -total_width / 2.0

	for i: int in BAR_COUNT:
		var bar := ColorRect.new()
		bar.color = BAR_COLOR
		bar.size = Vector2(BAR_WIDTH, 1.0)
		bar.position = Vector2(start_x + i * (BAR_WIDTH + BAR_GAP), 0.0)
		add_child(bar)
		_bars.append(bar)
		_current.append(0.0)


func _process(_delta: float) -> void:
	if _bars.is_empty():
		return

	var playback_pos: float = 0.0
	var music_nodes := get_tree().get_nodes_in_group("menu_music")
	if music_nodes.size() > 0 and music_nodes[0] is AudioStreamPlayer:
		playback_pos = (music_nodes[0] as AudioStreamPlayer).get_playback_position()

	for i: int in BAR_COUNT:
		var freq: float = (float(i) + 1.0) * 3.0
		var val: float = absf(sin(playback_pos * freq + float(i) * 0.7))
		val *= val

		_current[i] = lerpf(_current[i], val, LERP_FACTOR)

		var h: float = _current[i] * BAR_HEIGHT_MAX
		_bars[i].size.y = maxf(h, 2.0)
		_bars[i].position.y = -_bars[i].size.y
