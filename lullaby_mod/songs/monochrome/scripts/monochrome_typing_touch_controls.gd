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

@export_group("Drawn keyboard")

## Showcase Mode cannot use the system keyboard: it belongs to another app
## (Gboard, or whatever the player installed), is drawn in its own window,
## and nothing can highlight its keys - not Godot, not Android. So showcase
## gets the drawn keyboard this screen used to use instead, which is ours and
## can therefore be animated. It is also what the Mobile > Keyboard setting
## selects when the player prefers the game's own keys, so it is a real input
## method and not only a showcase prop - see _on_drawn_key_pressed.
##
## Bigger than RubiconOnScreenKeyboard's default on purpose: 96px keys are
## comfortable thumb targets on a phone and still legible from across a room
## in a showcase, so one size serves both uses.
@export var drawn_key_size: Vector2 = Vector2(96, 96)
@export var drawn_key_gap: float = 10.0
@export var drawn_space_width: float = 460.0

## Gap between the bottom of the keyboard and the bottom of the screen.
@export var drawn_bottom_margin: float = 56.0

## Keycap styling. The keys are plain Buttons on Godot's default theme
## otherwise, which is nearly black and leaves nothing for a flash to lift.
@export var drawn_key_color: Color = Color("2f2f36")
@export var drawn_label_color: Color = Color("e8e8ee")
@export var drawn_font_size: int = 34

## How long a key stays lit after the autoplay presses it, and what colour it
## goes. This is the pressed key's background, not a modulate multiplier -
## multiplying a near-black keycap is what made the first version invisible.
@export var drawn_flash_seconds: float = 0.22
@export var drawn_flash_color: Color = Color("d8c24a")

var _base_positions: PackedVector2Array
var _draining: bool = false

var _drawn_keyboard: RubiconOnScreenKeyboard
## Uppercase character -> that key's Button, read back out of the built
## keyboard rather than by changing on_screen_keyboard.gd, which is one of
## the scripts carried over from the pck.
var _drawn_keys: Dictionary = {}
var _drawn_tweens: Dictionary = {}
## Watching this advance is how a typed letter is spotted;
## TypingChallenge._autoplay_process emits no signal, and that file is the
## pck's too.
var _last_letters_passed: int = -1

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

	var challenge_wants: bool = (
		typing_challenge.active
		and typing_challenge.prompt_user
		and not typing_challenge.challenge_over
	)

	# Showcase overrides the setting rather than reading it. The system
	# keyboard is another app's window - its keys cannot be shown being
	# pressed, and raising it would cover the song - so a showcase always
	# gets the drawn one no matter what the player picked.
	var drawn: bool = (LullabyShowcase.is_active()
		or Settings.lullaby_mobile_keyboard_type == Settings.MobileKeyboardType.IN_GAME)

	# The hidden LineEdit is only ever focused for the system keyboard. On the
	# drawn path it stays unreachable, which is what keeps Android from
	# raising its keyboard behind ours.
	var wants_input: bool = challenge_wants and not typing_challenge.autoplay and not drawn

	if wants_input:
		_set_input_available(true)
		if not text_input.has_focus():
			text_input.grab_focus()
	else:
		_set_input_available(false)

	var drawn_height: float = _process_drawn_keyboard(drawn and challenge_wants)
	_apply_raise(wants_input, drawn_height)

## Returns how much of the screen the drawn keyboard is covering, in viewport
## units, so the unowns can be lifted clear of it exactly the way they are
## lifted clear of the system one. Zero whenever it isn't shown.
##
## Autoplay is deliberately not part of `showing`: in showcase it is always
## on, and the keyboard staying up is the entire point.
func _process_drawn_keyboard(showing: bool) -> float:
	if not showing:
		if _drawn_keyboard:
			_drawn_keyboard.visible = false
		_last_letters_passed = -1
		return 0.0

	if _drawn_keyboard == null:
		_build_drawn_keyboard()
		if _drawn_keyboard == null:
			return 0.0

	_drawn_keyboard.visible = true
	_layout_drawn_keyboard()
	_flash_typed_key()
	return _drawn_keyboard.size.y + drawn_bottom_margin

## RubiconOnScreenKeyboard builds its keys in _ready(), so every exported
## value has to be set before it enters the tree.
func _build_drawn_keyboard() -> void:
	_drawn_keyboard = RubiconOnScreenKeyboard.new()
	_drawn_keyboard.name = "DrawnKeyboard"
	_drawn_keyboard.key_size = drawn_key_size
	_drawn_keyboard.key_gap = drawn_key_gap
	_drawn_keyboard.space_width = drawn_space_width
	_drawn_keyboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drawn_keyboard)

	# It hides itself when there is no touchscreen and then never builds its
	# keys, which on a desktop run would leave an empty Control here.
	if _drawn_keyboard.get_child_count() == 0:
		_drawn_keyboard.queue_free()
		_drawn_keyboard = null
		return

	# Tappable, because this is a real input method when the player picks
	# In-Game and not only a showcase prop. In showcase nobody taps it, so
	# the connection simply never fires there.
	_drawn_keyboard.key_pressed.connect(_on_drawn_key_pressed)

	for button in _find_buttons(_drawn_keyboard):
		# _make_key() labels letter keys with the uppercase character and the
		# space bar with the word SPACE, so the text is the key's identity.
		_drawn_keys[button.text] = button
		_style_drawn_key(button)

## The keys are plain Buttons wearing Godot's default theme, which is a very
## dark grey. Multiplying modulate on that barely changes anything - the first
## version's flash was being applied correctly and was invisible on screen -
## so the keys get their own keycap styling here, both to make them read as
## keys and to give the flash something bright enough to lift.
##
## Done from this side rather than in on_screen_keyboard.gd, which is one of
## the scripts carried over from the pck and is also what normal touch play
## would use if it ever came back.
func _style_drawn_key(button: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = drawn_key_color
	box.set_corner_radius_all(10)
	box.border_width_bottom = 4
	box.border_color = drawn_key_color.darkened(0.35)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_stylebox_override("pressed", box)
	button.add_theme_stylebox_override("disabled", box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", drawn_label_color)
	button.add_theme_font_size_override("font_size", drawn_font_size)

## Centres the keyboard horizontally and sits it above the bottom edge. Done
## every frame rather than once because the rows only report a real size
## after their containers have laid out, and because the viewport can change
## size (rotation, or the render-scale settings).
func _layout_drawn_keyboard() -> void:
	var rows: Control = _drawn_keyboard.get_child(0) as Control
	if rows == null:
		return

	var wanted: Vector2 = rows.get_combined_minimum_size()
	if wanted.x <= 0.0 or wanted.y <= 0.0:
		return

	# The keyboard's own Control never sizes itself to its rows - it just
	# parents them - so both are set here, which is what keeps the block
	# square to the screen instead of hanging off the top-left corner.
	rows.size = wanted
	rows.position = Vector2.ZERO
	_drawn_keyboard.size = wanted

	var area: Vector2 = size if size.x > 0.0 else get_viewport_rect().size
	_drawn_keyboard.position = Vector2(
		roundf((area.x - wanted.x) * 0.5),
		roundf(area.y - wanted.y - drawn_bottom_margin))

## input_letter() consumes current_word[letters_passed] and advances, and it
## skips runs of spaces first, so the counter can jump by more than one. The
## last non-space character it swallowed is the one that was actually typed.
func _flash_typed_key() -> void:
	var passed: int = typing_challenge.letters_passed
	if _last_letters_passed < 0:
		_last_letters_passed = passed
		return
	if passed <= _last_letters_passed:
		_last_letters_passed = passed
		return

	var word: String = typing_challenge.current_word
	var typed: String = ""
	for i in range(_last_letters_passed, mini(passed, word.length())):
		if word[i] != " ":
			typed = word[i]
	_last_letters_passed = passed

	if typed.is_empty():
		return
	_flash_key(typed.to_upper())

## Lights the key by tweening its keycap colour back down from the flash
## colour, so the key itself changes rather than being multiplied.
func _flash_key(key: String) -> void:
	var button: Button = _drawn_keys.get(key)
	if button == null or not is_instance_valid(button):
		return

	var box: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	if box == null:
		return

	# Same reason RubiconActionButton._flash() kills its own tween first: two
	# tweens writing the same property can leave a key stuck lit.
	var previous: Tween = _drawn_tweens.get(button)
	if previous and previous.is_valid():
		previous.kill()

	box.bg_color = drawn_flash_color
	box.border_color = drawn_flash_color.darkened(0.35)
	var tween: Tween = button.create_tween()
	tween.set_parallel(true)
	tween.tween_property(box, "bg_color", drawn_key_color, drawn_flash_seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "border_color", drawn_key_color.darkened(0.35),
		drawn_flash_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_drawn_tweens[button] = tween

## The mechanic is the single source of truth for what has been typed, the
## same as the LineEdit path - this only forwards the character.
func _on_drawn_key_pressed(character: String) -> void:
	if typing_challenge == null or typing_challenge.autoplay:
		return
	typing_challenge.input_letter(character)

func _find_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	for child in node.get_children():
		var button := child as Button
		if button != null:
			out.append(button)
		out.append_array(_find_buttons(child))
	return out

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
func _apply_raise(wants_input: bool, drawn_height: float = 0.0) -> void:
	var overlap_source: float = 0.0
	var viewport_height: float = get_viewport_rect().size.y

	if wants_input:
		# virtual_keyboard_get_height() is in real screen pixels while the
		# targets live in the viewport's base resolution, so it has to be
		# scaled by the stretch ratio before it means anything to them.
		var window_height: float = float(DisplayServer.window_get_size().y)
		var to_viewport: float = viewport_height / window_height if window_height > 0.0 else 1.0
		var keyboard_height: float = float(DisplayServer.virtual_keyboard_get_height()) * to_viewport
		if keyboard_height > 0.0:
			overlap_source = viewport_height - keyboard_height
	elif drawn_height > 0.0:
		# The drawn keyboard is already in viewport units - it is a Control in
		# this scene, not an OS window - so it needs no conversion. The two are
		# mutually exclusive by construction (wants_input is false whenever the
		# drawn keyboard is up) but the branch keeps them from ever stacking.
		overlap_source = viewport_height - drawn_height

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
