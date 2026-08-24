class_name LullabyShowcase

## The one place that knows what Showcase Mode means for on-screen controls.
##
## Showcase Mode forces autoplay (lullaby_song_settings.gd), and every
## mechanic's touch control hides itself while its mechanic is on autoplay -
## which is right for the debug "Autoplay?" toggle, where nobody is watching
## the controls, and wrong for a showcase, where the controls flashing along
## with the automatic play is the entire point.
##
## The rule is one line, so it was written out at each call site and then only
## fixed at one of them: safety_lullaby's pendulum kept its hitbox, while
## Chimera's heartbeat and picture-taking silently vanished for the whole of a
## showcase run. Four copies of a one-line rule is exactly the shape of thing
## that drifts, so it lives here now.
##
## Deliberately NOT applied to Monochrome's typing controls. That "control" is
## a focused LineEdit whose only job is to make Android raise the system
## keyboard - showing it during a showcase would put the OS keyboard over the
## song. See monochrome_typing_touch_controls.gd.

## Static-only; there is no instance to make.
static func is_active() -> bool:
	return Settings.lullaby_showcase_mode

## Whether a mechanic's touch control should be on screen, given whether that
## mechanic is currently autoplaying. Callers still AND in their own
## conditions (mechanic started, HUD visible, not paused).
static func mechanic_controls_visible(autoplay: bool) -> bool:
	return not autoplay or is_active()

## Lights a mechanic's control up on an automatic hit, the way a real tap
## would. Safe to call when not in showcase - it does nothing - so callers do
## not need to guard it themselves.
##
## Three kinds of control exist and they do not share a base class, so this is
## duck-typed rather than typed:
##
##   Anything with its own _flash() - RubiconActionButton, ChimeraEscapeDPad -
##   owns its timing, so that is preferred and `seconds` is ignored.
##
##   RubiconMechanicHitbox (safety_lullaby's pendulum) has no flash of its
##   own and is driven through _handle_touch(index, pressed) with a timed
##   release, the same assumption LullabyShowcaseNoteSync already makes about
##   _press_lane.
##
##   **Any other CanvasItem**, which is the case that was missing and is why
##   Chimera's heartbeat button "no se prende" in a showcase. This function's
##   own docstring used to claim the heartbeat and picture-taking zones were
##   RubiconActionButtons; they are not. Both scenes wire a plain `Button`:
##
##       [node name="Hitbox" type="Button" parent="UILayer/HeartbeatTouchZone"]
##       [node name="Hitbox" type="Button" parent="UILayer/PictureTakingTouchZone"]
##
##   A plain Button has neither `_flash` nor `_handle_touch`, so both branches
##   above fell through and this returned having done nothing at all - silently,
##   on every automatic beat of every showcase run. The fallback pulses
##   `modulate`, which needs no API beyond CanvasItem and therefore cannot be
##   wrong about a class again.
static func flash_control(control: Node, tree: SceneTree, touch_index: int,
		seconds: float) -> void:
	if not is_active():
		return
	if control == null or not is_instance_valid(control):
		return

	if control.has_method("_flash"):
		control.call("_flash")
		return

	if control.has_method("_handle_touch") and tree != null:
		control.call("_handle_touch", touch_index, true)
		var timer: SceneTreeTimer = tree.create_timer(seconds)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(control):
				control.call("_handle_touch", touch_index, false))
		return

	_pulse(control as CanvasItem, seconds)

## How bright the fallback pulse goes. The same 1.6 action_button.gd's own
## _flash() uses, so a plain Button and a RubiconActionButton read as the same
## event rather than as two different ones.
const PULSE_BRIGHTNESS := 1.6

## Brightens a CanvasItem and lets it fall back, killing any pulse already
## running on it.
##
## Killed rather than left to race, for the reason action_button.gd already
## records about its own flash: two tweens writing `modulate` on the same frame
## leave whichever ran last in charge, so a fast repeat can strand the control
## on the bright colour instead of settling.
static func _pulse(item: CanvasItem, seconds: float) -> void:
	if item == null:
		return

	var previous: Tween = item.get_meta(&"lullaby_showcase_pulse", null) as Tween
	if previous != null and previous.is_valid():
		previous.kill()

	item.modulate = Color(PULSE_BRIGHTNESS, PULSE_BRIGHTNESS, PULSE_BRIGHTNESS, item.modulate.a)
	var tween: Tween = item.create_tween()
	tween.tween_property(item, "modulate", Color(1.0, 1.0, 1.0, item.modulate.a),
		maxf(seconds, 0.05)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	item.set_meta(&"lullaby_showcase_pulse", tween)
