class_name LullabyGameoverPrompt extends CanvasLayer

## On-screen buttons for the actions a death screen accepts, each labelled
## with whatever is currently bound to it.
##
## Why this exists: both death screens took "a tap anywhere" and nothing
## said so. On a phone that is an invisible affordance - the player has no
## keyboard to press the Enter the screen is really waiting for, and no way
## to tell whether the game is waiting for input at all or has hung. It also
## made a real bug possible: a tap anywhere is delivered twice on Android
## (emulate_mouse_from_touch turns one finger into an InputEventScreenTouch
## AND an InputEventMouseButton), which is what left the loading screen
## stuck over Monochrome after a retry. A Button fires once, whatever the
## device.
##
## The buttons dispatch the same actions the keyboard path already uses,
## through RubiconActionButton, so this adds no second way for a death
## screen to be dismissed - it is the existing one, made visible.
##
## Adding an action is one entry in [member prompts]. Nothing here decides
## what an action DOES; the death screen's own _input() still handles it.

## Action name -> the verb shown on its button, in display order.
##
## ui_cancel is Android's hardware Back button as well as Esc, so EXIT is
## reachable the way a phone player would already expect to leave a screen.
@export var prompts: Dictionary[StringName, String] = {
	&"ui_accept": "RETRY",
	&"ui_cancel": "EXIT",
}

## The song's own pause-menu theme, so the prompt reads as part of that song
## rather than as a default Godot button - Monochrome is johto, Safety
## Lullaby is kanto.
@export var button_theme: Theme

## Only show the buttons while this bool property is true. Both death
## screens already gate their _input() on "is the animation done, and are we
## not already leaving"; pointing this at the same flag keeps a tappable
## button from appearing before the screen would accept it, or lingering
## once the retry is under way.
##
## Same source/property pattern as RubiconActionButton.visible_source, and
## for the same reason: it is wired from the .tscn, so the death screen
## needs no code that knows this node exists.
@export var available_source: Node
@export var available_property: StringName = &""

## Above the death art (plain Node2D scenes, so canvas layer 0) and below
## the loading screen, which owns layer 128.
@export var canvas_layer: int = 32

var _buttons: Dictionary[StringName, RubiconActionButton] = {}
var _bind_type: int = LullabyInputBinds.BindType.KBM

func _ready() -> void :
	layer = canvas_layer

	_build()
	_refresh_labels()

	if Settings.has_signal(&"applied"):
		Settings.applied.connect(_refresh_labels)

	visible = _is_available()

func _build() -> void :
	var column := VBoxContainer.new()
	column.name = "Prompts"
	column.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_bottom = -48.0
	column.add_theme_constant_override("separation", 12)
	# The column itself must never eat a touch - only its buttons should.
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	for action: StringName in prompts:
		var button: RubiconActionButton = RubiconActionButton.new()
		button.name = String(action)
		button.action = action
		button.custom_minimum_size = Vector2(260, 64)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if button_theme != null:
			button.theme = button_theme
		column.add_child(button)
		_buttons[action] = button

func _process(_delta: float) -> void :
	visible = _is_available()

## -1 is "this event says nothing about the device family" - a screen touch,
## or the synthetic InputEventAction the buttons themselves dispatch. Those
## must not flip a gamepad player's labels back to keyboard glyphs, and the
## synthetic one would otherwise re-render the labels on every tap.
func _input(event: InputEvent) -> void :
	var bind_type: int = LullabyInputBinds.type_of(event)
	if bind_type == -1 or bind_type == _bind_type:
		return

	_bind_type = bind_type
	_refresh_labels()

func _refresh_labels() -> void :
	for action: StringName in _buttons:
		var bind: String = LullabyInputBinds.text_for(action, _bind_type)
		# An action with nothing bound to it still needs a tappable button,
		# it just cannot advertise a key for it.
		if bind.is_empty():
			_buttons[action].text = prompts[action]
		else:
			_buttons[action].text = "%s   %s" % [prompts[action], bind]

func _is_available() -> bool:
	if available_source == null or available_property.is_empty():
		return true
	if not is_instance_valid(available_source):
		return false
	return bool(available_source.get(available_property))
