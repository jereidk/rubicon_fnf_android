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

@export_group("Showcase")

## Showcase Mode cannot use the system keyboard: it belongs to another app
## (Gboard, or whatever the player installed), is drawn in its own window,
## and nothing can highlight its keys - not Godot, not Android. So showcase
## gets the drawn keyboard this screen used to use instead, which is ours and
## can therefore be animated. It is only ever built in showcase, so normal
## play still gets the native keyboard and none of this exists.
##
## Bigger than the touch default on purpose: nobody taps this one, so the key
## size is for legibility at a distance rather than for thumbs.
@export var showcase_key_size: Vector2 = Vector2(96, 96)
@export var showcase_key_gap: float = 10.0
@export var showcase_space_width: float = 460.0

## Gap between the bottom of the keyboard and the bottom of the screen.
@export var showcase_bottom_margin: float = 56.0

## Keycap styling. The keys are plain Buttons on Godot's default theme
## otherwise, which is nearly black and leaves nothing for a flash to lift.
@export var showcase_key_color: Color = Color("2f2f36")
@export var showcase_label_color: Color = Color("e8e8ee")
@export var showcase_font_size: int = 34

## How long a key stays lit after the autoplay presses it, and what colour it
## goes. This is the pressed key's background, not a modulate multiplier -
## multiplying a near-black keycap is what made the first version invisible.
@export var showcase_flash_seconds: float = 0.22
@export var showcase_flash_color: Color = Color("d8c24a")

var _base_positions: PackedVector2Array
var _draining: bool = false

var _showcase_keyboard: RubiconOnScreenKeyboard
## Uppercase character -> that key's Button, read back out of the built
## keyboard rather than by changing on_screen_keyboard.gd, which is one of
## the scripts carried over from the pck.
var _showcase_keys: Dictionary = {}
var _showcase_tweens: Dictionary = {}
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

	var showcase_height: float = _process_showcase_keyboard()
	_apply_raise(wants_input, showcase_height)

## Returns how much of the screen the showcase keyboard is covering, in
## viewport units, so the unowns can be lifted clear of it exactly the way
## they are lifted clear of the system one. Zero whenever it isn't shown.
func _process_showcase_keyboard() -> float:
	# The challenge is what decides there is typing to show; autoplay is not
	# checked, because in showcase it is always on and that is the point.
	var showing: bool = (LullabyShowcase.is_active()
		and typing_challenge.active
		and typing_challenge.prompt_user
		and not typing_challenge.challenge_over)

	if not showing:
		if _showcase_keyboard:
			_showcase_keyboard.visible = false
		_last_letters_passed = -1
		return 0.0

	if _showcase_keyboard == null:
		_build_showcase_keyboard()
		if _showcase_keyboard == null:
			return 0.0

	_showcase_keyboard.visible = true
	_layout_showcase_keyboard()
	_flash_typed_key()
	return _showcase_keyboard.size.y + showcase_bottom_margin

## RubiconOnScreenKeyboard builds its keys in _ready(), so every exported
## value has to be set before it enters the tree.
func _build_showcase_keyboard() -> void:
	_showcase_keyboard = RubiconOnScreenKeyboard.new()
	_showcase_keyboard.name = "ShowcaseKeyboard"
	_showcase_keyboard.key_size = showcase_key_size
	_showcase_keyboard.key_gap = showcase_key_gap
	_showcase_keyboard.space_width = showcase_space_width
	_showcase_keyboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_showcase_keyboard)

	# It hides itself when there is no touchscreen and then never builds its
	# keys, which on a desktop run would leave an empty Control here.
	if _showcase_keyboard.get_child_count() == 0:
		_showcase_keyboard.queue_free()
		_showcase_keyboard = null
		return

	for button in _find_buttons(_showcase_keyboard):
		# _make_key() labels letter keys with the uppercase character and the
		# space bar with the word SPACE, so the text is the key's identity.
		_showcase_keys[button.text] = button
		_style_showcase_key(button)

## The keys are plain Buttons wearing Godot's default theme, which is a very
## dark grey. Multiplying modulate on that barely changes anything - the first
## version's flash was being applied correctly and was invisible on screen -
## so the keys get their own keycap styling here, both to make them read as
## keys and to give the flash something bright enough to lift.
##
## Done from this side rather than in on_screen_keyboard.gd, which is one of
## the scripts carried over from the pck and is also what normal touch play
## would use if it ever came back.
func _style_showcase_key(button: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = showcase_key_color
	box.set_corner_radius_all(10)
	box.border_width_bottom = 4
	box.border_color = showcase_key_color.darkened(0.35)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_stylebox_override("pressed", box)
	button.add_theme_stylebox_override("disabled", box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", showcase_label_color)
	button.add_theme_font_size_override("font_size", showcase_font_size)

## Centres the keyboard horizontally and sits it above the bottom edge. Done
## every frame rather than once because the rows only report a real size
## after their containers have laid out, and because the viewport can change
## size (rotation, or the render-scale settings).
func _layout_showcase_keyboard() -> void:
	var rows: Control = _showcase_keyboard.get_child(0) as Control
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
	_showcase_keyboard.size = wanted

	var area: Vector2 = size if size.x > 0.0 else get_viewport_rect().size
	_showcase_keyboard.position = Vector2(
		roundf((area.x - wanted.x) * 0.5),
		roundf(area.y - wanted.y - showcase_bottom_margin))

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
	var button: Button = _showcase_keys.get(key)
	if button == null or not is_instance_valid(button):
		return

	var box: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	if box == null:
		return

	# Same reason RubiconActionButton._flash() kills its own tween first: two
	# tweens writing the same property can leave a key stuck lit.
	var previous: Tween = _showcase_tweens.get(button)
	if previous and previous.is_valid():
		previous.kill()

	box.bg_color = showcase_flash_color
	box.border_color = showcase_flash_color.darkened(0.35)
	var tween: Tween = button.create_tween()
	tween.set_parallel(true)
	tween.tween_property(box, "bg_color", showcase_key_color, showcase_flash_seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "border_color", showcase_key_color.darkened(0.35),
		showcase_flash_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_showcase_tweens[button] = tween

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
func _apply_raise(wants_input: bool, showcase_height: float = 0.0) -> void:
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
	elif showcase_height > 0.0:
		# The showcase keyboard is already in viewport units - it is a Control
		# in this scene, not an OS window - so it needs no conversion. The two
		# are mutually exclusive in practice (showcase forces autoplay, which
		# clears wants_input) but the branch keeps them from ever stacking.
		overlap_source = viewport_height - showcase_height

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
