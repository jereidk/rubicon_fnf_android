extends Node
## Instancia el MobileControls solo cuando la escena actual es gameplay.
##
## El MobileControls como autoload global corria en TODAS las escenas.
## En modo Hitbox crea cuatro columnas invisibles que cubren la pantalla
## entera y capturan InputEventScreenTouch - funcione o no la escena de
## arriba. En el ModSelector eso hacia que un toque sobre un boton no
## llegara nunca al Button, y el mod parecia no cargar.
##
## Este gate reemplaza al autoload: espera a que current_scene cambie,
## mira si la escena es gameplay (tiene un nodo con el script del nivel
## de Washos), y solo entonces instancia el MobileControls y le deja el
## input. En cualquier otra escena no existe la instancia, asi que no hay
## input que capturar ni columnas invisibles.

const MOBILE_CONTROLS_SCENE := preload("res://addons/rubicon_mobile_controls/mobile_controls.tscn")
const LEVEL_SCRIPT_NAME := "rubicon_level.gd"

var _instance: CanvasLayer = null
var _last_scene: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Un chequeo inicial en el primer frame, por si current_scene ya esta
	# puesta antes de que este nodo arranque.
	_refresh()

func _process(_delta: float) -> void:
	# Polling de una comparacion de referencia por frame. Es lo mas
	# barato y lo mas fiable: no hay signal nativo de "current_scene
	# cambio", y tree_changed dispara cientos de veces durante una
	# carga sin decirnos nada util.
	var current := get_tree().current_scene
	if current != _last_scene:
		_last_scene = current
		_refresh()

func _refresh() -> void:
	var wants_controls := _is_gameplay_scene(get_tree().current_scene)
	if wants_controls:
		_ensure_instance()
		if _instance != null and is_instance_valid(_instance):
			_instance.visible = true
			_instance.set_process_input(true)
			_instance.set_process_unhandled_input(true)
	else:
		if _instance != null and is_instance_valid(_instance):
			_instance.visible = false
			_instance.set_process_input(false)
			_instance.set_process_unhandled_input(false)

func _ensure_instance() -> void:
	if _instance != null and is_instance_valid(_instance):
		return
	_instance = MOBILE_CONTROLS_SCENE.instantiate()
	add_child(_instance)

## Un nodo gameplay en esta base tiene el script del nivel de Washos.
## Buscamos por nombre de archivo y no por clase porque la clase puede
## estar o no registrada segun como se cargo el addon.
func _is_gameplay_scene(node: Node) -> bool:
	if node == null:
		return false
	var scr = node.get_script()
	if scr != null and scr is GDScript:
		var path: String = scr.resource_path
		if path.ends_with(LEVEL_SCRIPT_NAME):
			return true
	for child in node.get_children():
		if _is_gameplay_scene(child):
			return true
	return false
