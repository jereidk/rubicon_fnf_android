extends Node2D
## The title screen.
##
## Two phases, and they come from two different places. The intro - the text that spells
## itself out over black for the first 31 beats - is `TitleScreen.script`, which the mod
## ships as plain HScript, so this half is transcribed rather than guessed. What follows it
## is `animania.states.TitleScreen`, compiled into the game's binary, so the logo and the
## press-enter prompt are here with their real assets and animations but a layout this port
## chose. See animania_mod/source/README.md.
##
## The beat is the music's: animaniaINTRO is 102bpm 4/4 per its own metadata, so a beat is
## 60/102 seconds. Funkin drives titleBeat off the Conductor the same way.

const BPM := 102.0

## case 31 tweens the last line up and out over .6s with a circIn ease.
const FINALE_SECONDS := 0.6
const FINALE_SCALE := 1.25
const FINALE_RISE := -100.0

## The colour the script's <a> markup applies, as FlxTextFormat(0xFFAAD2FF).
const ACCENT := Color8(0xAA, 0xD2, 0xFF)

## Every beat that does something, transcribed from titleBeat(). `text` replaces the line,
## `add` appends to it, `clear` empties it, `zoom` punches the camera, and `hold` is the
## script's `skipTween` - the beats that place the text themselves instead of letting the
## default tween slide it into the middle of the screen.
const BEATS := {
	1: {"text": "[accent]ANIMANIA!CREW[/accent]"},
	3: {"text": "[accent]ANIMANIA!CREW[/accent]\nPRESENTS"},
	4: {"clear": true},
	5: {"text": "HAVING FUN?"},
	7: {"add": "\nGOOD"},
	8: {"clear": true},
	9: {"text": "WOOF WOOF"},
	11: {"add": "\nWE FUNK"},
	12: {"clear": true},
	13: {"text": "FNF"},
	15: {"add": "\nIS REAL"},
	16: {"clear": true},
	17: {"text": "GOD DAMN THE SUN"},
	19: {"add": "\nMY EYES"},
	20: {"clear": true, "hold": true, "y": 350.0},
	21: {"text": "WE ARE"},
	23: {"add": "\nSO REAL"},
	24: {"clear": true, "hold": true, "y": 0.0},
	25: {"text": "FUNKIN\n"},
	27: {"add": "FOREVER"},
	28: {"text": "FRIDAY\n", "alpha": 0.0, "zoom": 0.05},
	29: {"add": "NIGHT\n", "zoom": 0.075},
	30: {"add": "FUNKIN'\n", "zoom": 0.1},
	31: {"add": "[accent]ANIMANIA![/accent]", "hold": true, "zoom": 0.15, "finale": true},
}

## The last beat the intro spells, after which the title proper takes over.
const LAST_BEAT := 31

@export var music: AudioStreamPlayer
@export var intro_text: RichTextLabel
@export var title: Node2D
@export var camera: Camera2D

var _beat: int = 0
var _elapsed: float = 0.0
var _line: String = ""
var _done: bool = false


func _ready() -> void:
	title.visible = false
	intro_text.visible = false
	intro_text.text = ""
	if music != null:
		music.play()


func _process(delta: float) -> void:
	if _done:
		return

	_elapsed += delta
	var beat: int = floori(_elapsed * BPM / 60.0)
	while _beat < beat:
		_beat += 1
		_run_beat(_beat)


## titleBeat(beat). The default tween at the bottom runs on every beat the script does not
## set skipTween on - it slides the line to the middle of the screen and fades it in over
## beatLengthMs / 1250, which at 102bpm is not quite half a beat.
func _run_beat(beat: int) -> void:
	if beat > LAST_BEAT:
		_finish()
		return

	var step: Dictionary = BEATS.get(beat, {})
	if step.is_empty():
		return

	if step.has("clear"):
		_line = ""
	elif step.has("text"):
		_line = String(step["text"])
	elif step.has("add"):
		_line += String(step["add"])

	intro_text.visible = not _line.is_empty()
	intro_text.text = "[center]%s[/center]" % _line.replace(
		"[accent]", "[color=#%s]" % ACCENT.to_html(false)).replace("[/accent]", "[/color]")

	if step.has("alpha"):
		intro_text.modulate.a = float(step["alpha"])
	if step.has("y"):
		intro_text.position.y = float(step["y"])
	if step.has("zoom") and camera != null:
		camera.zoom += Vector2.ONE * float(step["zoom"])

	if step.has("finale"):
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(intro_text, "scale", Vector2.ONE * FINALE_SCALE,
			FINALE_SECONDS).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
		tween.tween_property(intro_text, "position:y",
			intro_text.position.y + FINALE_RISE, FINALE_SECONDS) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_IN)
		return

	if step.get("hold", false):
		return

	# The default tween: to the middle of the screen, fading in.
	var slide: Tween = create_tween().set_parallel(true)
	slide.tween_property(intro_text, "position:x", 0.0, 60.0 / BPM / 1.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	slide.tween_property(intro_text, "modulate:a", 1.0, 60.0 / BPM / 1.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## moveToMain: the intro is over and the title itself comes up.
func _finish() -> void:
	_done = true
	intro_text.visible = false
	title.visible = true


## skipIntro, on any key.
func _unhandled_input(event: InputEvent) -> void:
	if _done or not event.is_pressed():
		return
	if event is InputEventKey or event is InputEventScreenTouch:
		_finish()
