extends SceneTree

## The Training tab built all three drills and none of them was playable.
##
## Nothing was wired wrong - the host found every scene, every signal it
## connects exists, and a live probe confirmed the mechanic node was there in
## all three cases. What was missing is that each of the three mechanics is
## normally driven by its own song's scene animation, and the host only
## replaced part of what that animation does:
##
##   PENDULUM  the song drives `started` AND `dropped`
##             (sng_safety_lullaby.tscn tracks 0/1 and 3/4). The host set only
##             `started`. lullaby_pendulum.gd reveals the visual from
##             _on_drop_changed(); the Anchor is authored modulate alpha 0 and
##             RESET repaints the same alpha, so the drill ran, judged and
##             scored against a pendulum nobody could see.
##
##   PULSE     mch_heartbeat.tscn authors no position; Chimera places the
##             instance at (1185, 786). Parented straight to the HUD it sat at
##             (0, 0), with an ECG line authored from x=-700 drawn off the
##             left edge of the screen.
##
##   TYPING    typing_challenge.gd is driven entirely by `time_end`, an
##             absolute position on the level clock, plus `show_celebi`.
##             Neither was written, so `time_end` kept its authored 0.0 and
##             BOTH initiate_challenge() and start_challenge() returned on
##             their `current_time >= time_end + end_offset` guard. No word,
##             no unowns, no timer - the drill did literally nothing.
##
## And on top of that, no touch controls at all: the test level's only touch
## node is addons/rubicon_mobile_controls/mobile_controls.tscn, which is a
## bare Control. Both the pendulum server and the heartbeat controller read
## `lullaby_special`, which nothing on a phone was producing, and the typing
## drill had no keyboard.
##
## None of that is visible to a parse check, to the animation-track sweep, or
## to the authored-property sweep, because every one of these is a value a
## script has to write at runtime. So it is pinned here, as text, against the
## authored state that makes each rule necessary.
##
## Run with:
##   godot --headless --path . --script tools/test_training_setup.gd

const HOST := "res://lullaby_mod/scripts/lullaby/training/lullaby_training_host.gd"
const OVERLAY := "res://lullaby_mod/scripts/lullaby/training/lullaby_training_overlay.gd"
const PENDULUM_SCENE := "res://lullaby_mod/resources/funkin/songs/global/mechanics/mch_pendulum.tscn"
const HEARTBEAT_SCENE := "res://lullaby_mod/resources/funkin/songs/chimera/mch_heartbeat.tscn"
const TYPING_SCENE := "res://lullaby_mod/resources/funkin/songs/monochrome/scenes/mch_typing.tscn"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	var host: String = FileAccess.get_file_as_string(HOST)
	var overlay: String = FileAccess.get_file_as_string(OVERLAY)
	_check(not host.is_empty(), "the training host is readable")
	_check(not overlay.is_empty(), "the training overlay is readable")

	_check_pendulum(host)
	_check_pulse(host)
	_check_typing(host)
	_check_touch_scripts(host)
	_check_overlay_font_sizes(overlay)

	print("training setup: %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)

## The rule and its reason, checked together: the host must set `dropped`,
## and the scene must still be the kind of scene that needs it. If someone
## ever authors the Anchor visible, this check says so instead of silently
## going on pinning a line that no longer matters.
func _check_pendulum(host: String) -> void:
	var body: String = _func_body(host, "_build_pendulum")
	# Matched as real code, not as text: both of these are named in this
	# function's own doc comment, so a plain contains() passes on a commented
	# -out assignment - which is precisely the bug.
	_check(_has_statement(body, "server\\.dropped\\s*=\\s*true"),
		"_build_pendulum reveals the pendulum (server.dropped)")
	_check(_has_statement(body, "server\\.started\\s*=\\s*true"),
		"_build_pendulum still starts the pendulum (server.started)")

	var scene: String = FileAccess.get_file_as_string(PENDULUM_SCENE)
	_check(scene.contains("[node name=\"Anchor\" type=\"Node2D\" parent=\".\"")
			and scene.contains("modulate = Color(1, 1, 1, 0)"),
		"mch_pendulum.tscn still ships its Anchor transparent (why dropped is needed)")

func _check_pulse(host: String) -> void:
	var body: String = _func_body(host, "_build_pulse")
	_check(_has_statement(body, "position\\s*=\\s*_pulse_position\\("),
		"_build_pulse places the heart instead of leaving it at (0, 0)")

	# The heart is the right-hand end of the ECG widget, not its middle, so
	# centring the sprite is not centring what the player looks at. Derived
	# from the viewport and from the controller's own line fields rather than
	# copied from Chimera - which authors its own line_start/line_end, so a
	# hardcoded figure would be centred for exactly one tuning.
	var placer: String = _func_body(host, "_pulse_position")
	_check(placer.contains("get_visible_rect()"),
		"_pulse_position centres against the viewport rather than a magic number")
	_check(placer.contains("&\"line_start\"") and placer.contains("&\"line_end\""),
		"_pulse_position reads the line span off the controller it is placing")

	# A position authored in the mechanic scene itself would make the host's
	# one redundant, and would mean two places decide where the heart goes.
	var scene: String = FileAccess.get_file_as_string(HEARTBEAT_SCENE)
	var root: String = _node_block(scene, "[node name=\"AnimatedSprite2D\" type=\"AnimatedSprite2D\"")
	_check(not root.contains("position = "),
		"mch_heartbeat.tscn still authors no position of its own (why the host must)")

func _check_typing(host: String) -> void:
	var body: String = _func_body(host, "_build_typing")
	_check(_has_statement(body, "set\\(&\"show_celebi\", true\\)"),
		"_build_typing switches show_celebi on (typing_challenge._process returns without it)")
	_check(_has_statement(body, "_start_typing_round\\(\\)"),
		"_build_typing starts a round")
	_check(body.contains("challenge_success") and body.contains("challenge_fail"),
		"_build_typing hooks both outcomes so the drill queues the next word")

	var round_body: String = _func_body(host, "_start_typing_round")
	_check(round_body.contains("&\"time_end\""),
		"_start_typing_round writes a deadline the clock can reach")
	_check(round_body.contains("_clock_position()"),
		"the deadline is built from the same clock typing_challenge.gd reads")
	_check(round_body.contains("&\"fail_count\""),
		"_start_typing_round clears fail_count (at 3, fail() leaves the unowns on screen)")

	# time_end is set BEFORE active/prompt_user, because its setter is what
	# clears challenge_over - the other order leaves both entry points refusing
	# to run, which is the shipped bug exactly.
	var at_time_end: int = round_body.find("&\"time_end\"")
	var at_active: int = round_body.find("&\"active\"")
	_check(at_time_end >= 0 and at_active > at_time_end,
		"time_end is written before active (its setter is what clears challenge_over)")

	var scene: String = FileAccess.get_file_as_string(TYPING_SCENE)
	_check(scene.contains("time_end = 0.0"),
		"mch_typing.tscn still authors time_end = 0.0 (why the host must write one)")

## load() by path returns null on a rename and the host only push_error()s -
## the drill would come up with no controls and no other symptom.
func _check_touch_scripts(host: String) -> void:
	for constant: String in ["MECHANIC_BUTTON_SCRIPT", "TYPING_TOUCH_SCRIPT"]:
		var path: String = _const_string(host, constant)
		_check(not path.is_empty(), "%s is declared" % constant)
		if path.is_empty():
			continue
		_check(ResourceLoader.exists(path), "%s points at a file that exists (%s)" % [constant, path])

	_check(_has_statement(_func_body(host, "_build_pendulum"), "_add_special_button\\("),
		"the pendulum drill gets a lullaby_special tap target")
	_check(_has_statement(_func_body(host, "_build_pulse"), "_add_special_button\\("),
		"the pulse drill gets a lullaby_special tap target")
	_check(_has_statement(_func_body(host, "_build_typing"), "_add_typing_touch\\("),
		"the typing drill gets a keyboard")

	var button: String = _func_body(host, "_add_special_button")
	_check(button.contains("&\"lullaby_special\""),
		"the tap target dispatches the action both mechanics actually read")

## The whole overlay is built in code, so nothing inherits a scene-authored
## font size - every Label and Button came up at Godot's stock 16px on a
## 1920x1080 canvas, about 13 real pixels on a 1600x720 phone. Pinned as a
## shape: any Label/Button this file creates has to say how big its text is.
func _check_overlay_font_sizes(overlay: String) -> void:
	var creation := RegEx.new()
	# Has to admit an explicit type annotation as well as := and plain =,
	# or the one Button written as `var x: RubiconActionButton = ...` slips
	# past silently - which is exactly the shape of miss this check exists
	# to prevent.
	creation.compile("(?m)^\\s*(?:var\\s+)?(_?[a-z_]+)\\s*(?::\\s*\\w+\\s*)?:?=\\s*(?:Label|Button|RubiconActionButton)\\.new\\(\\)")

	var missing: PackedStringArray = []
	var found: int = 0
	for m: RegExMatch in creation.search_all(overlay):
		var variable: String = m.get_string(1)
		found += 1
		if not overlay.contains("%s.add_theme_font_size_override" % variable):
			missing.append(variable)

	_check(found >= 6, "the overlay still builds its labels and buttons in code (%d found)" % found)
	_check(missing.is_empty(),
		"every Label/Button the overlay creates sets a font size (missing: %s)"
			% ("none" if missing.is_empty() else ", ".join(missing)))

## True when `pattern` appears on a line that is actually executed - an
## indented line whose first non-whitespace character is not `#`. Half the
## things pinned here are also named in the doc comments that explain why,
## so contains() alone cannot tell a live assignment from a commented one.
func _has_statement(body: String, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[\\t ]*[^#\\n]*" + pattern)
	return re.search(body) != null

## Everything from `func <name>` up to the next top-level `func`.
func _func_body(text: String, name: String) -> String:
	var head: int = text.find("func %s(" % name)
	if head < 0:
		_check(false, "%s() exists" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)

## A `[node ...]` block, up to the next one.
func _node_block(text: String, head_line: String) -> String:
	var head: int = text.find(head_line)
	if head < 0:
		_check(false, "node block %s exists" % head_line)
		return ""
	var tail: int = text.find("\n[node ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)

func _const_string(text: String, name: String) -> String:
	var re := RegEx.new()
	re.compile("const %s\\s*:?=\\s*\"([^\"]+)\"" % name)
	var m: RegExMatch = re.search(text)
	return m.get_string(1) if m != null else ""

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK  ", label)
	else:
		_failures += 1
		print("  FAIL ", label)
