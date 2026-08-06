class_name LullabyForceScreenAspect extends Node

## Pins the window's content-scale aspect while this scene is loaded, and
## puts the player's own choice back on the way out.
##
## Chimera's stage is authored for a 16:9 frame. Under "Wide"
## (CONTENT_SCALE_ASPECT_EXPAND) a wide phone gets extra game world at the
## sides instead of the same frame letterboxed, and the song's stage breaks:
## the extra width shows past what the scene was built to cover. Normal
## (KEEP) locks the design aspect and pillarboxes the rest.
##
## This deliberately does NOT touch Settings.display_screen_aspect - the
## player's preference is left alone and restored on exit, so leaving the
## song puts everything back and nothing is written to disk.
##
## content_scale_aspect is a Window property, so this is inevitably global
## while it is in force. That is fine for the debug display, which renders
## correctly either way.

## The aspect to hold while this node is in the tree. Defaults to KEEP,
## which is what the console's Screen Mode calls "Normal".
@export var forced_aspect: Window.ContentScaleAspect = Window.ContentScaleAspect.CONTENT_SCALE_ASPECT_KEEP

func _ready() -> void:
	_apply()

	# Settings.apply_settings() assigns window.content_scale_aspect from
	# display_screen_aspect, so anything the player changes in the pause
	# menu would silently undo this. Re-pin on every apply.
	if Settings.has_signal("applied"):
		Settings.applied.connect(_apply)

	tree_exiting.connect(_restore)

func _apply() -> void:
	var window: Window = get_window()
	if window != null and window.content_scale_aspect != forced_aspect:
		window.content_scale_aspect = forced_aspect

func _restore() -> void:
	if Settings.has_signal("applied") and Settings.applied.is_connected(_apply):
		Settings.applied.disconnect(_apply)

	var window: Window = get_window()
	if window != null:
		window.content_scale_aspect = Settings.display_screen_aspect
