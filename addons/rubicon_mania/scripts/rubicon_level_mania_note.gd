@tool
class_name RubiconLevelManiaNote extends RubiconLevelNote

@export var lane_id : int = 0
@export var local_direction : float = 0.0

@export_group("Offset", "offset_")
@export var offset_position : Vector2
@export var offset_rotation : float
@export var offset_scale : Vector2 = Vector2.ONE

@export_group("References", "reference_")
@export var reference_graphic : Control
@export var reference_trail : Control
@export var reference_container : Control

var _last_final_rotation : float = INF

## DirectionTree, MissedTree and HeldTree. Their state machines read only
## lane_id, was_hit() and was_missed(), so they are advanced only when one of
## those has moved rather than every frame. See RubiconMixerPump.
var _pump : RubiconMixerPump = RubiconMixerPump.new()
var _last_was_hit : bool = false
var _last_was_missed : bool = false

func get_mania_handler() -> RubiconLevelManiaNoteHandler:
	return _handler

func _ready() -> void:
	# The editor keeps the stock behaviour, so the scene previews the way it
	# always has.
	if Engine.is_editor_hint():
		return

	_pump.adopt_children_of(self)

func initialize(handler : RubiconLevelNoteHandler, data_index : int) -> void:
	super(handler, data_index)

	lane_id = get_mania_handler().lane_id

	# A reused note arrives holding whatever the last one left behind - a
	# different direction, or still greyed out from a miss. Waking here is
	# what walks it back. Note this runs before _ready() for a note taken
	# from the pool, which is why the pump only stores the request.
	_last_was_hit = false
	_last_was_missed = false
	_pump.wake()

	var final_rotation : float = get_mania_handler().global_direction + local_direction
	position = Vector2(cos(final_rotation), sin(final_rotation)) * 5000.0
	
	reference_container.offset_left = 0.0
	reference_container.pivot_offset.x = -reference_container.offset_left
	
	var controller : RubiconLevelNoteController = get_mania_handler().get_controller()
	reference_container.offset_right = floor(controller.chart.scroll_multiplier * controller.scroll_speed_multiplier * (handler.data[data_index].get_graphical_end_position() - handler.data[data_index].get_graphical_start_position()))

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		# Before the early return: a note still has to settle into its
		# direction on the frames where the level itself is not running yet.
		var hit : bool = was_hit()
		var missed_now : bool = was_missed()
		if hit != _last_was_hit or missed_now != _last_was_missed:
			_last_was_hit = hit
			_last_was_missed = missed_now
			_pump.wake()

		_pump.pump(delta)

	if not _should_process():
		return

	var handler : RubiconLevelManiaNoteHandler = get_mania_handler()
	var controller : RubiconLevelNoteController = handler.get_controller()
	
	# global_direction is chart-animatable (see the Lane* AnimationPlayer
	# tracks in the song scenes), so it can't be computed only once in
	# initialize() - but it's static outside those animated sections, so
	# only touch .rotation (which dirties the Control's transform) when it
	# actually changed since last frame.
	var final_rotation : float = handler.global_direction + local_direction
	if final_rotation != _last_final_rotation:
		_last_final_rotation = final_rotation
		reference_container.rotation = final_rotation
		reference_graphic.rotation = -final_rotation
	
	var current_time : float = controller.get_level_clock().time_milliseconds + controller.offset_note_position
	var current_start_position : float = controller.chart.scroll_multiplier * controller.scroll_speed_multiplier * handler.data[data_index].get_graphical_start_position_relative(current_time)
	
	# Positioning
	var rotation_vector : Vector2 = Vector2(cos(final_rotation), sin(final_rotation))
	position = (rotation_vector * current_start_position) + (rotation_vector * offset_position)
	
	if handler.data[data_index].ending_row != null:
		if was_hit() and not was_missed():
			reference_container.offset_left = floor(reference_container.offset_right - (controller.chart.scroll_multiplier * controller.scroll_speed_multiplier * handler.data[data_index].get_graphical_end_position_relative(current_time)))
			reference_container.pivot_offset.x = -reference_container.offset_left
		elif not was_hit():
			reference_container.offset_left = 0.0
			reference_container.pivot_offset.x = -reference_container.offset_left
	# Trail
	#var trail_size : Vector2 = reference_container.size
	#trail_size.x = handler.data[data_index].get_graphical_end_position_relative(current_time) - current_start_position
	#reference_container.size = trail_size
	#
	#var trail_position : Vector2 = reference_container.position
	#trail_position.x = reference_trail.size.x - trail_size.x
	#reference_container.position = trail_position
