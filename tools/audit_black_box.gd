extends SceneTree

## Every animation track in Chimera that touches the full-screen black rect,
## with its keyframes.
##
## The device census caught BlackBoxofAwesomeness - a full-rect ColorRect at
## the scene root - measured at coverage 1.00 while the song was running. The
## scene authors it visible=false with color.a=0, so something animated it
## opaque and left it there. That matches the report: a black graphic in front
## of everything from the moment the sprite plane starts.
##
## This is deliberately a dump rather than a verdict. The last two theories
## about this bug were both wrong - the results screen turned out to be a bare
## Control that paints nothing, and its Vingette a gradient that never reaches
## opaque - and both looked convincing until the actual values were read.
##
## Run with:
##   godot --headless --path . --script tools/audit_black_box.gd

const SCENE := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
const TARGET := "BlackBoxofAwesomeness"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("FALLO: no pude cargar %s" % SCENE)
		quit(1)
		return

	var state: SceneState = packed.get_state()
	var players: Array = []
	for i in state.get_node_count():
		if state.get_node_type(i) == &"AnimationPlayer":
			players.append(i)

	print("AnimationPlayers en la escena: %d" % players.size())
	print("")

	var found: int = 0
	for i in players:
		var node_name: String = str(state.get_node_name(i))
		for p in state.get_node_property_count(i):
			var prop: String = str(state.get_node_property_name(i, p))
			if not prop.begins_with("libraries/"):
				continue
			var library: Variant = state.get_node_property_value(i, p)
			if library is AnimationLibrary:
				found += _scan_library(node_name, prop, library)

	print("")
	if found == 0:
		print("ninguna pista toca %s" % TARGET)
	else:
		print("%d pista(s) en total" % found)
	quit(0)

func _scan_library(player: String, slot: String, library: AnimationLibrary) -> int:
	var hits: int = 0
	for anim_name in library.get_animation_list():
		var anim: Animation = library.get_animation(anim_name)
		for t in anim.get_track_count():
			var path: String = str(anim.track_get_path(t))
			if not path.contains(TARGET):
				continue

			hits += 1
			var mode: int = anim.value_track_get_update_mode(t) if anim.track_get_type(t) == Animation.TYPE_VALUE else -1
			print("%s [%s] %s  len=%.2fs" % [player, slot.trim_prefix("libraries/"), anim_name, anim.length])
			print("   %s   update=%s  keys=%d" % [path, _mode_name(mode), anim.track_get_key_count(t)])

			for k in anim.track_get_key_count(t):
				var at: float = anim.track_get_key_time(t, k)
				var value: Variant = anim.track_get_key_value(t, k)
				print("      %6.2fs  %s" % [at, _describe(value)])

			# The value the track leaves behind, which is what matters for a
			# rect that is still on screen after the animation ends.
			var last: Variant = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
			var verdict: String = _verdict(path, last)
			if not verdict.is_empty():
				print("   -> %s" % verdict)
			print("")
	return hits

func _verdict(path: String, last: Variant) -> String:
	if path.ends_with(":visible") and last is bool and last:
		return "TERMINA VISIBLE"
	if path.ends_with(":color") and last is Color and last.a >= 0.95:
		return "TERMINA OPACO (color.a=%.2f)" % last.a
	if path.ends_with(":modulate") and last is Color and last.a >= 0.95:
		return "termina con modulate.a=%.2f" % last.a
	return ""

func _describe(value: Variant) -> String:
	if value is Color:
		return "Color(%.2f, %.2f, %.2f, a=%.2f)" % [value.r, value.g, value.b, value.a]
	return str(value)

func _mode_name(mode: int) -> String:
	match mode:
		0: return "CONTINUOUS"
		1: return "DISCRETE"
		2: return "CAPTURE"
		_: return "-"
