class_name LullabyHideIfLocked extends Node

## Hides the parent settings row unless the given SaveData flag is set -
## e.g. Showcase Mode, unlocked by entering the "SHOWCASE" code in the
## console's Codes tab (see hacks_tab.gd). Same one-shot-at-ready check as
## LullabyHideIfRelease.

@export var unlock_flag: StringName

func _ready() -> void:
	get_parent().visible = SaveData.get_flag(unlock_flag)
