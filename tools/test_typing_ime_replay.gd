extends SceneTree

## Monochrome's typing mechanic survives an Android IME.
##
## The bug this pins was reported four separate times on the published port,
## by four people who had not spoken to each other:
##
##   "escribo la primera letra y bien, pero de ahi todas me las marca mal
##    aunque las escriba bien"
##   "a las dos letras ya me la cuenta como fallada"
##   "Esta impossivel jogar a monochrome pelo jeito que voce fez a mecanica"
##
## Two independent causes, both invisible on a PC.
##
## ONE: the same keystroke judged twice. Android delivers the on-screen
## keyboard's characters as ordinary InputEventKey to the whole tree, and
## Node._input() runs BEFORE the focused Control's _gui_input - so
## TypingChallenge._input() read every character the hidden LineEdit was about
## to read as well. The first reading was right and advanced the word; the
## second was then compared against the NEXT letter and missed.
##
## TWO: the composing region. Godot's GodotTextInputWrapper turns the Android
## EditText's diff into key events - one KEYCODE_DEL per replaced character
## from beforeTextChanged, then every character of the replacement from
## onTextChanged. Gboard keeps the word being typed in a composing region and
## calls setComposingText with the WHOLE word on every keystroke, so the
## "replacement" is the entire prefix, every time:
##
##     type m  ->  'm'
##     type o  ->  DEL, 'm', 'o'
##     type n  ->  DEL, DEL, 'm', 'o', 'n'
##
## Each of those lands as its own text_changed. A field that was wiped after
## every character therefore replayed the word from the start on every
## keystroke and fed the mechanic m, then m + o, then m + o + n - and
## input_letter() judges each character against the ONE letter it is waiting
## for, so every replayed letter missed. A miss costs 0.5s off a window that
## is 2.75s by the fourth bout.
##
## Why this is checked as source and not as behaviour: nothing in this song's
## input path can be instantiated headless. typing_challenge.gd names
## `Debugger`, the touch controls name `Settings` and `LullabyShowcase`, and
## autoload identifiers are not registered when the engine is started with
## --script, so both scripts fail to compile in the only mode a guard runs in.
## That is why every test in this directory reads source rather than driving
## it, and this one is no exception.
##
## The one thing it does check against the engine is the keyboard constant,
## which is worth a run on its own: the first version of the fix asked for
## LineEdit.VIRTUAL_KEYBOARD_TYPE_PASSWORD, which does not exist - the enum is
## KEYBOARD_TYPE_*, unprefixed - and that is a parse error that takes the
## whole typing screen down with it, not a setting that quietly misses.
##
## Run with:
##   godot --headless --path . --script tools/test_typing_ime_replay.gd

const TOUCH := "res://lullaby_mod/songs/monochrome/scripts/monochrome_typing_touch_controls.gd"
const CHALLENGE := "res://lullaby_mod/scripts/lullaby/mechanics/monochrome/typing_challenge.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var touch: String = _read(TOUCH)
	var challenge: String = _read(CHALLENGE)

	_double_read_checks(challenge)
	_composing_checks(touch)
	_constant_checks(touch)

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## Cause one: the keystroke the LineEdit is about to read must not be read
## here as well.
func _double_read_checks(challenge: String) -> void:
	var body: String = _code_only(_func_body(challenge, "_input"))
	_check(body.contains("gui_get_focus_owner()"),
		"TypingChallenge._input() mira quien tiene el foco")
	_check(body.contains("is LineEdit"),
		"...y reconoce un campo de texto")

	# On the CODE and after the guard, because a `return` anywhere in the
	# function would satisfy a looser check while doing nothing - the original
	# already had three of them.
	var focus_at: int = body.find("gui_get_focus_owner()")
	var return_at: int = body.find("return", focus_at)
	_check(focus_at >= 0 and return_at > focus_at,
		"...y se aparta, en vez de juzgar la letra por segunda vez")


## Cause two: the field is the mirror of Android's EditText, so it is never
## cleared while that one is still accumulating.
func _composing_checks(touch: String) -> void:
	_check(touch.contains("var _consumed: String"),
		"los controles llevan la cuenta de lo ya entregado al mecanismo")

	var changed: String = _code_only(_func_body(touch, "_on_text_changed"))
	_check(not changed.is_empty(), "_on_text_changed existe")

	# The heart of it. Wiping the field is what desynchronised the two ends,
	# and it is a one-line regression to reintroduce.
	_check(not changed.contains('text_input.text = ""'),
		"_on_text_changed ya NO vacia el campo (era la mitad del bug)")

	# Only the tail past what was consumed is forwarded, and a shorter string
	# forwards nothing - which is what absorbs both the DEL and the replayed
	# prefix without them ever reaching input_letter().
	_check(changed.contains("_consumed.length()"),
		"...compara contra lo ya entregado")
	var drop_at: int = changed.find("<= already")
	var feed_at: int = changed.find("input_letter(")
	_check(drop_at >= 0 and feed_at > drop_at,
		"...y descarta lo que no es mas largo ANTES de alimentar ninguna letra")
	_check(changed.contains("range(already,"),
		"...alimentando solo la cola nueva y no la palabra entera")

	# The early window, before prompt_user, is the other way the two ends can
	# drift apart: clearing there leaves Android holding characters this side
	# has never seen, and every keystroke of the bout after it arrives as a
	# replay of a word with no known prefix.
	var early: String = changed.substr(0, maxi(changed.find("var already"), 0))
	_check(early.contains("_consumed = new_text"),
		"lo tecleado antes de tiempo se absorbe, no se borra")

	# And the one place a reset IS correct: the focus boundary, which is where
	# HANDLER_OPEN_IME_KEYBOARD does setText("") + append(mOriginText) and puts
	# the two ends back in step. Before the early-out, or a bout that ended
	# with nothing to undo would start the next one dirty.
	var avail: String = _code_only(_func_body(touch, "_set_input_available"))
	var reset_at: int = avail.find('_consumed = ""')
	# The full condition: `if not text_input.visible:` also appears in the
	# branch ABOVE the reset, and matching that one made this check fail
	# against code that was already right.
	var bail_at: int = avail.find("if not text_input.visible and")
	_check(reset_at >= 0, "_set_input_available reinicia la cuenta al soltar el foco")
	_check(reset_at >= 0 and bail_at > reset_at,
		"...antes de su salida temprana, o una tanda empieza con la cuenta sucia")


## The belt to the above braces, checked against the engine's own enum.
func _constant_checks(touch: String) -> void:
	var m: RegExMatch = RegEx.create_from_string(
		"virtual_keyboard_type = LineEdit\\.([A-Z_]+)").search(touch)
	_check(m != null, "el campo fija el tipo de teclado")
	if m == null:
		return

	var name: String = m.get_string(1)
	var known: PackedStringArray = ClassDB.class_get_enum_constants(
		"LineEdit", "VirtualKeyboardType")
	_check(known.has(name),
		"LineEdit.%s existe de verdad en este motor" % name)
	_check(name.ends_with("PASSWORD"),
		"...y es el que Android traduce a TYPE_TEXT_VARIATION_PASSWORD, "
		+ "que apaga sugerencias y region de composicion (%s)" % name)


## `body` with comment lines removed, for checks about what the code DOES.
func _code_only(body: String) -> String:
	var out: PackedStringArray = []
	for line: String in body.split("\n"):
		var code: String = line
		var hash_at: int = code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		out.append(code)
	return "\n".join(out)


func _func_body(text: String, name: String) -> String:
	var head: int = -1
	var from: int = 0
	while true:
		var at: int = text.find("func %s(" % name, from)
		if at < 0:
			break
		if at == 0 or text[at - 1] == "\n":
			head = at
			break
		from = at + 1
	if head < 0:
		_check(false, "%s() existe al nivel superior" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "%s se lee" % path.get_file())
	return text
