extends Control
class_name MonochromeTypingTouchControls

## Android touch support for Monochrome's TypingChallenge mechanic
## (Stage/TypingChallenge). Desktop players type on a physical keyboard;
## TypingChallenge._input() reads raw InputEventKey letter by letter.
##
## This used to draw its own on-screen keyboard (RubiconOnScreenKeyboard).
## It now focuses a real LineEdit instead, which is what makes Android open
## the system keyboard - the same thing the Collector Shop's Codes tab does
## (hacks_tab.gd's code_input), and the reason that screen already felt
## native while this one did not. The player gets their own autocorrect,
## layout, language and swipe input rather than a hand-drawn approximation.
##
## The LineEdit is deliberately transparent and non-interactive: it exists to
## hold focus and receive characters, never to be seen or tapped. Typed text
## is drained into TypingChallenge.input_letter() and the field is cleared
## again immediately, so it never accumulates state of its own and the
## mechanic stays the single source of truth for what has been typed.
##
## Focus is what drives the keyboard, so it is also what closes it: releasing
## focus when the challenge stops prompting dismisses the system keyboard
## without having to call any platform API.

@export var typing_challenge: TypingChallenge
@export var text_input: LineEdit

## Nodes that must not end up behind the system keyboard - the unowns and
## their letters, which sit low enough on screen to be covered by it. The
## keyboard's height is only known at runtime (it varies by device, language
## and whether a suggestion strip is showing), so this can't be baked into
## the scene as a fixed offset and has to be applied live.
@export var raise_targets: Array[Node2D] = []

## Extra clearance above the keyboard, in the same units as the targets'
## positions. Their position is used as a stand-in for where their artwork
## actually ends, so this absorbs that difference.
@export var raise_margin: float = 120.0

var _base_positions: PackedVector2Array
var _draining: bool = false

func _ready() -> void:
	var settings_enabled: bool = ProjectSettings.get_setting("rubicon_mobile_controls/enabled", true)
	var has_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	if not settings_enabled or not has_touch:
		visible = false
		set_process(false)
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for t in raise_targets:
		_base_positions.append(t.position if t else Vector2.ZERO)

	if text_input:
		text_input.text_changed.connect(_on_text_changed)
		_set_input_available(false)

func _process(_delta: float) -> void:
	if not text_input or not typing_challenge:
		return

	var wants_input: bool = (
		typing_challenge.active
		and typing_challenge.prompt_user
		and not typing_challenge.autoplay
		and not typing_challenge.challenge_over
	)

	if wants_input:
		_set_input_available(true)
		if not text_input.has_focus():
			text_input.grab_focus()
	else:
		_set_input_available(false)

	_apply_raise(wants_input)

## Releasing focus is not enough on its own. The challenge's flags are reused
## between rounds (start_challenge() clears challenge_over while active and
## prompt_user are still set from the round before), so wants_input can blip
## back on for a frame after the unowns are gone - and a single frame of focus
## is a whole system keyboard back on screen, sitting over the note lanes.
##
## So when input isn't wanted the field is made genuinely unreachable rather
## than merely unfocused: focus_mode NONE means nothing can hand it focus,
## and hidden means Godot won't either. virtual_keyboard_hide() is belt and
## braces for the case where the keyboard is already up when that happens -
## Godot only lowers it as a side effect of a focus change it can see.
func _set_input_available(available: bool) -> void:
	if available:
		if not text_input.visible:
			text_input.focus_mode = Control.FOCUS_ALL
			text_input.visible = true
		return

	if not text_input.visible and text_input.focus_mode == Control.FOCUS_NONE:
		return

	if text_input.has_focus():
		text_input.release_focus()
	text_input.focus_mode = Control.FOCUS_NONE
	text_input.visible = false
	text_input.text = ""
	DisplayServer.virtual_keyboard_hide()

## Lifts each target by exactly how much the keyboard overlaps it, and no
## more, so nothing moves on a device whose keyboard is short enough to leave
## it clear anyway.
func _apply_raise(wants_input: bool) -> void:
	var overlap_source: float = 0.0
	if wants_input:
		# virtual_keyboard_get_height() is in real screen pixels while the
		# targets live in the viewport's base resolution, so it has to be
		# scaled by the stretch ratio before it means anything to them.
		var window_height: float = float(DisplayServer.window_get_size().y)
		var viewport_height: float = get_viewport_rect().size.y
		var to_viewport: float = viewport_height / window_height if window_height > 0.0 else 1.0
		var keyboard_height: float = float(DisplayServer.virtual_keyboard_get_height()) * to_viewport
		if keyboard_height > 0.0:
			overlap_source = viewport_height - keyboard_height

	for i in raise_targets.size():
		var target: Node2D = raise_targets[i]
		if target == null:
			continue

		var base: Vector2 = _base_positions[i]
		var lift: float = 0.0
		if overlap_source > 0.0:
			lift = maxf((base.y + raise_margin) - overlap_source, 0.0)

		target.position = Vector2(base.x, base.y - lift)

## Everything the player types arrives here as the field's full contents, so
## it is forwarded a character at a time and then wiped. The guard is because
## clearing the text re-emits text_changed.
func _on_text_changed(new_text: String) -> void:
	if _draining or not typing_challenge:
		return

	if new_text.is_empty():
		return

	_draining = true
	for character in new_text:
		typing_challenge.input_letter(character)
	text_input.text = ""
	_draining = false
