@tool
extends Node
class_name RubiconTouchInputHandler

## Maneja la conversión de eventos táctiles a inputs del juego
## Este script debe añadirse como autoload o como hijo del nivel

@export var enabled: bool = true

# Mapeo de lanes a teclas
# Por defecto: D=0, F=1, J=2, K=3 (estándar FNF)
var lane_to_keycode: Dictionary = {
	0: KEY_D,
	1: KEY_F,
	2: KEY_J,
	3: KEY_K
}

func _ready() -> void:
	# Configurar eventos de input para móvil
	_setup_mobile_input_actions()

func _setup_mobile_input_actions() -> void:
	# Crear acciones de input si no existen
	for i in range(4):
		var action_name = "mobile_lane_%d" % i
		if not InputMap.has_action(action_name):
			InputMap.create_action(action_name)
			
			# Añadir el keycode correspondiente
			var key_event = InputEventKey.new()
			key_event.keycode = lane_to_keycode[i]
			InputMap.action_add_event(action_name, key_event)

func handle_touch_input(lane: int, pressed: bool) -> void:
	if not enabled:
		return
	
	# Crear evento de teclado simulado
	var event = InputEventKey.new()
	event.keycode = lane_to_keycode.get(lane, KEY_SPACE)
	event.pressed = pressed
	
	# Enviar el evento al sistema de input
	Input.parse_input_event(event)

func _on_mobile_controls_lane_pressed(lane_id: int) -> void:
	handle_touch_input(lane_id, true)

func _on_mobile_controls_lane_released(lane_id: int) -> void:
	handle_touch_input(lane_id, false)
