extends RefCounted
## Referenced via preload(), not class_name: the global script class cache
## only updates after the editor rescans the project, which headless test
## runs don't trigger, causing "Identifier not declared" false negatives.
## Ports util/GenUtil.hx's playUISound — the only piece of GenUtil this port
## currently needs, shared between hq_message_window.gd and intro_screen.gd
## instead of duplicating the sound-file lookup in both.

## [base filename, variant count (0 = no numeric suffix)], one entry per
## GenUtil.hx playUISound() case.
const UI_SOUNDS := {
	"move": ["ui_move", 3],
	"confirm": ["ui_confirm", 3],
	"confirmbad": ["ui_confirm_bad", 0],
	"error": ["ui_error", 0],
	"back": ["ui_back", 2],
	"open": ["ui_open", 2],
	"close": ["ui_close", 2],
	"on": ["ui_tick_true", 0],
	"off": ["ui_tick_false", 0],
}

static func play_ui_sound(caller: Node, type: String) -> void:
	if not UI_SOUNDS.has(type):
		return
	var base: String = UI_SOUNDS[type][0]
	var count: int = UI_SOUNDS[type][1]
	var suffix := "" if count == 0 else str(randi() % count + 1)
	var path := "res://holyquintet_mod/source/sounds/ui/%s%s.ogg" % [base, suffix]
	if not ResourceLoader.exists(path):
		return
	# A fresh, self-freeing player per call, parented to the tree root
	# rather than the caller: the real FlxSound calls all set
	# .persist = true specifically so these UI sounds survive whatever
	# state switch they themselves trigger (e.g. 'close' firing right as
	# the state changes) — a child of the caller would be freed mid-playback.
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	caller.get_tree().root.add_child.call_deferred(player)
	player.finished.connect(player.queue_free)
	player.play.call_deferred()
