extends Node

## Reads back what a real game scene actually did, without rendering it.
##
## The sibling of scene_shot.gd and the one to reach for first: it answers "is
## this node visible right now, and is it still in the tree" in seconds, where
## the renderer takes minutes a frame under software GL. Every question of the
## form "does the scene really leave X on" is this, not a screenshot.
##
##   godot --headless --path . res://tools/harness/scene_probe.tscn \
##     -- res://lullaby_mod/songs/chimera/sng_chimera.tscn precache UILayer/NTSC
##
## Arguments after `--`: the scene, then `precache` to make PreloadCamera take
## its shipped path (it reads SceneChanger.awaiting_manual_end in _ready() and
## frees itself on the spot when it is false), then any number of node paths to
## report. It prints them once after _ready and again after the precache.
##
## Run it as a SCENE, as above - not with `--script`. A SceneTree script gets
## no autoloads, so `Settings` reads null, anything gated on a settings value
## takes its default branch and the scene answers a question you did not ask.
## That mistake made NTSC look like it was being freed when it is not.
##
## `advance()` and not `seek()` for the same reason the tests do it: `precache`
## dispatches the SequencePlayer's RESET through an `animation` track, and a
## clip stepped with seek() is assigned and never advanced.
var _scene_path: String = "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
var _precache: bool = false
var _watch: PackedStringArray = PackedStringArray()

func _ready() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() > 0: _scene_path = argv[0]
	for i in range(1, argv.size()):
		if argv[i] == "precache": _precache = true
		else: _watch.append(argv[i])

	var s: Node = get_node_or_null(^"/root/Settings")
	print("OUT Settings=%s post_processing=%s disable_shader_effects=%s preset=%s" % [
		s != null,
		s.get("graphics_post_processing") if s else "-",
		s.get("graphics_disable_shader_effects") if s else "-",
		s.get("graphics_quality_preset") if s and "graphics_quality_preset" in s else "-"])

	var changer: Node = get_node_or_null(^"/root/SceneChanger")
	if _precache and changer != null and "awaiting_manual_end" in changer:
		changer.set("awaiting_manual_end", true)

	var scene: Node = (load(_scene_path) as PackedScene).instantiate()
	add_child(scene)
	for i in 5: await get_tree().process_frame
	_dump(scene, "tras _ready")

	if _precache:
		var p: AnimationPlayer = scene.get_node_or_null(^"PreloadCamera/AnimationPlayer")
		if p != null:
			p.play(&"precache")
			for _i in 60:
				p.advance(1.0 / 60.0)
				await get_tree().process_frame
		_dump(scene, "tras precache")
	get_tree().quit()

func _dump(scene: Node, when: String) -> void:
	print("OUT === %s ===" % when)
	for path in _watch:
		var n: Node = scene.get_node_or_null(NodePath(path))
		if n == null:
			print("OUT %-52s LIBERADO/AUSENTE" % path); continue
		print("OUT %-52s visible=%-5s en_arbol=%s" % [path, n.get("visible"), n.is_visible_in_tree()])
