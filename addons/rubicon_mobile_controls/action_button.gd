extends Button
class_name RubiconActionButton

## Translucent round tap target that dispatches a press+release pair for
## [member action], one frame apart, exactly like a real key tap. Used for
## the menu overlay's Accept/Cancel buttons: some scripts read the raw
## InputEvent (event.is_action_pressed), others poll
## Input.is_action_just_released next frame, so both need to fire for this
## to behave like an actual key press in every listener.

@export var action: StringName = &"ui_accept"

var _flash_tween: Tween

## Optional: only show this button while this bool property is true (e.g.
## a contextual shortcut like "F / Switch Cartridge" that only means
## anything while the cartridge icon is actually focused). Leave
## visible_source unset to always show, which is the common case.
@export var visible_source: Node
@export var visible_property: StringName = &""

## Optional second required condition (AND'd with the first) - needed
## because a Control's own "focused" var can already be true well before
## its menu is actually open (e.g. ConsoleTab.default_focus grabs the
## Cartridges icon's focus as soon as the console scene loads, long
## before the player has looked at the console at all).
@export var visible_source2: Node
@export var visible_property2: StringName = &""

func _ready() -> void:
	# A Button grabs GUI focus on touch by default. Once this button holds
	# focus, RubiconVirtualDPad's ui_up/ui_down/ui_left/ui_right presses get
	# consumed by Godot's own focus-navigation (moving focus between
	# Controls) instead of reaching whatever the dpad is actually supposed
	# to drive - and a focused OK button re-absorbs the ui_accept event
	# _dispatch() synthesizes below into its own default "activate on
	# ui_accept" handling instead of it reaching the real target, making OK
	# look like it does nothing. on_screen_keyboard.gd's buttons already
	# have this same fix; this button just never got it.
	focus_mode = Control.FOCUS_NONE

	pressed.connect(_dispatch)
	button_down.connect(_flash)

## visible_source/visible_source2 are wired via a node_paths override from
## an ancestor scene (e.g. env_collector_shop.tscn pointing this button at
## Console/Cartridges nodes that live outside TouchControls' own sub-scene
## entirely). Checking for a configured visible_source every frame, rather
## than once in _ready() to decide whether to set_process(false)
## permanently, avoids depending on that cross-scene override always being
## resolved by the time this node's own _ready() runs.
func _process(_delta: float) -> void:
	if visible_source == null or visible_property.is_empty():
		return
	visible = _compute_visible()

func _compute_visible() -> bool:
	var v: bool = bool(visible_source.get(visible_property))
	if v and visible_source2 != null and not visible_property2.is_empty():
		v = bool(visible_source2.get(visible_property2))
	return v

func _dispatch() -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)

	await get_tree().process_frame

	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)

## Quick bright pulse on touch-down, on top of the pressed/normal
## StyleBoxFlat swap - a flash reads as "the touch registered" far more
## immediately than a style change alone.
##
## A fast repeated tap (double-tap, or a drag that re-enters the button)
## fires button_down more than once before the previous flash finishes.
## Without killing that previous tween, two tweens end up racing to write
## `modulate` on the same frame - whichever last happens to run that frame
## "wins", so the button can visibly get stuck on the bright flash color
## instead of ever settling back to white.
func _flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	modulate = Color(1.7, 1.7, 1.7, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
