extends Node2D
## createVisualizers (0x17ff530), which this port did not have. What was here instead was
## sixteen ColorRects driven by `sin(playback_position * i)` - no audio in it at all - and
## it was not even in the scene, so the menu drew nothing.
##
## The mod builds two things:
##
##     waveform = new WaveformSprite(FlxG.sound.music.waveformData, VERTICAL, -1, 1.25)
##     waveform.setPosition(-100, -15)          # 0x17ff65a
##     waveform.setSize(256, 900)               # 0x17ff687
##     waveform.alpha = 0.8                     # 0x17ff6b0
##     bars = new BarsVisualizer(-90, 390, 950, 350)   # 0x17ff732
##     bars.initBars(); bars.initAnalyzer(FlxG.sound.music)
##
## BarsVisualizer's own constructor (0x51c4ea0) carries the rest: 24 bars (0x51c4fc1),
## alpha 0.6 (0x51c4fb3) and a five-stop gradient (_hx_array_data_8fff23e0_1). initBars
## (0x51c5620) divides the visualiser's width by the bar count, draws each bar that wide
## minus 5 (0x51c5984) and the full height, and puts them at x = this.x + i * barWidth,
## y = this.y. drawFFT then writes each bar's scale.y - and Flixel scales about the frame's
## centre, so a bar grows out of the middle of the band rather than up from its floor.
##
## Where the DATA comes from is this port's, and is the one thing here that is not measured:
## Godot cannot hand back an ogg's samples, so the bars read an AudioEffectSpectrumAnalyzer
## and the waveform an AudioEffectCapture, both hung on the Music bus. The mod reads the
## song's own decoded waveform, which is the same picture from a different door.

const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

## The one calibration this menu has between the binary's world coordinates and where the
## mod's capture puts things. See main_menu.gd's WORLD_OFFSET.
const WORLD_OFFSET := Vector2(-4.0, -37.0)

const WAVE_POS := Vector2(-100.0, -15.0)
const WAVE_SIZE := Vector2(256.0, 900.0)
const WAVE_ALPHA := 0.8
## The window WaveformSprite shows, off its field at 0x278.
const WAVE_SECONDS := 1.5
## One column of the drawn waveform per this many pixels, so the shape stays cheap.
const WAVE_STEP := 3.0

const BARS_POS := Vector2(-90.0, 390.0)
const BARS_SIZE := Vector2(950.0, 350.0)
const BAR_COUNT := 24
const BAR_GAP := 5.0
const BAR_ALPHA := 0.6
## _hx_array_data_8fff23e0_1, read as ARGB: white, then the same pale yellow twice at 69%,
## then pink, then cyan.
const BAR_GRADIENT: Array[Color] = [
	Color(1.0, 1.0, 1.0, 1.0),
	Color(254.0 / 255.0, 249.0 / 255.0, 193.0 / 255.0, 177.0 / 255.0),
	Color(254.0 / 255.0, 249.0 / 255.0, 193.0 / 255.0, 177.0 / 255.0),
	Color(1.0, 192.0 / 255.0, 203.0 / 255.0, 1.0),
	Color(0.0, 1.0, 1.0, 1.0),
]

const MUSIC_BUS := &"Music"
## How fast a bar catches up with the band it is drawing. The mod lerps by elapsed * 3.
const BAR_LERP := 12.0
const MIN_HZ := 40.0
const MAX_HZ := 16000.0

var _bars: Array[Sprite2D] = []
var _levels: PackedFloat32Array = []
var _spectrum: AudioEffectSpectrumAnalyzerInstance = null
var _capture: AudioEffectCapture = null
var _wave: Line2D = null
var _samples: PackedFloat32Array = []
var _bus: int = -1
var _analyzer_fx: AudioEffect = null
var _capture_fx: AudioEffect = null


func _ready() -> void:
	_build_bars()
	_build_waveform()
	_attach_effects()


func _exit_tree() -> void:
	_detach_effects()


# ─── initBars ─────────────────────────────────────────────────────────────

func _build_bars() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array()
	gradient.colors = PackedColorArray()
	for i: int in BAR_GRADIENT.size():
		gradient.add_point(float(i) / float(BAR_GRADIENT.size() - 1), BAR_GRADIENT[i])
	# add_point keeps the two stops Gradient starts life with; drop them.
	while gradient.get_point_count() > BAR_GRADIENT.size():
		gradient.remove_point(0)

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 8
	tex.height = 128

	var bar_width: float = BARS_SIZE.x / float(BAR_COUNT)
	var drawn: float = bar_width - BAR_GAP
	for i: int in BAR_COUNT:
		var bar := Sprite2D.new()
		bar.name = "Bar%d" % i
		bar.centered = true
		bar.texture = tex
		bar.modulate = Color(1.0, 1.0, 1.0, BAR_ALPHA)
		# Flixel scales about the frame's centre, so the bar's anchor is the middle of the
		# band and scale.y opens it both ways.
		var centre := Vector2(
			BARS_POS.x + float(i) * bar_width + drawn * 0.5,
			BARS_POS.y + BARS_SIZE.y * 0.5)
		bar.position = _world(centre)
		bar.scale = Vector2(
			drawn / float(tex.width) * FUNKIN_TO_RUBICON,
			0.0)
		bar.set_meta(&"full", BARS_SIZE.y / float(tex.height) * FUNKIN_TO_RUBICON)
		add_child(bar)
		_bars.append(bar)
		_levels.append(0.0)


# ─── WaveformSprite ───────────────────────────────────────────────────────

func _build_waveform() -> void:
	_wave = Line2D.new()
	_wave.name = "Waveform"
	_wave.width = 2.0
	_wave.default_color = Color(1.0, 1.0, 1.0, WAVE_ALPHA)
	_wave.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_wave)


func _attach_effects() -> void:
	_bus = AudioServer.get_bus_index(MUSIC_BUS)
	if _bus < 0:
		return
	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.buffer_length = 0.1
	AudioServer.add_bus_effect(_bus, analyzer)
	_analyzer_fx = analyzer
	_spectrum = AudioServer.get_bus_effect_instance(
		_bus, AudioServer.get_bus_effect_count(_bus) - 1) \
		as AudioEffectSpectrumAnalyzerInstance

	var capture := AudioEffectCapture.new()
	capture.buffer_length = WAVE_SECONDS * 2.0
	AudioServer.add_bus_effect(_bus, capture)
	_capture_fx = capture
	_capture = capture


## By identity, not by the index they went in at: the story-select sub-state hangs its own
## filters on this same bus, and an index taken at _ready is stale the moment it does.
func _detach_effects() -> void:
	if _bus < 0:
		return
	for fx: AudioEffect in [_capture_fx, _analyzer_fx]:
		if fx == null:
			continue
		for i: int in range(AudioServer.get_bus_effect_count(_bus) - 1, -1, -1):
			if AudioServer.get_bus_effect(_bus, i) == fx:
				AudioServer.remove_bus_effect(_bus, i)
				break
	_spectrum = null
	_capture = null
	_analyzer_fx = null
	_capture_fx = null


# ─── drawFFT ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_drive_bars(delta)
	_drive_waveform()


func _drive_bars(delta: float) -> void:
	if _bars.is_empty():
		return
	var step: float = pow(MAX_HZ / MIN_HZ, 1.0 / float(BAR_COUNT))
	var edge: float = MIN_HZ
	var catch_up: float = minf(1.0, BAR_LERP * delta)
	for i: int in _bars.size():
		var top: float = edge * step
		var level: float = 0.0
		if _spectrum != null:
			var mag: Vector2 = _spectrum.get_magnitude_for_frequency_range(edge, top)
			# The analyser reports linear magnitude; the ear and the mod's bars are both
			# closer to a decibel scale.
			level = clampf((60.0 + linear_to_db(maxf(mag.x, mag.y))) / 60.0, 0.0, 1.0)
		edge = top
		_levels[i] = lerpf(_levels[i], level, catch_up)
		var bar: Sprite2D = _bars[i]
		bar.scale.y = float(bar.get_meta(&"full")) * _levels[i]


func _drive_waveform() -> void:
	if _wave == null:
		return
	if _capture != null:
		var available: int = _capture.get_frames_available()
		if available > 0:
			var frames: PackedVector2Array = _capture.get_buffer(available)
			for frame: Vector2 in frames:
				_samples.append((frame.x + frame.y) * 0.5)
	var wanted: int = int(WAVE_SECONDS * AudioServer.get_mix_rate())
	if _samples.size() > wanted:
		_samples = _samples.slice(_samples.size() - wanted)
	if _samples.is_empty():
		_wave.clear_points()
		return

	# VERTICAL: time runs down the box, amplitude across it, mirrored about the middle.
	var rows: int = int(WAVE_SIZE.y / WAVE_STEP)
	var spine: float = WAVE_POS.x + WAVE_SIZE.x * 0.5
	var half: float = WAVE_SIZE.x * 0.5
	var per_row: int = maxi(1, _samples.size() / maxi(1, rows))
	var points := PackedVector2Array()
	for r: int in rows:
		var start: int = r * per_row
		if start >= _samples.size():
			break
		var peak: float = 0.0
		for k: int in mini(per_row, _samples.size() - start):
			peak = maxf(peak, absf(_samples[start + k]))
		var y: float = WAVE_POS.y + float(r) * WAVE_STEP
		points.append(_world(Vector2(spine + peak * half, y)))
	for r: int in range(points.size() - 1, -1, -1):
		var p: Vector2 = points[r]
		var mirrored: float = _world(Vector2(spine, 0.0)).x
		points.append(Vector2(mirrored - (p.x - mirrored), p.y))
	_wave.points = points


func _world(p: Vector2) -> Vector2:
	return (p + WORLD_OFFSET) * FUNKIN_TO_RUBICON
