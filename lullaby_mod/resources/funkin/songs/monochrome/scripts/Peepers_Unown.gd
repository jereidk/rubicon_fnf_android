@tool
extends ColorRect

@export var glow_node: Node

@export_group("Movement")
@export var wobble_enabled: bool = true

@export_range(0.0, 500.0, 1.0)
var wobble_amount: float = 18.0

@export_range(0.0, 20.0, 0.01)
var wobble_speed: float = 0.35

@export_range(0.0, 360.0, 1.0)
var wobble_direction_degrees: float = 0.0

@export_range(0.0, 1.0, 0.01)
var wobble_side_amount: float = 0.35

@export_range(0.0, 5.0, 0.01)
var wobble_intensity: float = 1.0

@export var y_speed_multiplier: float = 0.85

var _time: float = 0.0
var _base_position: Vector2 = Vector2.ZERO
var _has_base_position: bool = false

## The wobble axis, derived from wobble_direction_degrees. It was recomputed
## in _process - a deg_to_rad, a cos, a sin and an orthogonal() - for a value
## that only changes if someone edits the export. With 128 eyes that was 256
## trig calls a frame for a constant. Recomputed when the source changes, so
## dragging the slider in the editor still works.
var _direction: Vector2 = Vector2.RIGHT
var _side_direction: Vector2 = Vector2.DOWN
var _direction_degrees: float = NAN


func _ready() -> void :
	_base_position = position
	_has_base_position = true


func _process(_delta: float) -> void :
	if not _has_base_position:
		_base_position = position
		_has_base_position = true

	if not wobble_enabled:
		return

	# A wobble of zero amplitude puts the node exactly on _base_position, and
	# it is already there from the frame the intensity reached zero. Peepers
	# holds every eye at intensity 0 whenever movement is off, so without
	# this all 128 kept computing a sine and writing back a position they
	# already had. Node2D.set_position() has no early-out either.
	if is_zero_approx(wobble_amount * wobble_intensity):
		if position != _base_position:
			position = _base_position
		return

	if not is_equal_approx(_direction_degrees, wobble_direction_degrees):
		_direction_degrees = wobble_direction_degrees
		var rot: float = deg_to_rad(wobble_direction_degrees)
		_direction = Vector2(cos(rot), sin(rot))
		_side_direction = _direction.orthogonal()

	var scaled_time: = _time * wobble_speed
	position = _base_position + (
		_direction * sin(scaled_time)
		+ (_side_direction * cos(scaled_time * y_speed_multiplier) * wobble_side_amount)
	) * wobble_amount * wobble_intensity


func set_wobble_intensity(value: float) -> void :
	wobble_intensity = value
