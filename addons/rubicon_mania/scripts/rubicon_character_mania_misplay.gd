@tool
class_name RubiconCharacterManiaMisplay extends Node

## Makes a character react to a misplay (a press with no note in range while
## the handler's allow_misplays is off) by playing that lane's miss
## animation. Drop it as a child of a RubiconCharacter; it finds the parent
## itself and needs no wiring.
##
## Restored from the mod's own Rubicon, which our fork had dropped along
## with the whole misplay subsystem - see rubicon_level_mania_note_handler's
## `misplayed` signal.

var _chara: RubiconCharacter

func _on_misplay(lane_id: int) -> void:
	var mode_aliases: Dictionary = _chara.get(&"mania_anim_aliases")
	var alias: StringName = StringName("mania_lane%s_miss" % lane_id)
	if not mode_aliases.has(alias):
		return

	var anim_key: StringName = mode_aliases[alias]
	if not _chara.animations.has(anim_key):
		return

	_chara._last_sing_anim = _chara.animations[anim_key]
	_chara.play(_chara._last_sing_anim)
	_chara.state = RubiconCharacter.CharacterState.STATE_SINGING

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PARENTED:
			_on_note_controller_connected(false)
			if _chara and _chara.note_controller_connected.is_connected(_on_note_controller_connected):
				_chara.note_controller_connected.disconnect(_on_note_controller_connected)

			_chara = null

			var parent: Node = get_parent()
			if parent is not RubiconCharacter:
				return

			_chara = parent
			_chara.note_controller_connected.connect(_on_note_controller_connected)
			_on_note_controller_connected(_chara.level_note_controller != null)

func _on_note_controller_connected(connected: bool) -> void:
	if _chara == null or _chara.level_note_controller == null:
		return

	for handler_id in _chara.level_note_controller.note_handlers:
		var handler: RubiconLevelNoteHandler = _chara.level_note_controller.note_handlers[handler_id]
		if handler is not RubiconLevelManiaNoteHandler:
			continue

		var signal_connected: bool = handler.misplayed.is_connected(_on_misplay)
		if connected and not signal_connected:
			handler.misplayed.connect(_on_misplay)
		elif not connected and signal_connected:
			handler.misplayed.disconnect(_on_misplay)
