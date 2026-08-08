extends Control
class_name LullabyTouchNoteInput

## Touch gameplay mode ("Gameplay Control: Touch" in the Mobile settings).
##
## Behaves exactly like the lane hitbox (RubiconMobileControls), with two
## differences: it draws nothing, and its tap zones sit on the STATIC
## receptor arrows instead of running the full height of the screen.
##
## ## Why the previous version was unplayable
##
## It tried to be cleverer than the hitbox: each tap searched for the
## falling note whose on-screen centre was nearest the finger, within a
## radius. But the player taps the receptor - the static arrow at the
## strumline - and a note only reaches that point at the instant it should
## be hit. Any tap made before then (i.e. essentially every tap, since you
## press *as* the note arrives, not after) found no note within the radius
## and was silently dropped. It also refused a second finger on a lane that
## was already held, so chords and holds fought each other. The result was
## a mode that read as "the touchscreen does not respond".
##
## The fix is to stop targeting notes at all. Lanes are what the engine
## judges; a tap belongs to a lane, and the engine decides whether a note
## was there. That is precisely what the hitbox does, so this now shares
## its dispatch path verbatim.
##
## ## Dispatch
##
## Presses go through RubiconTouchInputHandler (`/root/RubiconTouchInput`),
## which synthesises an InputEventKey and feeds it to
## Input.parse_input_event() - the same route RubiconMobileControls uses.
## RubiconLevelNoteController matches raw InputEvents against its
## RubiconLevelNoteInputMap, so this reaches the engine through its own
## front door: judgment windows, scoring, splashes, character animations
## and lane_state all behave identically to the hitbox and to a physical
## keyboard, with no per-note bookkeeping here to get out of step.
##
## (The previous version called handler._press()/_release() directly. That
## bypassed the controller and made this script responsible for state the
## engine already owns - which is how it ended up leaving lane_state stuck
## at LANE_STATE_HIT and drifting Monochrome's camera.)
##
## note_controller is duck-typed (a real RubiconLevelNoteController, but the
## contract is just `note_handlers` + `should_autoplay()` + `disable_inputs`),
## matching the rest of the touch-addon's style.

signal note_pressed(lane: int)
signal note_released(lane: int)

const MOUSE_TOUCH_INDEX := -1000
const LANE_ID_PREFIX := "mania_lane"

## Fallback lane spacing, used only if the lane positions cannot be read
## (single lane, or handlers not laid out yet). The real value is measured
## from the receptors themselves - see _lane_zones().
const FALLBACK_SPACING := 160.0

const HAPTIC_DURATION_MS := 35

## The authored range of the Touch Note Hitbox Size option (see the
## TouchNoteHitboxSize row in console.tscn). Everything that scales off
## that setting clamps to this same pair, so a value that somehow lands
## outside it degrades identically everywhere.
const SIZE_SCALE_MIN := 0.5
const SIZE_SCALE_MAX := 2.0

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

## touch index -> lane, and lane -> how many fingers are currently on it.
## The refcount is what makes multitouch behave: a second finger landing on
## a lane that is already held must not re-press it, and lifting one of two
## fingers must not release the lane while the other is still down. The old
## version rejected the second finger outright instead, which is why more
## than a couple of fingers appeared not to work.
var _touch_to_lane: Dictionary = {}
var _lane_active_count: Dictionary = {}

## Deliberately an impossible scale so the first _update_special_button_size()
## always applies the offsets. Starting it at 1.0 meant that at the default
## setting (also 1.0) the very first call early-returned, and the button only
## ever had a rect because the applier happened to author the same numbers -
## a silent break the moment either default moved.
var _special_scale: float = -1.0

var _reserved: Array[Control] = []

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
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
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
		if _touch_to_lane.has(index):
			return
		if _is_reserved(pos):
			return
		var lane: int = _lane_at(pos)
		if lane < 0:
			return
		_touch_to_lane[index] = lane
		_press_lane(lane)
	else:
		if not _touch_to_lane.has(index):
			return
		var lane: int = _touch_to_lane[index]
		_touch_to_lane.erase(index)
		_release_lane(lane)

## Sliding from one receptor to another hands the hold over, exactly like
## RubiconMobileControls._handle_drag. Leaving every zone holds the lane
## you started on rather than dropping it, so a finger that drifts slightly
## off the arrow mid-hold does not break the hold.
func _handle_drag(index: int, pos: Vector2) -> void:
	if not _touch_to_lane.has(index):
		return

	var new_lane: int = _lane_at(pos)
	var old_lane: int = _touch_to_lane[index]
	if new_lane < 0 or new_lane == old_lane:
		return

	_touch_to_lane[index] = new_lane
	_release_lane(old_lane)
	_press_lane(new_lane)

## The lane whose receptor zone contains `pos`, or -1.
func _lane_at(pos: Vector2) -> int:
	var zones: Dictionary = _lane_zones()
	for lane: int in zones:
		if (zones[lane] as Rect2).has_point(pos):
			return lane
	return -1

## Tap zones, one per lane, centred on each lane's receptor.
##
## The receptor position is the note handler's own global position: each
## Lane node is a zero-width Control sitting exactly where its static arrow
## is drawn (offset_left == offset_right in the song scenes), so its global
## position IS the arrow's centre. Recomputed per query rather than cached
## because Midscroll animates Player:anchor_left/anchor_right every frame -
## a cached rect would lag behind the arrows it is supposed to sit on.
##
## Zone size comes from the measured spacing between neighbouring lanes, so
## at scale 1.0 the zones tile edge to edge with no dead gap between them,
## whatever a given song's layout or the Note Layout setting does.
func _lane_zones() -> Dictionary:
	var zones: Dictionary = {}
	if note_controller == null or not is_instance_valid(note_controller):
		return zones

	var handlers: Dictionary = note_controller.get("note_handlers")
	if handlers == null:
		return zones

	var centres: Dictionary = {}
	for key: String in handlers:
		if not key.begins_with(LANE_ID_PREFIX):
			continue
		var handler: Object = handlers[key]
		if handler == null or not is_instance_valid(handler) or not (handler is Control):
			continue
		centres[key.trim_prefix(LANE_ID_PREFIX).to_int()] = (handler as Control).global_position

	var spacing: float = _measure_spacing(centres)
	var scale: float = clampf(Settings.lullaby_touch_note_hitbox_size, SIZE_SCALE_MIN, SIZE_SCALE_MAX)
	var extent: Vector2 = Vector2(spacing, spacing) * scale * 0.5
	for lane: int in centres:
		zones[lane] = Rect2((centres[lane] as Vector2) - extent, extent * 2.0)
	return zones

## Smallest horizontal gap between neighbouring receptors. Smallest rather
## than average so zones never overlap on an unevenly spaced layout.
func _measure_spacing(centres: Dictionary) -> float:
	var xs: Array = []
	for lane: int in centres:
		xs.append((centres[lane] as Vector2).x)
	if xs.size() < 2:
		return FALLBACK_SPACING
	xs.sort()
	var best: float = INF
	for i in range(1, xs.size()):
		best = minf(best, absf(xs[i] - xs[i - 1]))
	return best if best > 1.0 else FALLBACK_SPACING

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

func _press_lane(lane: int) -> void:
	var count: int = _lane_active_count.get(lane, 0)
	_lane_active_count[lane] = count + 1
	if count > 0:
		return

	_dispatch(lane, true)
	note_pressed.emit(lane)
	if Settings.lullaby_touch_haptics:
		Input.vibrate_handheld(HAPTIC_DURATION_MS)

func _release_lane(lane: int) -> void:
	var count: int = _lane_active_count.get(lane, 0)
	if count <= 0:
		return

	count -= 1
	if count > 0:
		_lane_active_count[lane] = count
		return

	_lane_active_count.erase(lane)
	_dispatch(lane, false)
	note_released.emit(lane)

## Same handler the lane hitbox emits into - see the class doc. Looked up
## by path rather than held as a reference because it is an autoload and
## this overlay is created and freed repeatedly as the setting changes.
func _dispatch(lane: int, pressed: bool) -> void:
	var handler: Node = get_node_or_null(^"/root/RubiconTouchInput")
	if handler != null and handler.has_method("handle_touch_input"):
		handler.call("handle_touch_input", lane, pressed)

func _release_all() -> void:
	for lane: int in _lane_active_count.keys():
		_dispatch(lane, false)
		note_released.emit(lane)
	_lane_active_count.clear()
	_touch_to_lane.clear()

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
	if visible or not _lane_active_count.is_empty():
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
	# with the mechanic's autoplay hits; the rule is shared with
	# SafetyLullabyTouchControls and both Chimera zones.
	_update_special_button_size()
	special_button.visible = started and LullabyShowcase.mechanic_controls_visible(autoplay)

## Re-derives the button's offsets from the Touch Note Hitbox Size
## setting, only when that scale actually changed (this runs every frame).
func _update_special_button_size() -> void:
	var scale: float = 0.5 + 0.5 * clampf(Settings.lullaby_touch_note_hitbox_size, SIZE_SCALE_MIN, SIZE_SCALE_MAX)
	if is_equal_approx(scale, _special_scale):
		return
	_special_scale = scale
	special_button.offset_right = -SPECIAL_BUTTON_GAP * scale
	special_button.offset_left = special_button.offset_right - SPECIAL_BUTTON_SIZE * scale
	special_button.offset_top = -SPECIAL_BUTTON_SIZE * 0.5 * scale
	special_button.offset_bottom = SPECIAL_BUTTON_SIZE * 0.5 * scale
