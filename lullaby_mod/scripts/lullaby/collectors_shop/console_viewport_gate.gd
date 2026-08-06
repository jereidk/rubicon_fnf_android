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

## SubViewport.UpdateMode. Named here rather than passed as the bare 4/0
## the scene connections used, which said nothing about intent.
const UPDATE_DISABLED := 0
const UPDATE_ALWAYS := 4

@export var console_viewport: SubViewport

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
