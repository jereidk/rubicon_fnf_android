extends CanvasLayer

## Port of Lullaby's global volume popup (autoloads/volume_slider.tscn).
## Scroll the mouse wheel anywhere in the game to nudge the Master bus
## volume; the bar pops down from the top and auto-hides after a couple
## of seconds. The original script is compiled bytecode we can't recover,
## so this reimplements the behavior its exported properties describe.
##
## volume_up/volume_down/volume_mute (project.godot) also fire this same
## popup+sound - each is bound to both a desktop keyboard stand-in ("-"/"="/
## "0") and Godot's dedicated KEY_VOLUMEDOWN/KEY_VOLUMEUP/KEY_VOLUMEMUTE,
## which is what Android's hardware volume rocker actually sends, so the
## physical buttons get identical feedback to the keyboard shortcut.

const MAX_STEPS := 10.0
const MIN_DB := -40.0

@export var bar_container: Container
@export var timer: Timer
@export var animation_player: AnimationPlayer
@export var volume_down: AudioStreamPlayer
@export var volume_up: AudioStreamPlayer

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	timer.timeout.connect(_on_timer_timeout)
	_refresh_bars()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_volume(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_volume(-1)
	elif event.is_action_pressed(&"volume_up"):
		_change_volume(1)
	elif event.is_action_pressed(&"volume_down"):
		_change_volume(-1)
	elif event.is_action_pressed(&"volume_mute"):
		_toggle_mute()

func _change_volume(direction: int) -> void:
	var bus := AudioServer.get_bus_index("Master")
	var steps: float = clampf(_db_to_steps(AudioServer.get_bus_volume_db(bus)) + direction, 0.0, MAX_STEPS)
	AudioServer.set_bus_volume_db(bus, _steps_to_db(steps))
	AudioServer.set_bus_mute(bus, steps <= 0.0)

	if direction > 0:
		volume_up.play()
	else:
		volume_down.play()

	_show_popup()

func _toggle_mute() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))
	_show_popup()

func _show_popup() -> void:
	_refresh_bars()
	animation_player.play("in_immediate" if visible else "in")
	timer.start()

func _on_timer_timeout() -> void:
	animation_player.play("out")

func _refresh_bars() -> void:
	var bus := AudioServer.get_bus_index("Master")
	var muted: bool = AudioServer.is_bus_mute(bus)
	var steps: float = _db_to_steps(AudioServer.get_bus_volume_db(bus))
	var lit_bars: int = 0 if muted else roundi(steps / MAX_STEPS * bar_container.get_child_count())
	var bars := bar_container.get_children()
	for i in bars.size():
		var bar: ProgressBar = bars[i]
		bar.value = bar.max_value if i < lit_bars else 0.0

func _steps_to_db(steps: float) -> float:
	if steps <= 0.0:
		return -80.0
	return lerpf(MIN_DB, 0.0, steps / MAX_STEPS)

func _db_to_steps(db: float) -> float:
	if db <= -80.0:
		return 0.0
	return clampf(inverse_lerp(MIN_DB, 0.0, db), 0.0, 1.0) * MAX_STEPS
