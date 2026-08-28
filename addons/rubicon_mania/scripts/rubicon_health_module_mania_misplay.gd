@tool
class_name RubiconHealthModuleManiaMisplay extends Node

## Docks health on a misplay (a press with no note in range while the
## handler's allow_misplays is off). Drop it as a child of a
## RubiconHealthModule; it finds the parent itself and needs no wiring.
##
## Monochrome's scene in the original mod carries one of these as
## `HealthModule/RubiconHealthModuleManiaGhostTap`. Our extraction dropped
## the node because the class did not exist on this fork, which is why
## ghost tapping cost nothing in the port.

@export var health_change: int = -4

var _health_module: RubiconHealthModule

func _on_misplay(_lane_id: int) -> void:
	_health_module.health += health_change

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PARENTED:
			_on_note_controller_connected(false)
			if _health_module and _health_module.note_controller_connected.is_connected(_on_note_controller_connected):
				_health_module.note_controller_connected.disconnect(_on_note_controller_connected)

			_health_module = null

			var parent: Node = get_parent()
			if parent is not RubiconHealthModule:
				return

			_health_module = parent
			_health_module.note_controller_connected.connect(_on_note_controller_connected)
			_on_note_controller_connected(_health_module.note_controller != null)

func _on_note_controller_connected(connected: bool) -> void:
	if _health_module == null or _health_module.note_controller == null:
		return

	for handler_id in _health_module.note_controller.note_handlers:
		var handler: RubiconLevelNoteHandler = _health_module.note_controller.note_handlers[handler_id]
		if handler is not RubiconLevelManiaNoteHandler:
			continue

		var signal_connected: bool = handler.misplayed.is_connected(_on_misplay)
		if connected and not signal_connected:
			handler.misplayed.connect(_on_misplay)
		elif not connected and signal_connected:
			handler.misplayed.disconnect(_on_misplay)
