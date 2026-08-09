extends Node

## Applies the Rubicon "Mobile" settings section to whatever song scene is
## running.
##
## Same autoload pattern as lullaby_note_layout_applier.gd: hooks
## SceneChanger.scene_change_finished and Settings.applied, waits two frames
## (current_scene is only assigned on the frame after change_scene_to_packed
## runs), then walks the fresh scene. Each option maps onto knobs that
## already exist in the addon so no song scene has to know about them.
##
## The RubiconMobileControls instances join the "rubicon_mobile_controls"
## group in their own _ready(), so the three songs (and any future one) pick
## up hint/gradient/opacity without this script knowing node names. The
## pendulum mechanic hitbox is found by script path - only Safety Lullaby
## has one - and the pause button sits at the same
## UILayer/SongTouchControls/PauseButton path in every song.

const MECHANIC_SCRIPT_PATH := "res://addons/rubicon_mobile_controls/mechanic_touch_hitbox.gd"
const PAUSE_BUTTON_PATH := "UILayer/SongTouchControls/PauseButton"
const PENDULUM_SERVER_SCRIPT := "res://lullaby_mod/scripts/lullaby/mechanics/safety_lullaby/lullaby_pendulum_server.gd"
## Chimera's crawl/escape pad. A plain Control, not a Button, so the
## overlay's own "every visible Button is reserved" sweep cannot see it -
## it has to be handed over explicitly or a tap would drive the pad and
## hit a note at the same time.
const ESCAPE_DPAD_SCRIPT := "res://lullaby_mod/songs/chimera/scripts/chimera_escape_dpad.gd"
const TOUCH_OVERLAY_SCRIPT := "res://lullaby_mod/scripts/lullaby/settings/lullaby_touch_note_input.gd"
const MECHANIC_BUTTON_SCRIPT := "res://lullaby_mod/scripts/lullaby/settings/lullaby_mechanic_action_button.gd"
const CONTROLLER_PATH := "UILayer/GameUI/Player"
## The songs' CanvasLayer. The overlay has to live under it: a Control
## parented to the song root sits in the default canvas (layer 0), below
## UILayer (layer 1, and 6 in Monochrome), where UILayer/GameUI - a
## full-rect Control on the default MOUSE_FILTER_STOP - swallows every GUI
## touch first. Note tapping still worked there because it runs off
## _input(), but the overlay's own red mechanic Button is picked through
## GUI and so could never be pressed, and drew behind the whole UI.
const UI_LAYER_PATH := "UILayer"
const TOUCH_OVERLAY_GROUP := &"lullaby_touch_note_input"

## Height of the pendulum band per mechanic direction, as a fraction of the
## screen, matching the scene authoring (the top strip is 20% tall).
const MECHANIC_BAND := 0.2

## The centre direction keeps the same 20% band in the middle; lanes 0-1
## then fill the top 40% and lanes 2-3 the bottom 40%.
const MECHANIC_CENTER_BAND := 0.2

## The addon's own authored values, kept here so turning an option back on
## restores exactly what the scene shipped with instead of compounding.
const FILL_ALPHA := 0.03
const PRESSED_ALPHA := 0.16

## Flat mode's own pair. It used to reuse PRESSED_ALPHA for both, so with
## Gradient off a lane looked identical pressed and at rest - the setting
## quietly took the touch feedback away along with the gradient, which is
## not what its name says it does. The resting level stays where it was
## (a flat lane has to be readable without being touched); pressing now
## goes above it.
const FLAT_FILL_ALPHA := 0.16
const FLAT_PRESSED_ALPHA := 0.34
## The outline's own default alpha. It was left out of the opacity scaling,
## so at 0% the fills vanished and the outlines stayed at full strength -
## the setting visibly did not do what it says.
const OUTLINE_ALPHA := 0.35

func _ready() -> void:
	if SceneChanger.has_signal("scene_change_finished"):
		SceneChanger.scene_change_finished.connect(_on_scene_changed)
	if Settings.has_signal("applied"):
		Settings.applied.connect(_apply_when_scene_ready)

	# The first scene of a session is already up by the time this autoload
	# runs and no scene-change signal fires for it.
	_apply_when_scene_ready()

func _on_scene_changed(_path: String) -> void:
	_apply_when_scene_ready()

## Same two-frame wait as the note layout applier: current_scene is assigned
## the frame AFTER change_scene_to_packed runs, and a call_deferred() (or a
## one-frame wait) can still catch the outgoing scene or null.
func _apply_when_scene_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_to_current_scene()

func _apply_to_current_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	var touch_mode: bool = Settings.lullaby_mobile_control_mode == Settings.MobileControlMode.TOUCH

	# Idempotent: re-applying settings (or switching modes mid-session) must
	# never leave a stale overlay behind.
	_remove_touch_overlay()

	# Everything below this point is song-only. Settings.applied fires on
	# every single option the player touches in the console, so without this
	# the Collector's Shop would walk its (very large) whole node tree twice
	# per keypress looking for song nodes that cannot exist, and leave a
	# full-screen overlay running _process in every menu.
	var controller: Node = scene.get_node_or_null(CONTROLLER_PATH)
	if controller == null:
		return

	var opacity: float = clampf(float(Settings.lullaby_hitbox_opacity) / 100.0, 0.0, 1.0)
	var gradient: bool = Settings.lullaby_hitbox_gradient

	# Gradient on: a lane is nearly invisible at rest and fades in along its
	# own height, then lights up when touched. Gradient off: a flat, plainly
	# visible lane that still brightens under a finger. Either way pressing
	# does something, and Opacity scales all of it.
	var rest_alpha: float = FILL_ALPHA if gradient else FLAT_FILL_ALPHA
	var press_alpha: float = PRESSED_ALPHA if gradient else FLAT_PRESSED_ALPHA
	var fill := Color(1, 1, 1, clampf(rest_alpha * opacity, 0.0, 1.0))
	var pressed := Color(1, 1, 1, clampf(press_alpha * opacity, 0.0, 1.0))

	for control in get_tree().get_nodes_in_group(&"rubicon_mobile_controls"):
		if not is_instance_valid(control):
			continue
		# Touch mode hands note input to the overlay: the lane hitbox goes
		# inert (hidden, no input, holds released) via gameplay_touch_mode.
		control.gameplay_touch_mode = touch_mode
		if not touch_mode:
			control.show_outlines = Settings.lullaby_hitbox_hint
			control.gradient_fill = gradient
			control.fill_color = fill
			control.pressed_fill_color = pressed
			control.outline_color = Color(1, 1, 1, OUTLINE_ALPHA * opacity)

	var pause: Control = scene.get_node_or_null(PAUSE_BUTTON_PATH)
	if pause is Control:
		pause.visible = Settings.lullaby_show_pause_button

	# One walk for all three script-matched nodes: this runs on every
	# Settings.applied, and a song scene is big enough that three separate
	# find_children() sweeps were the most expensive thing here.
	var found: Dictionary = _find_song_nodes(scene)
	var mechanic: Control = found.get("mechanic")

	if touch_mode:
		# The pendulum plays through the round red button now, not the
		# full-width zone (which would sit on the notes and eat their taps).
		_disable_mechanic_hitbox(mechanic)
		_create_touch_overlay(scene, controller, found)
	else:
		# Switching back to Hitbox mid-session must undo the disable above.
		_restore_mechanic_hitbox(mechanic)
		_apply_mechanic_layout(mechanic)

func _apply_mechanic_layout(mechanic: Control) -> void:
	if mechanic == null:
		# No mechanic hitbox in this song (Monochrome/Chimera). Leave the
		# lane hitboxes exactly as their scenes ship them - full height.
		return

	var mobile: Control = null
	for control in get_tree().get_nodes_in_group(&"rubicon_mobile_controls"):
		if is_instance_valid(control):
			mobile = control
			break

	mechanic.anchor_left = 0.0
	mechanic.anchor_top = 0.0
	mechanic.anchor_right = 1.0
	mechanic.offset_left = 0.0
	mechanic.offset_right = 0.0

	match Settings.lullaby_mechanic_hitbox_direction:
		Settings.MechanicHitboxDirection.UP:
			mechanic.anchor_top = 0.0
			mechanic.anchor_bottom = MECHANIC_BAND
			mechanic.offset_top = 0.0
			mechanic.offset_bottom = 0.0
			mechanic.notch_corner = mechanic.NOTCH_TOP_RIGHT
			mechanic.notch_size = Vector2(190, 190)
			if mobile:
				mobile.hitbox_top_percent = MECHANIC_BAND
				mobile.hitbox_bottom_percent = 0.0
				mobile.hitbox_center_percent = 0.0
		Settings.MechanicHitboxDirection.BOTTOM:
			mechanic.anchor_top = 1.0 - MECHANIC_BAND
			mechanic.anchor_bottom = 1.0
			mechanic.offset_top = 0.0
			mechanic.offset_bottom = 0.0
			mechanic.notch_corner = mechanic.NOTCH_NONE
			mechanic.notch_size = Vector2.ZERO
			if mobile:
				mobile.hitbox_top_percent = 0.0
				mobile.hitbox_bottom_percent = MECHANIC_BAND
				mobile.hitbox_center_percent = 0.0
		Settings.MechanicHitboxDirection.CENTER:
			# A tall channel between the two lane pairs, not a horizon across
			# the screen: left | down | mechanic | up | right. The anchors set
			# above this match assume a full-width band, so both axes are
			# overridden here.
			mechanic.anchor_left = 0.5 - MECHANIC_CENTER_BAND * 0.5
			mechanic.anchor_right = 0.5 + MECHANIC_CENTER_BAND * 0.5
			mechanic.anchor_top = 0.0
			mechanic.anchor_bottom = 1.0
			mechanic.offset_top = 0.0
			mechanic.offset_bottom = 0.0
			mechanic.notch_corner = mechanic.NOTCH_NONE
			mechanic.notch_size = Vector2.ZERO
			if mobile:
				mobile.hitbox_top_percent = 0.0
				mobile.hitbox_bottom_percent = 0.0
				mobile.hitbox_center_percent = MECHANIC_CENTER_BAND

## Single pass for every node this script locates by script resource path
## (which keeps it independent of each song's node names): the pendulum
## hitbox and pendulum server, both Safety Lullaby only, and Chimera's
## escape D-pad. Returns {"mechanic": Control, "pendulum": Node,
## "escape_dpad": Control}, with missing entries simply absent.
func _find_song_nodes(scene: Node) -> Dictionary:
	var found: Dictionary = {}
	for node in scene.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script == null:
			continue
		match script.resource_path:
			MECHANIC_SCRIPT_PATH:
				found["mechanic"] = node as Control
			PENDULUM_SERVER_SCRIPT:
				found["pendulum"] = node
			ESCAPE_DPAD_SCRIPT:
				found["escape_dpad"] = node as Control
	return found

func _remove_touch_overlay() -> void:
	for node in get_tree().get_nodes_in_group(TOUCH_OVERLAY_GROUP):
		if is_instance_valid(node):
			node.queue_free()

## In Touch mode the pendulum is played through the round red button, so
## the full-width RubiconMechanicHitbox must go away. Hiding the hitbox
## alone is not enough: SafetyLullabyTouchControls polls
## `hitbox.visible = ...` every frame and would re-show it, so its
## controller's _process is stopped too. Every scene load re-runs this
## applier, so a later Hitbox-mode song starts from the scene's own state.
func _disable_mechanic_hitbox(mechanic: Control) -> void:
	if mechanic == null:
		return
	mechanic.visible = false
	var controller: Node = mechanic.get_parent()
	if controller != null and controller.has_method("set_process"):
		controller.set_process(false)

## Mirror of _disable_mechanic_hitbox: re-enables the mechanic hitbox
## controller's _process when the player switches back to Hitbox mode
## without leaving the song (otherwise the red zone would never show again
## in that scene).
func _restore_mechanic_hitbox(mechanic: Control) -> void:
	if mechanic == null:
		return
	var controller: Node = mechanic.get_parent()
	if controller != null and controller.has_method("set_process"):
		controller.set_process(true)

func _create_touch_overlay(scene: Node, controller: Node, found: Dictionary) -> void:
	var overlay_script: Script = load(TOUCH_OVERLAY_SCRIPT)
	if overlay_script == null:
		push_error("MobileControlsApplier: failed to load touch overlay script %s" % TOUCH_OVERLAY_SCRIPT)
		return
	var overlay: Control = overlay_script.new()
	overlay.name = "LullabyTouchNoteInput"
	# Full-rect so the overlay (and its right-centre special button, which
	# is anchored against the overlay's rect) covers the whole screen. Under
	# a CanvasLayer the anchorable rect is the viewport - the same rule the
	# MobileControls/SongTouchControls overlays already rely on.
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	overlay.note_controller = controller

	# The lane hitboxes already wire per-song HUD/gameover sources and their
	# own reserved zones; reuse the first one's so this script does not need
	# per-song paths.
	for control in get_tree().get_nodes_in_group(&"rubicon_mobile_controls"):
		if not is_instance_valid(control):
			continue
		overlay.default_hud = control.get("default_hud")
		overlay.gameover_source = control.get("gameover_source")
		var shared: Array = control.get("reserved_controls")
		if shared != null:
			for zone in shared:
				if zone is Control:
					overlay.reserved_controls.append(zone)
		break

	# Not a Button, so the overlay's automatic sweep cannot find it.
	var escape_dpad = found.get("escape_dpad")
	if escape_dpad is Control:
		overlay.reserved_controls.append(escape_dpad)

	overlay.mechanic_source = found.get("pendulum")

	var button_script: Script = load(MECHANIC_BUTTON_SCRIPT)
	if button_script == null:
		push_error("MobileControlsApplier: failed to load mechanic button script %s" % MECHANIC_BUTTON_SCRIPT)
	else:
		var button: Button = Button.new()
		button.set_script(button_script)
		button.name = "TouchSpecialButton"
		button.set("action", &"lullaby_special")
		button.visible = false
		# Anchors only - the offsets are the overlay's to own, derived from
		# the Touch Note Hitbox Size setting in _update_special_button_size()
		# before the button is ever shown. Authoring them here as well meant
		# two copies of the same geometry that only agreed by coincidence.
		button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		overlay.add_child(button)
		overlay.special_button = button

	# Under the song's CanvasLayer, not the scene root - see UI_LAYER_PATH.
	# Last child of UILayer puts it above the HUD for both drawing and GUI
	# picking, which is what the red mechanic button needs to be pressable.
	var parent: Node = scene.get_node_or_null(UI_LAYER_PATH)
	if parent == null:
		parent = scene
	# Added after the button so the overlay's _ready() (which runs when the
	# subtree enters the tree) already finds it among the reserved Buttons.
	parent.add_child(overlay)
