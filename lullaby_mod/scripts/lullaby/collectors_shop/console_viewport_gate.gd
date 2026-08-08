extends VisibleOnScreenNotifier3D

## Drives the console SubViewport's update mode from whether the TV is on
## screen, and records every switch in the diagnostics log.
##
## The behaviour is what the scene already did through two direct
## screen_entered/screen_exited -> set_update_mode connections; this only
## takes ownership of them so the switches can be counted.
##
## Why measure instead of just changing it: the shop's periodic 70-150ms
## spikes were suspected to be this gate re-rendering a 640x480 viewport
## on each crossing, but the log does not support that on its own. Ten
## separate spikes carry byte-identical render counters
## (draw=80 prims=13389 objs=267), and a normal 30fps heartbeat carries
## those exact numbers too - so the same GPU work is present with and
## without a spike. The viewport being on only adds ~10 draw calls and
## ~700 primitives, which is far too little to explain a 4x frame.
##
## What is still plausible is FLAPPING: the notifier's AABB is 0.002 units
## thick, so while the camera pans the TV can cross the frustum edge
## repeatedly, and each DISABLED -> ALWAYS switch forces a full re-render.
## That would not show up in any per-frame counter. The MARK lines below
## make it visible: if the next log shows switches clustering around the
## spike timestamps, the gate is implicated; if switches are rare and the
## spikes continue between them, it is ruled out and the search moves on.
##
## What the log DID say, once gpu= was compared against frame=: the shop's
## spikes hold gpu at a flat 13.5ms while the frame runs 68-141ms. That
## number only covers the MAIN viewport - RenderingServer's measured render
## time is per-viewport - so every SubViewport in the scene is GPU work the
## log cannot see. The console carries the big one: console_bg's
## SubViewport is 1440x1080 with own_world_3d, a WorldEnvironment with fog
## and a DirectionalLight3D, i.e. 1.56Mpx of 3D rendered every frame
## against the main viewport's 800x360 (scale 0.50). It is authored inside
## a Control that is never hidden, so it renders for the whole shop
## session - including while the player is free-looking away from the TV
## and this gate has the OUTER viewport disabled.
##
## Hence background_container below. Note that setting
## render_target_update_mode on a SubViewport owned by a SubViewportContainer
## does not work: the container overwrites it from its own
## is_visible_in_tree() on every visibility notification (ALWAYS when
## visible, DISABLED when not), so an authored value is inert and a manual
## set survives only until the next visibility change. Verified against
## 4.7.1. Toggling the container's visibility is therefore the supported
## way to switch a nested viewport off, and it is what this does.
##
## Only console_bg's container is managed here, deliberately. The Home and
## Credits containers are already gated correctly by the TabContainer
## hiding their tabs, and blanket-showing containers is exactly what made
## the reverted shader prewarm open the console on a screen the player
## never chose (see CLAUDE.md).

## SubViewport.UpdateMode. Named here rather than passed as the bare 4/0
## the scene connections used, which said nothing about intent.
const UPDATE_DISABLED := 0
const UPDATE_ALWAYS := 4

@export var console_viewport: SubViewport

## The SubViewportContainer wrapping console_bg's 3D background. Hidden
## while the TV is off screen so its nested viewport stops rendering.
@export var background_container: Control

var _switches: int = 0
var _last_switch_msec: int = 0

func _ready() -> void:
	screen_entered.connect(_on_screen_entered)
	screen_exited.connect(_on_screen_exited)

func _on_screen_entered() -> void:
	_set_mode(UPDATE_ALWAYS, "on")

func _on_screen_exited() -> void:
	_set_mode(UPDATE_DISABLED, "off")

func _set_mode(mode: int, label: String) -> void:
	if console_viewport == null or not is_instance_valid(console_viewport):
		return

	console_viewport.render_target_update_mode = mode

	# The outer viewport keeps its last rendered texture while disabled, so
	# the TV screen still shows the console with the background on it; the
	# frame it comes back, the outer viewport redraws against the nested
	# texture's own last content, which is that same image. Nothing blanks.
	if background_container != null and is_instance_valid(background_container):
		background_container.visible = mode == UPDATE_ALWAYS

	_switches += 1
	var now: int = Time.get_ticks_msec()
	var gap: int = now - _last_switch_msec if _last_switch_msec > 0 else -1
	_last_switch_msec = now

	# Autoload, but the shop is opened directly from the editor often enough
	# that this should not hard-depend on it.
	var log_node: Node = get_node_or_null(^"/root/DiagnosticsLog")
	if log_node != null and log_node.has_method("mark"):
		log_node.call("mark", "console viewport %s (switch #%d, %s since last)" % [
			label, _switches, "%dms" % gap if gap >= 0 else "first",
		])
