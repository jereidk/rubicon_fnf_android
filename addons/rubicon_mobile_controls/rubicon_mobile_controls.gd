@tool
extends Control
class_name RubiconMobileControls

signal lane_pressed(lane_id: int)
signal lane_released(lane_id: int)

@export var lane_count: int = 4
@export var button_size: Vector2 = Vector2(100, 100)
@export var spacing: float = 20.0
@export var opacity: float = 0.7

var buttons: Array = []
var lane_ids: Array = []
var pressed_lanes: Dictionary = {}

# Mapeo de lanes a teclas (estándar FNF)
var lane_to_keycode: Dictionary = {
	0: KEY_D,
	1: KEY_F,
	2: KEY_J,
	3: KEY_K
}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	_setup_buttons()
	_update_layout()
	_setup_mobile_input_actions()

func _setup_mobile_input_actions() -> void:
	for i in range(4):
		var action_name = "mobile_lane_%d" % i
		if not InputMap.has_action(action_name):
			InputMap.create_action(action_name)
			var key_event = InputEventKey.new()
			key_event.keycode = lane_to_keycode[i]
			InputMap.action_add_event(action_name, key_event)

func _setup_buttons() -> void:
	for btn in buttons:
		btn.queue_free()
	buttons.clear()
	lane_ids.clear()
	
	for i in range(lane_count):
		var btn = TouchScreenButton.new()
		btn.name = "LaneButton%d" % i
		btn.visible = true
		btn.modulate.a = opacity
		
		var normal = _create_circle_texture(Color(1, 1, 1, 0.5))
		var pressed = _create_circle_texture(Color(1, 1, 1, 0.8))
		
		btn.texture_normal = normal
		btn.texture_pressed = pressed
		
		add_child(btn)
		buttons.append(btn)
		lane_ids.append(i)

func _create_circle_texture(color: Color) -> ImageTexture:
	var size = int(button_size.x)
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	
	var center = Vector2(size, size) / 2
	var radius = size / 2
	for x in range(size):
		for y in range(size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			if dist > radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.create_from_image(image)
	return texture

func _update_layout() -> void:
	if buttons.is_empty():
		return
	
	var total_width = (button_size.x + spacing) * lane_count - spacing
	var start_x = (size.x - total_width) / 2
	var btn_y = size.y - button_size.y - 50
	
	for i in range(buttons.size()):
		var btn = buttons[i]
		if btn:
			btn.position = Vector2(start_x + i * (button_size.x + spacing), btn_y)
			btn.size = button_size

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventMouseButton:
		_handle_mouse(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var lane = _get_lane_for_position(event.position)
		if lane >= 0 and not pressed_lanes.has(lane):
			pressed_lanes[lane] = true
			_send_input_event(lane, true)
			lane_pressed.emit(lane)
	else:
		for lane in pressed_lanes.keys():
			_send_input_event(lane, false)
			lane_released.emit(lane)
		pressed_lanes.clear()

func _handle_mouse(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var lane = _get_lane_for_position(event.position)
			if lane >= 0 and not pressed_lanes.has(lane):
				pressed_lanes[lane] = true
				_send_input_event(lane, true)
				lane_pressed.emit(lane)
		else:
			for lane in pressed_lanes.keys():
				_send_input_event(lane, false)
				lane_released.emit(lane)
			pressed_lanes.clear()

func _send_input_event(lane: int, pressed: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = lane_to_keycode.get(lane, KEY_SPACE)
	event.pressed = pressed
	Input.parse_input_event(event)

func _get_lane_for_position(pos: Vector2) -> int:
	var total_width = (button_size.x + spacing) * lane_count - spacing
	var start_x = (size.x - total_width) / 2
	
	if pos.x < start_x or pos.x > start_x + total_width:
		return -1
	
	var rel_x = pos.x - start_x
	var lane = int(rel_x / (button_size.x + spacing))
	
	if lane >= lane_count:
		return -1
	
	var local_x = int(rel_x) % int(button_size.x + spacing)
	if local_x > button_size.x:
		return -1
	
	return lane

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()
