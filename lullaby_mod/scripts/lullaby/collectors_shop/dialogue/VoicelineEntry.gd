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

## Whether a threaded warm has been asked for. See warm().
var _requested: bool = false

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

	# Blocking on purpose. This is the path taken when the line is about to
	# play, and silence would be worse than a stall - warm() exists so this
	# is rarely reached with nothing ready. If a threaded warm is already in
	# flight, collect that rather than starting a second load of the same
	# file.
	if _requested and ResourceLoader.load_threaded_get_status(stream_path) != ResourceLoader.THREAD_LOAD_FAILED:
		_loaded = ResourceLoader.load_threaded_get(stream_path) as AudioStream
	else:
		_loaded = load(stream_path) as AudioStream
	return _loaded

## Loads the audio without needing it yet.
##
## Called off the critical path once the room is up, so a line is in memory
## before anything plays it and the lazy path never costs a hitch mid-dialogue.
func warm() -> void:
	if stream != null or _loaded != null or stream_path.is_empty():
		return

	# Threaded, because this runs from the shop's _process, one line per
	# frame, and a blocking load() of an .ogg on this device is not a frame.
	# The device log measured the damage: the shop's two worst script frames
	# are 111.47ms and 71.90ms, both with every note-system field at zero and
	# anim2d at zero, both in the only scene that warms voicelines. Warming
	# was added to take 109 .ogg files off the shop's cold load and it moved
	# their cost into gameplay instead, one stall at a time.
	if not _requested:
		_requested = true
		ResourceLoader.load_threaded_request(stream_path)
		return

	# Only collected once the thread says it is done. load_threaded_get()
	# blocks until the load finishes, so asking early would reintroduce
	# exactly the stall this avoids.
	if ResourceLoader.load_threaded_get_status(stream_path) == ResourceLoader.THREAD_LOAD_LOADED:
		_loaded = ResourceLoader.load_threaded_get(stream_path) as AudioStream

## Whether the audio is in memory already.
func is_warm() -> bool:
	return stream != null or _loaded != null

@export_multiline var dialogue_text: String = ""

@export_enum("BUSY", "FREE_LOOK", "FOCUSED", "NONE")
var state: int = 1

@export_enum("BUSY", "FREE_LOOK", "FOCUSED", "NONE")
var ending_state: int = 2
