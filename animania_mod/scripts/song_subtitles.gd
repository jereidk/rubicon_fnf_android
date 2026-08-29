extends RichTextLabel
## The song's subtitles, read from the mod's own .srt.
##
## phone-call.script does not create these - the engine has a subtitle display and the
## script only restyles it (`subtitles.subtitleText.font = Paths.font('MP Manga.ttf')`,
## size 26). So the cues, their timings and their colours are the mod's; what the engine
## owns, and this port therefore has to choose, is the font - which this repo does not
## carry - and where on the screen the line sits.
##
## The import at the top of that script is `flixel.text.FlxTextBorderStyle`, which is the
## one piece of styling evidence there is: the text is outlined.

const SOURCE := "res://animania_mod/source/songs/phone-call/subtitles/song-lyrics.srt"

## The script's `size = 26`, in a project one and a half times Funkin's.
const FONT_SIZE := 39
const OUTLINE_SIZE := 12

## The line sits on a dark plate, not straight on the stage. Read off a capture of the mod
## at 9.2s: the wall behind the box measures (237.5, 191.1, 183.5) and the box over it
## (178.6, 140.7, 136.4) - the same 0.745 on all three channels, which is black at a
## quarter alpha and not a tint. Drawn with BBCode rather than a panel so it hugs the text
## the way the mod's does.
const BACKDROP := "#00000040"

@export var clock: Node

var _cues: Array[Dictionary] = []
## Which cue is on screen, so the text is only rebuilt when it actually changes.
var _showing: int = -1


func _ready() -> void:
	_cues = parse(FileAccess.get_file_as_string(SOURCE))
	text = ""


func _process(_delta: float) -> void:
	if clock == null or clock.animation_player == null:
		return

	var at: float = clock.animation_player.current_animation_position
	var index: int = -1
	for i: int in _cues.size():
		if at >= float(_cues[i]["from"]) and at < float(_cues[i]["to"]):
			index = i
			break

	if index == _showing:
		return
	_showing = index
	text = "" if index < 0 else "[center][bgcolor=%s]%s[/bgcolor][/center]" % [
		BACKDROP, String(_cues[index]["text"])]


## SubRip: blocks separated by a blank line, each an index, a `from --> to` line and the
## text. Static so the guard can derive its expectations from the same file rather than
## from numbers copied out of it.
static func parse(srt: String) -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	# The file is written with a BOM, which otherwise ends up inside the first index line.
	for block: String in srt.lstrip("\uFEFF").replace("\r\n", "\n").split("\n\n", false):
		var lines: PackedStringArray = block.strip_edges().split("\n")
		var arrow: int = -1
		for i: int in lines.size():
			if lines[i].contains("-->"):
				arrow = i
				break
		if arrow < 0 or arrow + 1 >= lines.size():
			continue

		var span: PackedStringArray = lines[arrow].split("-->")
		cues.append({
			"from": seconds_of(span[0]),
			"to": seconds_of(span[1]),
			"text": bbcode_of("\n".join(Array(lines.slice(arrow + 1)))),
		})
	return cues


## "00:01:04,700" - hours, minutes, seconds, and milliseconds behind a comma.
static func seconds_of(stamp: String) -> float:
	var parts: PackedStringArray = stamp.strip_edges().replace(",", ":").split(":")
	if parts.size() < 4:
		return 0.0
	return parts[0].to_float() * 3600.0 + parts[1].to_float() * 60.0 \
		+ parts[2].to_float() + parts[3].to_float() / 1000.0


## The cues carry `{font color="#rrggbb"}...{/font}`, which is Flixel's markup for the same
## thing BBCode spells `[color=...]`.
static func bbcode_of(line: String) -> String:
	var opening := RegEx.create_from_string('\\{font\\s+color="([^"]+)"\\}')
	return opening.sub(line, "[color=$1]", true).replace("{/font}", "[/color]")
