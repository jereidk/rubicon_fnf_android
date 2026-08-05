extends Control
class_name LullabyTouchNoteInput

## Touch gameplay mode ("Gameplay Control: Touch" in the Mobile settings):
## the player taps the falling notes themselves instead of the full-height
## lane hitbox zones. Each tap picks the unhit note whose visual centre is
## nearest to the finger, within a radius scaled by
## Settings.lullaby_touch_note_hitbox_size; up to four simultaneous
## fingers (one per lane) cover chords, and a held finger keeps a hold
## note held until it is lifted - the engine's own judgment windows and
## scoring are untouched, because this drives the exact same handler
## methods (_press/_release) that the lane hitbox drives, just targeted at
## a specific note instead of a whole lane.
##
## Instanced at runtime by lullaby_mobile_controls_applier.gd while the
## Touch mode is active, so no song scene has to be edited. Only the note
## at each handler's `note_hit_index` is ever a candidate: the engine
## judges lanes in order, so a "future" note cannot be hit without
## skipping the ones before it. Tapping too early or off-note is a silent
## ghost (the same LANE_STATE_PUSH the hitbox produces), never a penalty.
##
## note_controller is duck-typed (a real RubiconLevelNoteController, but
## the contract is just `note_handlers` + `should_autoplay()` +
## `disable_inputs`), matching the rest of the touch-addon's style.

signal note_pressed(lane: int)
signal note_released(lane: int)

const MOUSE_TOUCH_INDEX := -1000
const MAX_ACTIVE_TOUCHES := 4
## Half the lane spacing (160px) plus slack: at the default size the tap
## radius covers the arrow art and the strumline offset without ever
## reaching into a neighbouring lane's lane-line.
const BASE_RADIUS := 100.0
const LANE_ID_PREFIX := "mania_lane"

## Matches RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE (1). Kept as a
## local constant so this script has no compile-time dependency on the
## rubicon engine classes - everything else here is already duck-typed.
const HIT_INCOMPLETE := 1
const HAPTIC_FEEDBACK := true
const HAPTIC_DURATION_MS := 35

## Authoring for the special button (right-centre, 140x140, 30px gap).
## Scaled by the Touch Note Hitbox Size setting so a bigger tap target
## also means a bigger mechanic button; the scale factor is pinned to
## 0.75..1.5 so the button never becomes untappably small or covers the
## whole screen at the extreme settings.
const SPECIAL_BUTTON_GAP := 30.0
const SPECIAL_BUTTON_SIZE := 140.0

## A real RubiconLevelNoteController (duck-typed, see class doc).
@export var note_controller: Node

## The round red mechanic button (LullabyMechanicActionButton) owned by
## this overlay; shown only while the song's special mechanic is active.
@export var special_button: Button

## The mechanic's source node (e.g. LullabyPendulumServer) exposing
## `started` / `autoplay` booleans, duck-typed like
## RubiconSongTouchControls.mechanic_source.
@export var mechanic_source: Node

## The score/health HUD - hidden the same way RubiconMobileControls hides
## itself during cutscenes (fade via modulate:alpha), pause and gameover.
@export var default_hud: CanvasItem

## Any node exposing an "is_game_over" bool (Safety Lullaby's in-scene
## gameover cutscene, which never changes the scene).
@export var gameover_source: Node

## Extra zones that must never count as note taps, in addition to every
## visible Button in the scene (pause/restart, Chimera's mechanic buttons
## and the special button are all Buttons, so they are picked up
## automatically - this covers non-Button zones only).
@export var reserved_controls: Array[Control] = []

var _touch_to_note: Dictionary = {}
var _lane_to_touch: Dictionary = {}
var _reserved: Array[Control] = []
var _special_scale: float = 1.0

func _ready() -> void:
	add_to_group("lullaby_touch_note_input")
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Raw _input() ignores mouse_filter, so IGNORE keeps this overlay from
	# blocking the buttons beneath it while still seeing every touch.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collect_reserved()
	tree_exiting.connect(_release_all)

func _process(_delta: float) -> void:
	_update_visibility()

func _collect_reserved() -> void:
	_reserved.clear()
	var scene := get_tree().current_scene
	if scene != null:
		# find_children("*", "Button") matches both the built-in Button and
		# everything extending it (RubiconActionButton, pause icon, etc.).
		for node in scene.find_children("*", "Button", true, false):
			if node is Control:
				_reserved.append(node)
	for control in reserved_controls:
		if control != null:
			_reserved.append(control)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not _controller_accepts_input():
		return

	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(MOUSE_TOUCH_INDEX, event.position, event.pressed)

func _controller_accepts_input() -> bool:
	if note_controller == null or not is_instance_valid(note_controller):
		return false
	if note_controller.get("disable_inputs"):
		return false
	return not note_controller.call("should_autoplay")

func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _touch_to_note.has(index) or _lane_to_touch.size() >= MAX_ACTIVE_TOUCHES:
			return
		if _is_reserved(pos):
			return
		var hit := _find_note_at(pos)
		if hit.lane < 0:
			return
		if _lane_to_touch.has(hit.lane):
			return
		_touch_to_note[index] = hit
		_lane_to_touch[hit.lane] = index
		_press_note(hit)
		note_pressed.emit(hit.lane)
	else:
		if not _touch_to_note.has(index):
			return
		var hit: Dictionary = _touch_to_note[index]
		_touch_to_note.erase(index)
		if _lane_to_touch.get(hit.lane) == index:
			_lane_to_touch.erase(hit.lane)
		_release_note(hit)
		note_released.emit(hit.lane)

## Nearest unhit note across the four lanes, within the scaled radius.
## Only each lane's `note_hit_index` note counts (see class doc) and a
## lane that is already being held is skipped so a second finger cannot
## double-press the same hold.
func _find_note_at(pos: Vector2) -> Dictionary:
	var radius: float = BASE_RADIUS * clampf(Settings.lullaby_touch_note_hitbox_size, 0.25, 4.0)
	var best: Dictionary = {"lane": -1, "index": -1}
	var best_distance := radius

	var handlers: Dictionary = note_controller.get("note_handlers")
	for key: String in handlers:
		if not key.begins_with(LANE_ID_PREFIX):
			continue
		var lane: int = key.trim_prefix(LANE_ID_PREFIX).to_int()
		if _lane_to_touch.has(lane):
			continue

		var handler: Object = handlers[key]
		if handler == null or not handler.has_method("_press"):
			continue

		var index: int = handler.get("note_hit_index")
		var data: Array = handler.get("data")
		if index >= data.size():
			continue

		var graphics: Array = handler.get("graphics")
		if index >= graphics.size() or graphics[index] == null:
			continue

		var results: Array = handler.get("results")
		if index < results.size() and results[index] != null:
			var scoring_hit: int = results[index].get("scoring_hit")
			if scoring_hit == HIT_INCOMPLETE:
				continue

		var center: Vector2 = _note_center(graphics[index])
		var distance: float = center.distance_to(pos)
		if distance <= best_distance:
			best_distance = distance
			best = {"lane": lane, "index": index}

	return best

## Visual centre of a note in global coordinates: the rotated arrow
## container's AABB centre when available, falling back to the note's own
## global position (the lane-line point it crosses the strumline at).
func _note_center(note: Control) -> Vector2:
	var container = note.get("reference_container")
	if container is Control:
		return container.get_global_rect().get_center()
	return note.global_position

## A tap inside a visible reserved zone (pause button, mechanic buttons,
## Chimera's zones...) never counts as a note: those controls consume the
## touch themselves.
func _is_reserved(pos: Vector2) -> bool:
	for control in _reserved:
		if control == null or not is_instance_valid(control):
			continue
		if control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return true
	return false

func _press_note(hit: Dictionary) -> void:
	var handler: Object = _handler_for(hit.lane)
	if handler == null:
		return
	# The note may have been missed/despawned between selection and press
	# (a frame boundary); only press when it is still the lane's current
	# note. Otherwise this is a ghost tap, same as the hitbox.
	if handler.get("note_hit_index") != hit.index:
		return
	if not handler.has_method("_press") or not handler.has_method("_should_process"):
		return
	if not handler.call("_should_process"):
		return

	var event := InputEventScreenTouch.new()
	handler.call("_press", event)
	if HAPTIC_FEEDBACK:
		Input.vibrate_handheld(HAPTIC_DURATION_MS)

func _release_note(hit: Dictionary) -> void:
	var handler: Object = _handler_for(hit.lane)
	if handler == null:
		return
	# Only complete the note if it is still the lane's current one AND
	# still being held - a hold auto-completes at its end, after which
	# note_hit_index has already advanced and this release must do nothing.
	if handler.get("note_hit_index") != hit.index:
		return
	if not handler.has_method("_release"):
		return
	var results: Array = handler.get("results")
	if hit.index >= results.size() or results[hit.index] == null:
		return
	if results[hit.index].get("scoring_hit") != HIT_INCOMPLETE:
		return

	var event := InputEventScreenTouch.new()
	handler.call("_release", event)

func _handler_for(lane: int) -> Object:
	if note_controller == null or not is_instance_valid(note_controller):
		return null
	var handlers: Dictionary = note_controller.get("note_handlers")
	return handlers.get("%s%d" % [LANE_ID_PREFIX, lane])

func _release_all() -> void:
	for hit: Dictionary in _touch_to_note.values():
		_release_note(hit)
	_touch_to_note.clear()
	_lane_to_touch.clear()

func _update_visibility() -> void:
	if get_tree().paused:
		_hide_and_release()
		return

	if gameover_source != null and is_instance_valid(gameover_source) and "is_game_over" in gameover_source and bool(gameover_source.get("is_game_over")):
		_hide_and_release()
		return

	var hud_visible: bool = true
	if default_hud != null and is_instance_valid(default_hud):
		hud_visible = default_hud.visible and default_hud.modulate.a > 0.01

	if not hud_visible:
		_hide_and_release()
	else:
		visible = true

	_update_special_button()

func _hide_and_release() -> void:
	if visible or not _touch_to_note.is_empty():
		_release_all()
	visible = false
	if special_button != null and is_instance_valid(special_button):
		special_button.visible = false

func _update_special_button() -> void:
	if special_button == null or not is_instance_valid(special_button):
		return
	if not visible or mechanic_source == null or not is_instance_valid(mechanic_source):
		special_button.visible = false
		return

	var started: bool = "started" in mechanic_source and bool(mechanic_source.get("started"))
	var autoplay: bool = "autoplay" in mechanic_source and bool(mechanic_source.get("autoplay"))
	# Showcase mode wants the mechanic controls visible and flashing along
	# with the pendulum's autoplay hits, same rule as
	# SafetyLullabyTouchControls.
	var showing_off: bool = Settings.lullaby_showcase_mode
	_update_special_button_size()
	special_button.visible = started and (not autoplay or showing_off)

## Re-derives the button's offsets from the Touch Note Hitbox Size
## setting, only when that scale actually changed (this runs every frame).
func _update_special_button_size() -> void:
	var scale: float = 0.5 + 0.5 * clampf(Settings.lullaby_touch_note_hitbox_size, 0.5, 2.0)
	if is_equal_approx(scale, _special_scale):
		return
	_special_scale = scale
	special_button.offset_right = -SPECIAL_BUTTON_GAP * scale
	special_button.offset_left = special_button.offset_right - SPECIAL_BUTTON_SIZE * scale
	special_button.offset_top = -SPECIAL_BUTTON_SIZE * 0.5 * scale
	special_button.offset_bottom = SPECIAL_BUTTON_SIZE * 0.5 * scale
