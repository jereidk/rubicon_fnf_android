extends Button
class_name RubiconActionButton

## Translucent round tap target that dispatches a press+release pair for
## [member action], one frame apart, exactly like a real key tap. Used for
## the menu overlay's Accept/Cancel buttons: some scripts read the raw
## InputEvent (event.is_action_pressed), others poll
## Input.is_action_just_released next frame, so both need to fire for this
## to behave like an actual key press in every listener.

@export var action: StringName = &"ui_accept"

## Optional line above the key, for what the button DOES.
##
## The rule across the game is: a button shows its key, and shows a verb as
## well only where nothing else on screen already says what that key does.
## The console's buttons take the key alone, because the mod's own legend
## sits right under them ("[Enter] Accept / [Escape] Back") and saying it
## twice in two different vocabularies is exactly the inconsistency this
## replaced - Accept said "OK" and Cancel said "Back" while the cartridge
## button said "F". The death screen's prompt has no such legend, so its
## buttons carry both.
##
## Leave it empty and the authored [member text] is left exactly as it is,
## so nothing that has not opted in changes.
@export var verb: String = "":
	set(value):
		verb = value
		if is_node_ready():
			_refresh_label()

## Add the generated key line. Off by default so no button that has not
## opted in changes what it displays.
##
## Usable on its own, with an empty [member verb], for a button that already
## says what it does some other way - LullabyMechanicActionButton draws a
## pendulum glyph and would only be hidden by a word on top of it, but still
## benefits from saying which key does the same thing.
@export var show_binding: bool = false:
	set(value):
		show_binding = value
		if is_node_ready():
			_refresh_label()

## Point size of the generated key line. The verb keeps the button's own
## theme font size.
@export var binding_font_size: int = 18

## Optional: bypass the action/raycast system entirely and call this area's
## trigger() straight away instead. For a contextual button that always
## means one specific, unambiguous thing while visible (e.g. "Power" for
## the TV's power console) - no aiming involved, unlike [member action]
## dispatching "RightClick" for MouseController's raycast to pick up
## whatever it happens to be pointed at.
@export var direct_target: TriggerArea3D

var _flash_tween: Tween

var _label_column: VBoxContainer
var _verb_label: Label
var _binding_label: Label
## Whatever the scene authored as the Button's own text, kept so a button
## that ends up with nothing else to show can fall back to it.
var _authored_text: String = ""
## 0 = keyboard/mouse, 1 = gamepad. Starts on keyboard because that is what
## the InputMap's first binding is for every action here.
var _last_device_family: int = 0

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

	_build_label()
	_refresh_label()

	# Soft dependency, by node name rather than by class: this addon is kept
	# free of the mod's autoloads (everything else in it reads only
	# ProjectSettings), and it has to keep loading in a project that has no
	# Settings at all. When there is one, rebinding a key in the console
	# updates these labels straight away.
	#
	# The InputMap is what gets read either way, not Settings.input_game -
	# settings.gd applies every rebind into the InputMap
	# (action_erase_events/action_add_event), so the engine's own map is the
	# live truth and input_game is just its persisted copy.
	var settings: Node = get_node_or_null(^"/root/Settings")
	if settings != null and settings.has_signal(&"applied"):
		settings.applied.connect(_refresh_label)

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

## Two stacked Labels rather than one with a newline: Button renders its own
## text through a single-line TextLine, and the two halves want different
## font sizes anyway. The container is IGNORE all the way down so the Button
## underneath still receives every touch.
func _build_label() -> void:
	if (verb.is_empty() and not show_binding) or _verb_label != null:
		return

	# The generated label replaces the Button's own text rather than sitting
	# next to it, so the two cannot draw on top of each other. Kept rather
	# than thrown away, because it is also the fallback - see _refresh_label.
	_authored_text = text
	text = ""

	var column := VBoxContainer.new()
	column.name = "GeneratedLabel"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	_verb_label = Label.new()
	_verb_label.name = "Verb"
	_verb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verb_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# These buttons are fixed-size tap targets, so a long verb has to clip
	# rather than push the button's own layout around.
	_verb_label.clip_text = true
	column.add_child(_verb_label)

	_binding_label = Label.new()
	_binding_label.name = "Binding"
	_binding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_binding_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_binding_label.clip_text = true
	_binding_label.add_theme_font_size_override("font_size", binding_font_size)
	# Dimmed only when it is the second line - with no verb the key IS the
	# label and has to read as strongly as any other button's text.
	if not verb.is_empty():
		_binding_label.modulate = Color(1.0, 1.0, 1.0, 0.7)
	column.add_child(_binding_label)

	_label_column = column

func _refresh_label() -> void:
	if _verb_label == null:
		return

	_verb_label.text = verb
	_verb_label.visible = not verb.is_empty()

	var binding: String = _binding_text() if show_binding else ""
	_binding_label.text = binding
	# An action with nothing bound to it still needs its verb; it just has no
	# key to advertise, and an empty line would push the verb off centre.
	_binding_label.visible = not binding.is_empty()

	# A button with no verb and no resolvable binding would otherwise render
	# nothing at all, and these buttons are a 7%-white rectangle - with no
	# label there is no button, which is exactly how the results screen's way
	# out and the death screens' prompts went missing on the device. A key
	# name was never a sensible label on a phone in the first place; the text
	# the scene authored is.
	if not _verb_label.visible and not _binding_label.visible:
		# Last resort, so the invariant holds no matter how the button was
		# authored: the action's own name, spelled out. It reads badly on
		# purpose - it means someone shipped a button with no verb, no text
		# and an action nothing is bound to, and a visibly wrong label is
		# how that gets noticed instead of shipping as a dead rectangle.
		text = _authored_text if not _authored_text.is_empty() else String(action).capitalize()
	else:
		text = ""

## Preferred binding for [member action], following whichever kind of device
## was last used, and falling back to the first binding of any kind rather
## than to nothing.
func _binding_text() -> String:
	if not InputMap.has_action(action):
		return ""

	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return ""

	var chosen: InputEvent = events[0]
	for event: InputEvent in events:
		if _device_family(event) == _last_device_family:
			chosen = event
			break

	# as_text() spells a key out as e.g. "Enter (Physical)", which is noise
	# on a button this size.
	return chosen.as_text().replace(" (Physical)", "").replace(" - Physical", "")

## -1 for events that say nothing about the device in use - a screen touch,
## or the synthetic InputEventAction this button itself dispatches. Those
## must not flip a gamepad player's labels back to keyboard glyphs.
func _device_family(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return 0
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return 1
	return -1

func _input(event: InputEvent) -> void:
	if _verb_label == null:
		return

	var family: int = _device_family(event)
	if family == -1 or family == _last_device_family:
		return

	_last_device_family = family
	_refresh_label()

func _dispatch() -> void:
	if direct_target != null:
		direct_target.area_triggered.emit()
		direct_target.trigger()
		return

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
