class_name LullabyTrainingOverlay extends CanvasLayer

## Everything a training session needs around the mechanic: a way out, a
## pause, an end, and something to show for it.
##
## The test level has none of this. It has no pause menu, no gameover module
## and nothing that happens when the chart runs out, which is fine for the
## placeholder the main menu opens but leaves a drill with no shape at all.
##
## Built in code rather than as a scene because it is four Buttons and two
## Labels, and because the three song pause menus are all song-themed scenes
## (johto, kanto, chimera) with no neutral one to borrow.

signal exit_requested
signal restart_requested

## Above the level's own UILayer, below SceneChanger's loading screen at 128.
const LAYER := 40

enum State { RUNNING, PAUSED, FINISHED }

var hits: int = 0
var misses: int = 0

var _state: State = State.RUNNING
var _elapsed: float = 0.0
var _stats: Label
var _dim: ColorRect
var _panel: VBoxContainer
var _title: Label
var _first_button: Button

func _ready() -> void:
	layer = LAYER
	# The panel has to work while the tree is paused, which is the whole
	# point of the pause half.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_stats = Label.new()
	_stats.name = "Stats"
	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stats.offset_right = -32.0
	_stats.offset_top = 32.0
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stats)

	# EXIT stays reachable at all times, including mid-drill. ui_cancel is
	# Esc, gamepad B and Android's hardware Back, and _unhandled_input below
	# answers the same action, so touch and keyboard land in one place.
	var exit_button: RubiconActionButton = RubiconActionButton.new()
	exit_button.name = "Exit"
	exit_button.action = &"ui_cancel"
	exit_button.verb = "EXIT"
	exit_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	exit_button.offset_left = 32.0
	exit_button.offset_top = 32.0
	exit_button.custom_minimum_size = Vector2(180, 72)
	exit_button.size = exit_button.custom_minimum_size
	root.add_child(exit_button)

	# The panel sits over live gameplay, which on Chimera's heartbeat is a
	# bright red line and on Monochrome a white stage. Without something
	# behind it the text competes with whatever is moving underneath.
	# MOUSE_FILTER_STOP as well as opaque: while the panel is up, a tap on
	# the world behind it should hit the dim and stop, not reach the lanes.
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)

	_panel = VBoxContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_theme_constant_override("separation", 16)
	_panel.visible = false
	root.add_child(_panel)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_title)

	_add_panel_button("RESUME", _on_resume)
	_add_panel_button("RESTART", _on_restart)
	_add_panel_button("EXIT", _on_exit)

	_refresh_stats()

func _add_panel_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = text
	button.text = text
	button.custom_minimum_size = Vector2(260, 72)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(handler)
	_panel.add_child(button)
	return button

func _process(delta: float) -> void:
	if _state != State.RUNNING:
		return
	_elapsed += delta
	_refresh_stats()

## Counted rather than scored. Every mechanic now reports both sides -
## pendulum_success/pendulum_missed were already there, and beat_hit and
## challenge_success were added to the other two alongside the failures they
## already announced.
func record_hit() -> void:
	hits += 1
	_refresh_stats()

func record_miss() -> void:
	misses += 1
	_refresh_stats()

func _refresh_stats() -> void:
	if _stats == null:
		return
	_stats.text = "HITS  %d\nMISSES  %d\nTIME  %d:%02d" % [
		hits, misses, int(_elapsed) / 60, int(_elapsed) % 60,
	]

## Only when there is something to divide by - a drill you exited before the
## first beat should say nothing rather than "0%".
func _accuracy() -> String:
	var total: int = hits + misses
	if total <= 0:
		return ""
	return "ACCURACY  %d%%" % int(round(100.0 * float(hits) / float(total)))

func pause_session() -> void:
	if _state != State.RUNNING:
		return
	_show_panel(State.PAUSED, "PAUSED")

## Called when the chart runs out or health hits zero. Both end the drill;
## the title is the only difference, because a training session that stops
## because you died should say so.
func finish_session(reason: String) -> void:
	if _state == State.FINISHED:
		return
	_show_panel(State.FINISHED, reason)

func _show_panel(state: State, title: String) -> void:
	_state = state
	_title.text = "%s\n\nHITS  %d\nMISSES  %d\nTIME  %d:%02d\n%s" % [
		title, hits, misses, int(_elapsed) / 60, int(_elapsed) % 60, _accuracy(),
	]
	# Resuming a drill that has ended is meaningless; restarting it is not.
	_panel.get_node(^"RESUME").visible = state == State.PAUSED
	_dim.visible = true
	_panel.visible = true
	get_tree().paused = true

	_first_button = _panel.get_node(^"RESUME") if state == State.PAUSED else _panel.get_node(^"RESTART")
	_first_button.grab_focus()

func _on_resume() -> void:
	if _state != State.PAUSED:
		return
	_state = State.RUNNING
	_dim.visible = false
	_panel.visible = false
	get_tree().paused = false

func _on_restart() -> void:
	get_tree().paused = false
	restart_requested.emit()

func _on_exit() -> void:
	get_tree().paused = false
	exit_requested.emit()

## is_action_pressed, not is_action: every synthetic action in this project
## arrives as a press and then a release one frame later, and the release
## would fire whatever this did a second time.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"funkin_pause"):
		get_viewport().set_input_as_handled()
		if _state == State.PAUSED:
			_on_resume()
		else:
			pause_session()
		return

	if not event.is_action_pressed(&"ui_cancel"):
		return

	get_viewport().set_input_as_handled()
	# While paused, Back is "un-pause" rather than "leave" - the same thing
	# it means in every other menu in the game. Otherwise it leaves.
	if _state == State.PAUSED:
		_on_resume()
	else:
		_on_exit()
