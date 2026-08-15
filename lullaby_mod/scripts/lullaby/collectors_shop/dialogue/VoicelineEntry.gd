extends Resource
class_name VoicelineEntry

enum ShopStates{
	BUSY, 
	FREE_LOOK, 
	FOCUSED, 
}

## The line's audio, held as a path rather than as a reference.
##
## This used to be `@export var stream: AudioStream`, which puts an
## ExtResource in the .tres - and an ExtResource is loaded by whatever loads
## the file holding it. The Collector's Shop reaches 32 voiceline groups and
## through them 109 .ogg files: 21% of the 512 files behind the room, none of
## which the room needs in order to appear.
##
## That matters because the shop's cold load is per-file cost rather than
## bandwidth. Traced on the device it makes continuous progress and simply
## slows down - 777 resources in the first 14 seconds with VRAM climbing 33MB,
## then 301 in the next 16 with VRAM climbing 6MB. Three hundred small files at
## roughly 53ms each, and 109 reactive lines for outcomes that mostly did not
## happen this visit are the largest identified block of exactly that.
##
## A path costs nothing to load and resolves on first use.
@export_file("*.ogg", "*.wav") var stream_path: String = ""

## Still honoured for any .tres holding a direct reference.
##
## Nothing in this project should after the migration, but a resource format
## that silently ignores a field somebody set is worse than one carrying both,
## and it keeps the editor's own drag-and-drop working.
@export var stream: AudioStream

## Resolved audio, once something has asked for it.
var _loaded: AudioStream

## The line's audio, loading it if this is the first time it is needed.
##
## Read this rather than `stream`: that field is only the direct-reference
## fallback and is null on a migrated entry.
func get_stream() -> AudioStream:
	if stream != null:
		return stream
	if _loaded != null:
		return _loaded
	if stream_path.is_empty():
		return null

	_loaded = load(stream_path) as AudioStream
	return _loaded

## Loads the audio without needing it yet.
##
## Called off the critical path once the room is up, so a line is in memory
## before anything plays it and the lazy path never costs a hitch mid-dialogue.
func warm() -> void:
	get_stream()

## Whether the audio is in memory already.
func is_warm() -> bool:
	return stream != null or _loaded != null

@export_multiline var dialogue_text: String = ""

@export_enum("BUSY", "FREE_LOOK", "FOCUSED", "NONE")
var state: int = 1

@export_enum("BUSY", "FREE_LOOK", "FOCUSED", "NONE")
var ending_state: int = 2
