extends Node

## Builds the mechanic the Training tab asked for into the test level.
##
## Sits in songs/test/test.tscn and does nothing at all on an ordinary run -
## LullabyTraining.take_request() returns NONE unless a Training button set
## it, so the test level still opens as the plain placeholder the main menu
## uses.
##
## Each mechanic goes in the way its own song already instances it, which is
## the whole reason the Test song works as a host: none of the three needed
## to be rewritten, only placed and started.

## Where a mechanic's visuals go. The test level's own HUD Control, so the
## mechanic sits with the judgment popup and health bar rather than over the
## notes.
@export var ui_parent: Control

## Fed to mch_typing, which unlike the other two is not self-contained: it
## exports reference_level and health_module and Monochrome wires both from
## the song. bar_animation is Monochrome's own HUD bar and stays null here -
## typing_challenge.gd is the thing that has to tolerate that.
@export var level: Node
@export var health_module: Node

## The end-of-song signal. RubiconLevelClock and RubiconLevel have no
## "finished" of their own, so the instrumental player's is the one available.
@export var instrumental: AudioStreamPlayer

## Your lanes. Switched to autoplay for a training session, which is the fix
## for two problems at once.
##
## The test level ships a full four-lane chart you are expected to play, and
## the health module drives itself off that controller's note_changed - so a
## Typing drill could end with OUT OF HEALTH because you dropped NOTES while
## the mechanic went perfectly. The panel would blame the wrong thing.
##
## Autoplay rather than removing the notes: the pendulum and the heartbeat
## are timed against the song, and the lanes are the visible beat. They stay
## as the metronome, they stop being a second task.
@export var player_notes: Node

## Words to practise with. Monochrome's own list is story text; these are
## neutral and short enough to land inside one pass.
const TRAINING_WORDS: Array[String] = [
	"pulse", "steady", "listen", "breathe", "focus", "again",
	"slower", "hold", "ready", "calm",
]

const SHOP_SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"

## The round red "special" button the Touch gameplay mode already uses for
## Safety Lullaby's pendulum. Training needs it for two of the three drills
## and had NONE of it: the test level's only touch node is
## addons/rubicon_mobile_controls/mobile_controls.tscn, which is a bare
## Control with nothing inside - no RubiconMechanicHitbox (Safety Lullaby
## supplies its own), no typing controls (Monochrome supplies its own). Both
## the pendulum server and the heartbeat controller read
## `event.is_action_pressed(&"lullaby_special")` and nothing on a phone was
## ever producing that action, so those two drills were unplayable by touch
## and the typing one had no keyboard.
##
## Loaded by path rather than by class_name for the same reason
## lullaby_mobile_controls_applier.gd does it: the button is created at
## runtime with Button.new() + set_script, which needs the Script resource.
const MECHANIC_BUTTON_SCRIPT := "res://lullaby_mod/scripts/lullaby/settings/lullaby_mechanic_action_button.gd"

## Monochrome's own typing touch layer - a hidden focused LineEdit for the
## system keyboard, or the drawn RubiconPaintedKeyboard when the player
## picked In-Game (or is in Showcase Mode). Reused whole rather than
## reimplemented: it already handles both paths, the Mobile > Keyboard
## setting, hiding itself on desktop, and lifting the unowns clear of the
## keyboard.
const TYPING_TOUCH_SCRIPT := "res://lullaby_mod/songs/monochrome/scripts/monochrome_typing_touch_controls.gd"

## Square, and generous: this is the only control in a drill whose whole
## point is hitting a beat, so it is bigger than the 140px the Touch overlay
## uses next to four note lanes it must not cover. Nothing competes with it
## here - the lanes play themselves.
const SPECIAL_BUTTON_SIZE := 200.0
const SPECIAL_BUTTON_GAP := 48.0

## Where the heart goes. mch_heartbeat.tscn authors no position of its own -
## Chimera places the instance at (1185, 786) - so parenting it to the HUD
## put it at (0, 0), with an ECG line authored from x=-700 to x=+150 drawn
## almost entirely off the left edge of the screen. Same figure as Chimera's,
## lifted a little because there is no Serena underneath it here.
const PULSE_POSITION := Vector2(1185.0, 700.0)

## How long each typing round gets, in song seconds.
##
## typing_challenge.gd is driven entirely by `time_end`, an absolute position
## on the level clock that Monochrome writes from its scene animation. Nobody
## wrote it here, so it kept its authored 0.0 - and both initiate_challenge()
## and start_challenge() bail out when `current_time >= time_end + end_offset`.
## The drill therefore did nothing at all: no word, no unowns, no Celebi, no
## timer. Training writes a rolling deadline instead, one per round.
##
## Eight seconds against Monochrome's own windows, which run 6.7s, 6.3s, 4.2s,
## 2.75s and 3.1s: a practice round should be the comfortable end of that,
## not the tightest.
const TYPING_WINDOW_SECONDS := 8.0

## Gap between one word being resolved and the next one arriving. Long enough
## to clear succeed()/fail()'s own 0.5s unown exit and read the result.
const TYPING_GAP_SECONDS := 1.5


## Set the moment an exit is accepted, so the release half of one tap cannot
## start a second one - the same guard the death screens needed.
var _leaving: bool = false

var _overlay: LullabyTrainingOverlay
var _requested: LullabyTraining.Mechanic = LullabyTraining.Mechanic.NONE

## The typing drill loops itself; these two hold that loop.
var _typing: Node
var _typing_restarting: bool = false

func _ready() -> void:
	var mechanic: LullabyTraining.Mechanic = LullabyTraining.take_request()
	if mechanic == LullabyTraining.Mechanic.NONE:
		return

	_requested = mechanic

	# Before the mechanic, not after: the test level has no pause menu, no
	# gameover module and no exit of any kind - its MobileControls is a bare
	# placeholder Control - so without this there is no way out of a training
	# session at all except killing the app. A mechanic that fails to build
	# must not take the overlay down with it.
	_build_overlay()
	_watch_session()
	_free_the_notes()

	var path: String = String(LullabyTraining.SCENES.get(mechanic, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("Training: no scene for mechanic %d" % mechanic)
		return

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Training: could not load %s" % path)
		return

	match mechanic:
		LullabyTraining.Mechanic.PENDULUM:
			_build_pendulum(packed)
		LullabyTraining.Mechanic.PULSE:
			_build_pulse(packed)
		LullabyTraining.Mechanic.TYPING:
			_build_typing(packed)

## lullaby_pendulum.gd finds its server by walking UP the parent chain, so
## the server has to be an ancestor of the visual rather than a sibling. The
## server goes into the HUD and the pendulum goes under the server, which is
## a level deeper than Safety Lullaby nests it but is what the lookup wants.
##
## Safety Lullaby drives `started` from a song animation track. There is no
## such track here, so training just switches it on and leaves it on.
func _build_pendulum(packed: PackedScene) -> void:
	var host: Control = _hud()
	if host == null:
		return

	var server: LullabyPendulumServer = LullabyPendulumServer.new()
	server.name = "TrainingPendulumServer"
	host.add_child(server)

	var pendulum: Node = packed.instantiate()
	server.add_child(pendulum)

	# BOTH flags, not just started. The pendulum's Anchor is authored
	# modulate = Color(1,1,1,0) and its RESET animation paints the same
	# alpha 0; the only thing that ever reveals it is the "drop" animation,
	# which lullaby_pendulum.gd plays from _on_drop_changed(). Safety
	# Lullaby drives `started` AND `dropped` from its scene animation
	# (sng_safety_lullaby.tscn tracks 0/1 and 3/4). Training set only
	# `started`, so the mechanic ran, judged and scored against a pendulum
	# that was never on screen - the drill was invisible, not broken.
	server.dropped = true
	server.started = true
	_count(server, [&"pendulum_success"], [&"pendulum_missed"], [&"mechanic_failed"])

	_add_special_button(host, "TAP ON THE SWING")

## heartbeat_controller.gd already exposes initialize()/stop() as tool
## buttons for playtesting in the editor, which is exactly a training
## session. mch_heartbeat.tscn carries the controller inside it (Chimera
## reaches it at Heart/HeartbeatController), so this only has to find it.
func _build_pulse(packed: PackedScene) -> void:
	var host: Control = _hud()
	if host == null:
		return

	var heart: Node = packed.instantiate()
	var heart_item := heart as CanvasItem
	if heart_item != null:
		# Chimera ships this instance hidden and reveals it from a sequence;
		# there is no sequence here to do it.
		heart_item.visible = true
	var heart_node := heart as Node2D
	if heart_node != null:
		heart_node.position = PULSE_POSITION
	host.add_child(heart)

	var controller: Node = _first_with_method(heart, &"initialize")
	if controller == null:
		push_error("Training: mch_heartbeat has no node with initialize()")
		return
	controller.call(&"initialize")
	_count(controller, [&"beat_hit"], [&"beat_missed"], [&"mechanic_failed"])

	_add_special_button(host, "TAP ON THE BEAT")

## The one that is not drop-in. Monochrome wires reference_level,
## bar_animation and health_module from the song; two of those exist here and
## the third does not, so it is left unset rather than pointed at something
## that is not a bar.
func _build_typing(packed: PackedScene) -> void:
	var host: Control = _hud()
	if host == null:
		return

	var typing: Node = packed.instantiate()
	host.add_child(typing)

	if level != null and "reference_level" in typing:
		typing.set(&"reference_level", level)
	if health_module != null and "health_module" in typing:
		typing.set(&"health_module", health_module)

	if "word_list" in typing:
		typing.set(&"word_list", TRAINING_WORDS)
	if "choose_from_list" in typing:
		typing.set(&"choose_from_list", true)

	# After add_child, so the setter's own $Celebi / celebi_animator work and
	# so _ready() has already applied the starting state it would otherwise
	# overwrite. Without this the mechanic's whole _process body returns on
	# its first line (`or not show_celebi`) - no ticking clock, no Celebi, no
	# timeout, so a word could never end and the drill could never advance.
	if "show_celebi" in typing:
		typing.set(&"show_celebi", true)

	_typing = typing
	_count(typing, [&"challenge_success"], [&"challenge_fail"], [])

	# Separate from _count's scoring hooks: those two feed the readout, these
	# drive the loop. Monochrome gets a fresh word from its scene animation
	# every bout; a drill has no animation, so it queues its own.
	if typing.has_signal(&"challenge_success"):
		typing.connect(&"challenge_success", _on_typing_round_over)
	if typing.has_signal(&"challenge_fail"):
		typing.connect(&"challenge_fail", _on_typing_round_over.unbind(1))

	_add_typing_touch(host, typing)
	_start_typing_round()

## One word, with a deadline the level clock can actually reach.
##
## Every field here is written in the order typing_challenge.gd's own setters
## need: time_end first, because its setter is what clears challenge_over and
## passed_challenge, and both initiate_challenge() and start_challenge()
## refuse to run while challenge_over is set or the deadline is in the past.
##
## active/prompt_user are toggled only on the first round and called directly
## afterwards. Toggling active off and on again would work too, but active is
## also what MonochromeTypingTouchControls watches to decide whether the
## system keyboard belongs on screen - flipping it between every word would
## dismiss and re-raise the Android keyboard each time, and that animation
## comes out of the player's next typing window.
func _start_typing_round() -> void:
	if _typing == null or not is_instance_valid(_typing):
		return

	# fail_count is Monochrome's three-strikes game-over counter. It never
	# resets on its own, and at 3 fail() returns early without exiting the
	# unowns - so after three dropped words a drill would leave the previous
	# word's letters sitting on screen forever. A drill has no game over.
	if "fail_count" in _typing:
		_typing.set(&"fail_count", 0)

	_typing.set(&"time_end", _clock_position() + TYPING_WINDOW_SECONDS)

	if not bool(_typing.get(&"active")):
		_typing.set(&"active", true)
	else:
		_typing.call(&"initiate_challenge")

	if not bool(_typing.get(&"prompt_user")):
		_typing.set(&"prompt_user", true)
	else:
		_typing.call(&"start_challenge")

## Both outcomes queue the next word. The guard is because a round can end
## twice in the same frame - input_letter() calls end_challenge() on the last
## letter and _process can set active = false on the same frame's timeout.
func _on_typing_round_over() -> void:
	if _typing_restarting or _typing == null or not is_instance_valid(_typing):
		return
	_typing_restarting = true

	# process_always = false on purpose: pausing the drill has to pause the
	# queue with it, or the panel comes up and a new word starts behind it.
	await get_tree().create_timer(TYPING_GAP_SECONDS, false).timeout

	_typing_restarting = false
	if is_instance_valid(_typing):
		_start_typing_round()

## Where the mechanic thinks it is. typing_challenge.gd reads exactly this,
## so a deadline built from it is in the same units as the comparison that
## consumes it.
func _clock_position() -> float:
	if level == null or not is_instance_valid(level):
		return 0.0
	var clock: Object = level.get(&"clock")
	if clock == null:
		return 0.0
	var player: AnimationPlayer = clock.get(&"animation_player")
	if player == null:
		return 0.0
	return player.current_animation_position

## The tap target for `lullaby_special`, for the two drills that read it.
##
## Deliberately the round button rather than Safety Lullaby's full-width
## RubiconMechanicHitbox: one control that means one thing, in the same place
## for both drills, regardless of what the Mobile > Gameplay Control setting
## is set to. It is also useful on desktop - RubiconActionButton draws the
## key currently bound to the action underneath the glyph, which is the one
## place in the game that tells you what to press.
func _add_special_button(host: Control, hint: String) -> void:
	var script: Script = load(MECHANIC_BUTTON_SCRIPT)
	if script == null:
		push_error("Training: could not load %s" % MECHANIC_BUTTON_SCRIPT)
		return

	var button := Button.new()
	button.set_script(script)
	button.name = "TrainingSpecialButton"
	button.set(&"action", &"lullaby_special")
	button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.offset_right = -SPECIAL_BUTTON_GAP
	button.offset_left = button.offset_right - SPECIAL_BUTTON_SIZE
	button.offset_top = -SPECIAL_BUTTON_SIZE * 0.5
	button.offset_bottom = SPECIAL_BUTTON_SIZE * 0.5
	host.add_child(button)

	if _overlay != null:
		_overlay.set_hint(hint)

## The typing drill's keyboard. Everything is assigned before add_child
## because MonochromeTypingTouchControls._ready() is what reads raise_targets
## (to remember where the unowns started) and connects text_changed - an
## export set afterwards is set too late for both.
func _add_typing_touch(host: Control, typing: Node) -> void:
	var script: Script = load(TYPING_TOUCH_SCRIPT)
	if script == null:
		push_error("Training: could not load %s" % TYPING_TOUCH_SCRIPT)
		return

	var controls := Control.new()
	controls.set_script(script)
	controls.name = "TrainingTypingTouch"
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Invisible and untappable by design - it exists to hold focus so Android
	# raises its own keyboard, and is drained a character at a time into the
	# mechanic. Same shape as Monochrome's authored TextInput.
	var field := LineEdit.new()
	field.name = "TextInput"
	field.modulate = Color(1, 1, 1, 0)
	field.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	field.offset_top = -8.0
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.caret_blink = false
	controls.add_child(field)

	controls.set(&"typing_challenge", typing)
	controls.set(&"text_input", field)

	var raise: Array[Node2D] = []
	for child_name: String in ["Unowns", "UnownLetters"]:
		var node := typing.get_node_or_null(NodePath(child_name)) as Node2D
		if node != null:
			raise.append(node)
	controls.set(&"raise_targets", raise)

	host.add_child(controls)

	if _overlay != null:
		_overlay.set_hint("TYPE THE LETTERS")

## The overlay owns the exit, the pause, the end of the drill and the
## readout. Kept as its own node rather than folded in here so that the host
## stays "build the mechanic" and nothing else.
func _build_overlay() -> void:
	_overlay = LullabyTrainingOverlay.new()
	_overlay.name = "TrainingOverlay"
	_overlay.exit_requested.connect(_on_exit_requested)
	_overlay.restart_requested.connect(_on_restart_requested)
	_overlay.drill_name = _drill_name(_requested)
	add_child(_overlay)

## What the overlay calls the drill. The three Training buttons are labelled
## Pendulum / Pulse / Typing in the console, so these match them rather than
## the mechanics' internal names.
func _drill_name(mechanic: LullabyTraining.Mechanic) -> String:
	match mechanic:
		LullabyTraining.Mechanic.PENDULUM:
			return "PENDULUM"
		LullabyTraining.Mechanic.PULSE:
			return "PULSE"
		LullabyTraining.Mechanic.TYPING:
			return "TYPING"
	return "TRAINING"

## The two ways a drill ends on its own. Neither exists in this level: there
## is no gameover module to catch health_depleted, and nothing at all happens
## when the chart runs out, so the instrumental finishing is the end-of-song
## signal - the clock and the level do not have one.
func _watch_session() -> void:
	if health_module != null and health_module.has_signal(&"health_depleted"):
		health_module.connect(&"health_depleted", _on_died)

	if instrumental != null and instrumental.has_signal(&"finished"):
		instrumental.connect(&"finished", _on_song_finished)

## Notes become scenery. should_autoplay() gates both the input path and the
## judging, so with this on your lanes hit themselves and stop feeding the
## health module anything you did or did not do.
func _free_the_notes() -> void:
	if player_notes == null or not is_instance_valid(player_notes):
		return
	if "autoplay" in player_notes:
		player_notes.set(&"autoplay", true)

## What the songs treat as losing the mechanic. Safety Lullaby wires
## LullabyPendulumServer.mechanic_failed straight into the health module's
## health_depleted, so this is the same ending, reached the same way - and
## now the only thing that can end a drill early, since the notes no longer
## touch health.
func _on_mechanic_failed() -> void:
	if _overlay != null:
		_overlay.finish_session("MECHANIC FAILED")

func _on_died() -> void:
	if _overlay != null:
		_overlay.finish_session("OUT OF HEALTH")

func _on_song_finished() -> void:
	if _overlay != null:
		_overlay.finish_session("DRILL OVER")

## Restart puts the same request back before reloading, so the drill comes
## up again instead of the plain placeholder level.
func _on_restart_requested() -> void:
	if _leaving:
		return
	_leaving = true
	LullabyTraining.requested = _requested
	SceneChanger.change_to(LullabyTraining.TEST_SONG, &"hypno")

func _on_exit_requested() -> void:
	if _leaving:
		return
	_leaving = true
	# The shop reads this static in its own _ready() and puts you back at the
	# TV instead of at the entrance. Nothing wrote it before now - the
	# "Kollectadex" case next to it has been waiting for a writer.
	CollectorShop.previous_state = "Console"
	SceneChanger.change_to(SHOP_SCENE, &"hypno", true)

## Each mechanic's own vocabulary for the same two outcomes, routed to the
## overlay's two counters. beat_hit and challenge_success were added to
## heartbeat_controller.gd and typing_challenge.gd for this; the pendulum
## server already announced both sides.
## mechanic_failed is terminal, not a miss: the pendulum only emits it once
## retention has already run out over many drops, and Safety Lullaby treats
## it as death. Typing has no terminal signal - a dropped word is just a
## dropped word there.
func _count(node: Node, hit_signals: Array[StringName], miss_signals: Array[StringName],
		fail_signals: Array[StringName]) -> void:
	if _overlay == null:
		return
	_connect_all(node, hit_signals, _overlay.record_hit)
	_connect_all(node, miss_signals, _overlay.record_miss)
	_connect_all(node, fail_signals, _on_mechanic_failed)

func _connect_all(node: Node, signals: Array[StringName], handler: Callable) -> void:
	for name: StringName in signals:
		if not node.has_signal(name):
			continue
		# challenge_fail carries a failure code and mechanic_failed carries
		# nothing; connecting a signal with arguments to a zero-arg method is
		# an error, so unbind however many it actually has.
		var callable: Callable = handler
		var arg_count: int = _signal_arg_count(node, name)
		if arg_count > 0:
			callable = callable.unbind(arg_count)
		node.connect(name, callable)

func _signal_arg_count(node: Node, name: StringName) -> int:
	for info: Dictionary in node.get_signal_list():
		if StringName(info.get("name", "")) == name:
			return (info.get("args", []) as Array).size()
	return 0

func _hud() -> Control:
	if ui_parent != null and is_instance_valid(ui_parent):
		return ui_parent
	push_error("Training: ui_parent is not set on the host")
	return null

func _first_with_method(root: Node, method: StringName) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_method(method):
			return node
		for child in node.get_children():
			stack.append(child)
	return null
