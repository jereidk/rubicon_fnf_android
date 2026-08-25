class_name LullabyNoMechanics

## One place to ask whether the player turned the songs' mechanics off.
##
## Why a helper and not `Settings.lullaby_no_mechanics` written three times.
## The three mechanics that read this live in three different songs and are
## reached from three different places - `HeartbeatController.initialize()`,
## `TypingChallenge.active`'s setter and `LullabyPendulumServer`'s start - and
## two of them are also instanced by benches and by the guard suite, where the
## Settings autoload does not exist. A bare `Settings.lullaby_no_mechanics`
## there is not a false answer, it is a crash on a null autoload, which turns
## an opt-in cheat into a broken test run. The same defensive shape
## `LullabyCutsceneVideo._wanted()` already uses, for the same reason.
##
## Absent Settings the answer is false: mechanics ON. The safe default is the
## game as authored, so a lookup that fails can never silently strip content.
##
## What "off" means is documented on the setting itself in menus/settings.gd:
## the mechanics are switched on and off by each song's own timeline at fixed
## times, never by the player reaching something, so declining to switch on is
## enough. Nothing needs auto-completing and nothing waits.
static func wanted() -> bool:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return false

	var settings: Node = loop.root.get_node_or_null(^"/root/Settings")
	if settings == null:
		return false

	return bool(settings.get(&"lullaby_no_mechanics"))
