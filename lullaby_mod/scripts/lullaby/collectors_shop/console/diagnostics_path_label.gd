extends Label

## Read-only row under Misc > Diagnostics Log saying where the log actually
## went this session.
##
## The log tries three directories in order and falls back quietly, so
## "diagnostics are on" has never told the player - or anyone reading a bug
## report - which file to go and fetch. The log itself records dir_used in
## its own header, which is no help to someone who cannot find the file in
## the first place.
##
## Reads DiagnosticsLog by node name rather than by class: the log turns
## itself off (set_process(false) and no file) when the setting is off, and
## the shop is also opened straight from the editor often enough that this
## must not hard-depend on the autoload being there.

## Refreshed on Settings.applied rather than per frame - the path only
## changes when a new session opens a new file, and this sits in a menu that
## already redraws on every option row.
func _ready() -> void:
	_refresh()
	if Settings.has_signal(&"applied"):
		Settings.applied.connect(_refresh)

func _refresh() -> void:
	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	var path: String = ""
	if log_node != null:
		path = String(log_node.get(&"log_path"))

	if path.is_empty():
		# Either the setting is off, or every candidate directory refused to
		# be written to. Both mean "there is no file to go and get".
		text = "No log this session"
		return

	# The directory is the useful half: the file name carries a timestamp
	# and there is a rotation of five of them in there.
	text = path.get_base_dir()
