class_name LullabyHideIfLocked extends Node

## Hides the parent settings row unless the given SaveData flag is set -
## e.g. Showcase Mode, unlocked by entering the "SHOWCASE" code in the
## console's Codes tab (see hacks_tab.gd).
##
## Unlike LullabyHideIfRelease this cannot be a one-shot check at _ready,
## because the thing that unlocks it is on the screen next door. It used to
## be one, and the effect was that entering the code did nothing visible: the
## row only appeared after loading a song and coming back, by which point the
## console had been rebuilt and _ready had run again. Now it also listens, so
## the row appears the moment the code is accepted.

@export var unlock_flag: StringName

func _ready() -> void:
	_apply()
	SaveData.flag_changed.connect(_on_flag_changed)

func _on_flag_changed(flag: StringName, _value: bool) -> void:
	if flag == unlock_flag:
		_apply()

func _apply() -> void:
	var parent: Node = get_parent()
	if parent != null and "visible" in parent:
		parent.visible = SaveData.get_flag(unlock_flag)
