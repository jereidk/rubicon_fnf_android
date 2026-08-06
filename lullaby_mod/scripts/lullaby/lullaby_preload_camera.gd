extends Camera3D

@export var animation_player: AnimationPlayer
@export var animation_name: StringName
@export var camera_to_focus: Camera3D

var _started_msec: int = 0

func _ready() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS

	if !SceneChanger.awaiting_manual_end:
		finish_preload()
		return

	visible = true
	make_current()
	_started_msec = Time.get_ticks_msec()
	_mark("preload camera '%s' started on %s" % [animation_name, get_parent().scene_file_path.get_file()])
	animation_player.play(animation_name)

	animation_player.animation_finished.connect(finish_preload)

func finish_preload(_anim: StringName = &"") -> void :
	# 0 when the manual-end branch above skipped straight here without ever
	# starting an animation - worth distinguishing from an animation that
	# genuinely finished in under a millisecond.
	if _started_msec > 0:
		_mark("preload camera '%s' finished (%dms)" % [animation_name, Time.get_ticks_msec() - _started_msec])

	if camera_to_focus != null and !camera_to_focus.current:
		camera_to_focus.make_current()

	if SceneChanger.awaiting_manual_end:
		SceneChanger.finish_loading_screen()
	queue_free()

# Soft dependency: this camera is also used in scenes opened directly from
# the editor, where DiagnosticsLog's autoload chain may not be running.
func _mark(what: String) -> void :
	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node != null and log_node.has_method("mark"):
		log_node.call("mark", what)
