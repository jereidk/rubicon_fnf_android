class_name SubmenuArea extends FocusArea3D

@export var submenu_viewport: SubViewport
@export var open_sound: AudioStreamPlayer

func trigger() -> void :
	if not can_interact:
		return

	sequences.animation_player.play(animation_name)

	if open_sound:
		open_sound.play()

## Rubicon addition: the console's SubViewport is rendered onto a 3D
## screen mesh, not embedded via a SubViewportContainer, so it never gets
## real window input automatically - this forward is the only thing that
## reaches it. The original mod only needed to forward InputEventKey
## (real keyboards), but RubiconVirtualDPad/RubiconActionButton dispatch
## synthetic InputEventAction instead, so that type needs forwarding too
## or the whole console goes unreachable by touch.
func _input(event: InputEvent) -> void :
	if submenu_viewport != null and is_focused and (event is InputEventKey or event is InputEventAction):
		submenu_viewport.push_input(event)
