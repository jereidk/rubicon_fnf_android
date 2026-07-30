@tool
extends CanvasLayer
class_name RubiconMobileControls

signal lane_pressed(lane_id: int)
signal lane_released(lane_id: int)

@export var lane_count: int = 4
@export_enum("Buttons", "Hitbox") var control_mode: String = "Hitbox"
@export var button_size: Vector2 = Vector2(100, 100)
@export var spacing: float = 20.0
@export var opacity: float = 0.7

var buttons: Array = []
var hitboxes: Array[ColorRect] = []
var lane_ids: Array = []

# Mapeo de lanes a teclas (estándar FNF)
var lane_to_keycode: Dictionary = {
	0: KEY_D,
	1: KEY_F,
	2: KEY_J,
	3: KEY_K
}

var lane_colors: Dictionary = {
	0: Color(0.76, 0.29, 0.60, 0.15),  # Left - Purple/Magenta
	1: Color(0.00, 1.00, 1.00, 0.15),  # Down - Cyan
	2: Color(0.07, 0.98, 0.02, 0.15),  # Up - Green
	3: Color(0.98, 0.22, 0.25, 0.15)   # Right - Red
}

var main_control: Control

# Diccionario para rastrear qué carril (lane) está presionando cada dedo (index)
# index -> lane
var active_touches: Dictionary = {}

# Diccionario para rastrear el estado actual de cada carril
# lane -> boolean (pressed o no)
var lane_states: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	# Asegurar que tenemos un contenedor Control a pantalla completa para posicionamiento
	main_control = Control.new()
	main_control.name = "MainControl"
	main_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_control)

	main_control.resized.connect(_update_layout)

	_setup_buttons()
	_update_layout()
	_setup_mobile_input_actions()

func _setup_mobile_input_actions() -> void:
	for i in range(4):
		var action_name = "mobile_lane_%d" % i
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var key_event = InputEventKey.new()
			key_event.keycode = lane_to_keycode[i]
			InputMap.action_add_event(action_name, key_event)

func _setup_buttons() -> void:
	# Limpiar botones existentes
	for btn in buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	buttons.clear()

	# Limpiar hitboxes existentes
	for hb in hitboxes:
		if is_instance_valid(hb):
			hb.queue_free()
	hitboxes.clear()

	lane_ids.clear()
	active_touches.clear()
	lane_states.clear()
	
	if control_mode == "Buttons":
		_setup_buttons_mode()
	elif control_mode == "Hitbox":
		_setup_hitbox_mode()

func _setup_buttons_mode() -> void:
	for i in range(lane_count):
		var btn = TouchScreenButton.new()
		btn.name = "LaneButton%d" % i
		btn.visible = true
		btn.modulate.a = opacity
		
		var normal = _create_circle_texture(Color(1, 1, 1, 0.5))
		var pressed = _create_circle_texture(Color(1, 1, 1, 0.8))
		
		btn.texture_normal = normal
		btn.texture_pressed = pressed
		
		main_control.add_child(btn)
		buttons.append(btn)
		lane_ids.append(i)

func _setup_hitbox_mode() -> void:
	for i in range(lane_count):
		var hb = ColorRect.new()
		hb.name = "HitboxColumn%d" % i
		hb.color = lane_colors.get(i, Color(1, 1, 1, 0.15))
		hb.color.a = 0.0  # Invisible por defecto

		main_control.add_child(hb)
		hitboxes.append(hb)
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
	if not is_instance_valid(main_control):
		return
	
	var screen_size = main_control.size
	if screen_size == Vector2.ZERO:
		# Fallback por si la pantalla no está lista
		screen_size = get_viewport().get_visible_rect().size

	if control_mode == "Buttons":
		if buttons.is_empty():
			return

		var total_width = (button_size.x + spacing) * lane_count - spacing
		var start_x = (screen_size.x - total_width) / 2
		var btn_y = screen_size.y - button_size.y - 50

		for i in range(buttons.size()):
			var btn = buttons[i]
			if is_instance_valid(btn):
				btn.position = Vector2(start_x + i * (button_size.x + spacing), btn_y)
				btn.size = button_size
	elif control_mode == "Hitbox":
		if hitboxes.is_empty():
			return

		var column_width = screen_size.x / lane_count
		for i in range(hitboxes.size()):
			var hb = hitboxes[i]
			if is_instance_valid(hb):
				hb.position = Vector2(i * column_width, 0)
				hb.size = Vector2(column_width, screen_size.y)

func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	var index = event.index
	if event.pressed:
		var lane = _get_lane_for_position(event.position)
		if lane >= 0:
			if active_touches.has(index):
				_release_touch_index(index)

			active_touches[index] = lane
			_update_lane_press(lane)
	else:
		if active_touches.has(index):
			_release_touch_index(index)

func _handle_drag(event: InputEventScreenDrag) -> void:
	var index = event.index
	if active_touches.has(index):
		var old_lane = active_touches[index]
		var new_lane = _get_lane_for_position(event.position)
		if new_lane != old_lane:
			_release_touch_index(index)
			if new_lane >= 0:
				active_touches[index] = new_lane
				_update_lane_press(new_lane)

func _handle_mouse(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var lane = _get_lane_for_position(event.position)
			if lane >= 0:
				if active_touches.has(999):
					_release_touch_index(999)
				active_touches[999] = lane
				_update_lane_press(lane)
		else:
			if active_touches.has(999):
				_release_touch_index(999)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if active_touches.has(999):
		var old_lane = active_touches[999]
		var new_lane = _get_lane_for_position(event.position)
		if new_lane != old_lane:
			_release_touch_index(999)
			if new_lane >= 0:
				active_touches[999] = new_lane
				_update_lane_press(new_lane)

func _release_touch_index(index: int) -> void:
	if active_touches.has(index):
		var lane = active_touches[index]
		active_touches.erase(index)
		_update_lane_press(lane)

func _update_lane_press(lane: int) -> void:
	var is_pressed = false
	for touch_lane in active_touches.values():
		if touch_lane == lane:
			is_pressed = true
			break

	var was_pressed = lane_states.get(lane, false)
	if is_pressed != was_pressed:
		lane_states[lane] = is_pressed
		_send_input_event(lane, is_pressed)
		if is_pressed:
			lane_pressed.emit(lane)
			_on_lane_pressed_visual(lane)
		else:
			lane_released.emit(lane)
			_on_lane_released_visual(lane)

func _on_lane_pressed_visual(lane: int) -> void:
	if control_mode == "Buttons":
		if lane >= 0 and lane < buttons.size():
			var btn = buttons[lane]
			if is_instance_valid(btn):
				btn.modulate.a = 1.0
	elif control_mode == "Hitbox":
		if lane >= 0 and lane < hitboxes.size():
			var hb = hitboxes[lane]
			if is_instance_valid(hb):
				var base_color = lane_colors.get(lane, Color(1, 1, 1, 0.15))
				hb.color = base_color
				hb.color.a = opacity

func _on_lane_released_visual(lane: int) -> void:
	if control_mode == "Buttons":
		if lane >= 0 and lane < buttons.size():
			var btn = buttons[lane]
			if is_instance_valid(btn):
				btn.modulate.a = opacity
	elif control_mode == "Hitbox":
		if lane >= 0 and lane < hitboxes.size():
			var hb = hitboxes[lane]
			if is_instance_valid(hb):
				var tween = create_tween()
				var target_color = hb.color
				target_color.a = 0.0
				tween.tween_property(hb, "color", target_color, 0.1)

func _send_input_event(lane: int, pressed_state: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = lane_to_keycode.get(lane, KEY_SPACE)
	event.pressed = pressed_state
	Input.parse_input_event(event)

func _get_lane_for_position(pos: Vector2) -> int:
	if not is_instance_valid(main_control):
		return -1
	
	var screen_size = main_control.size
	if screen_size == Vector2.ZERO:
		screen_size = get_viewport().get_visible_rect().size
	
	if control_mode == "Buttons":
		for i in range(buttons.size()):
			var btn = buttons[i]
			if is_instance_valid(btn) and btn.visible:
				var rect = Rect2(btn.global_position, btn.size)
				if rect.has_point(pos):
					return i
		return -1
	elif control_mode == "Hitbox":
		var column_width = screen_size.x / lane_count
		var lane = int(pos.x / column_width)
		if lane >= 0 and lane < lane_count:
			return lane
		return -1
	return -1
