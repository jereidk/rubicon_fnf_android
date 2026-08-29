# Watches the STANDING pair for a few seconds after the swap and prints what they are
# actually playing, beat by beat.
#
# Written because they did neither: standUP() revealed them and rebound the cast, but never
# handed over `level_note_controller`, which is what subscribes a RubiconCharacter to
# note_changed and to the clock's step_change. Without it a character plays its autoplay
# dance_idle once when the scene loads and then stands still forever - no idle, no singing.
# A still frame cannot show that, and the camera harnesses that shoot this stretch all
# freeze the clock, so nothing here caught it.
#
# A pass is: both names change over the window, and at least one sing_* shows up.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/standup_dance.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
## Beat 232 at 152bpm is 91.58s. Start just after the swap and watch eight seconds of it.
const WATCH_FROM := 92.5
const WATCH_TO := 112.0
const WIND_SPEED := 20.0
const WATCHED := ["TadanoStand", "KomiStand"]

var _level: Node
var _clock: Node
var _frames: int = 0
var _wound: bool = false
var _seen: Dictionary = {}


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true
	for name: String in WATCHED:
		_seen[name] = {}


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	_clock = _level.get_node("RubiconLevelClock")
	var player: AnimationPlayer = _clock.animation_player
	var at: float = player.current_animation_position

	if not _wound:
		if at < WATCH_FROM:
			player.speed_scale = WIND_SPEED
			return
		player.speed_scale = 1.0
		_wound = true

	for name: String in WATCHED:
		var character: Node = _level.find_child(name, true, false)
		if character == null:
			continue
		var root: AnimationPlayer = character.get_node("RootAnimationPlayer")
		var playing: String = root.current_animation
		var bound: bool = character.get(&"level_note_controller") != null
		var key: String = "%s%s" % [playing, "" if bound else " (SIN CONTROLADOR)"]
		_seen[name][key] = int(_seen[name].get(key, 0)) + 1

	if at >= WATCH_TO:
		for name: String in WATCHED:
			var names: Array = (_seen[name] as Dictionary).keys()
			names.sort()
			var parts: PackedStringArray = []
			for entry: String in names:
				parts.append("%s x%d" % ["(ninguna)" if entry.is_empty() else entry,
					int(_seen[name][entry])])
			print("OUT %-12s %s" % [name, ", ".join(parts)])
		get_tree().quit()
