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
##
## Used as the BASE only. Its text settings are overridden below, and that is
## not a preference - the pause themes are what made these buttons invisible.
## Both of them say, for the two types that matter here:
##
##     Button/styles/normal = StyleBoxEmpty      (no box at all)
##     Button/colors/font_color = Color(0,0,0,1) (black)
##     Label/colors/font_color  = Color(0,0,0,1) (black)
##     Button/font_sizes/font_size = 8
##     Label/font_sizes/font_size  = 8
##
## Which is correct where they were designed to live: inside the pause menu's
## Panel, which is a light Pokemon dialog box (`thm_panel_kanto.webp`). Black
## on white. A death screen has no panel, so the same theme draws black 8px
## text on an unlit background - present, hit-testable, and invisible. The
## styleboxes for focus/hover/pressed still come from here, so the song's
## flavour survives on the states where there IS a box to see.
@export var button_theme: Theme

## Text style for the buttons, taken from the Collector's Shop rather than
## invented: white, large, with a heavy black outline.
##
## The shop's own buttons and dialogue are authored exactly this way -
## `fnt_hypnosis.ttf`, `font_outline_color = Color(0,0,0,1)` and
## `outline_size = 12` on `UI/Control/Dialogue/Text`, and a black shadow with
## an outline on `BriefcaseHUD/BuyButton`. An outline is what makes text
## legible over arbitrary art without putting a box behind it, which is the
## whole problem a death screen poses.
@export var prompt_font: Font = preload("res://lullaby_mod/resources/fonts/fnt_hypnosis.ttf")
@export var prompt_font_size: int = 72
@export var prompt_outline_size: int = 12

## Tap target. Sized for a thumb first and the text second: 8px text in a
## 260x76 box was the old pairing, and neither half of it was readable.
@export var button_size: Vector2 = Vector2(420, 116)

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

func _ready() -> void :
	layer = canvas_layer

	_build()
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
		# The verb alone here. Everywhere else a button shows its key, but
		# those all sit under the mod's own key legend; a death screen has no
		# legend to be consistent with, and RETRY / EXIT is what the player
		# needs to read at a glance. show_binding stays off (its default).
		button.verb = prompts[action]
		button.custom_minimum_size = button_size
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.theme = _readable_theme()
		column.add_child(button)
		_buttons[action] = button


## The song's theme with the text settings that hid these buttons replaced.
##
## It has to be a Theme and not add_theme_*_override() calls on the Button,
## and that is the part worth writing down. RubiconActionButton does not draw
## `verb` as the Button's own text - with a non-empty verb it CLEARS `text`
## and builds a child Label to hold it (`_build_label`, action_button.gd).
## Overrides set on the Button apply to the Button; that Label is a separate
## node and resolves `Label/colors/font_color` and `Label/font_sizes/font_size`
## from the nearest ancestor theme, which is the Button's. So the black 8px
## text the player could not see was being read from `Label/...`, and an
## override on the Button would have missed it entirely and looked like the
## fix had simply not worked.
##
## A Theme reaches it because theme resolution walks ancestors: setting this
## on the Button covers every node it builds underneath, now and later.
##
## merge_with() keeps everything the song authored - the selector styleboxes
## for focus, hover and pressed - and only the entries set afterwards win.
func _readable_theme() -> Theme:
	var theme := Theme.new()
	if button_theme != null:
		theme.merge_with(button_theme)

	for type: StringName in [&"Button", &"Label"]:
		if prompt_font != null:
			theme.set_font(&"font", type, prompt_font)
		theme.set_font_size(&"font_size", type, prompt_font_size)
		theme.set_color(&"font_color", type, Color.WHITE)
		theme.set_color(&"font_outline_color", type, Color.BLACK)
		theme.set_constant(&"outline_size", type, prompt_outline_size)

	# Button carries a colour per state, and leaving these black would bring
	# the invisibility back the moment a finger touched one.
	for entry: StringName in [
		&"font_focus_color", &"font_hover_color",
		&"font_pressed_color", &"font_hover_pressed_color",
	]:
		theme.set_color(entry, &"Button", Color.WHITE)

	return theme

func _process(_delta: float) -> void :
	visible = _is_available()

func _is_available() -> bool:
	if available_source == null or available_property.is_empty():
		return true
	if not is_instance_valid(available_source):
		return false
	return bool(available_source.get(available_property))
