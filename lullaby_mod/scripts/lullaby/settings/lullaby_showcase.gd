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
## Two kinds of control exist and they do not share a base class, so this is
## duck-typed rather than typed:
##
##   RubiconActionButton (Chimera's heartbeat and picture-taking) has its own
##   _flash(), which already handles the tween-collision case, so that is
##   preferred and `seconds` is ignored - the button owns its own timing.
##
##   RubiconMechanicHitbox (safety_lullaby's pendulum) has no flash of its
##   own and is driven through _handle_touch(index, pressed) with a timed
##   release, the same assumption LullabyShowcaseNoteSync already makes about
##   _press_lane.
static func flash_control(control: Node, tree: SceneTree, touch_index: int,
		seconds: float) -> void:
	if not is_active():
		return
	if control == null or not is_instance_valid(control):
		return

	if control.has_method("_flash"):
		control.call("_flash")
		return

	if not control.has_method("_handle_touch") or tree == null:
		return

	control.call("_handle_touch", touch_index, true)
	var timer: SceneTreeTimer = tree.create_timer(seconds)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(control):
			control.call("_handle_touch", touch_index, false))
