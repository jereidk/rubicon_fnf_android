extends Resource
class_name VoicelineGroup

@export var group_name: String = ""
@export var voicelines: Array[VoicelineEntry] = []

## Loads one line's audio that has not been loaded yet, and says whether there
## was one.
##
## Deliberately one at a time rather than a whole group at once: this runs
## while the player is in the room, so it has to stay off the frame. The
## caller drives it - see env_collector_shop.gd, which pulls one per frame
## until every group reports done.
func warm_next() -> bool:
	for entry in voicelines:
		if entry != null and not entry.is_warm():
			entry.warm()
			return true
	return false

