extends SceneTree

## Diffs a scene in this port against the PC mod's copy inside Lullaby.pck,
## without instantiating either - SceneState reads the authored node list and
## property values, and any AnimationLibrary found on a node is expanded to
## per-animation track paths.
##
## This is the tool for "was this a porting mistake or was it always like
## this": our fork is not the mod's Rubicon, so a property our engine renamed
## or dropped is discarded in silence, along with every animation track
## targeting it. Comparing authored state against the pck is the only way to
## see what went missing.
##
##   godot --headless --script tools/diff_pck_scene.gd -- <port_path> <pc_path>
##
## Output is one "OUT <SIDE> ..." line per fact, meant to be diffed by a
## script rather than read directly - see the comparison in the same commit.

const PCK := "res://lullaby_mod/original_pck/Lullaby.pck"

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("OUT usage: -- <port_path> <pc_path>")
		quit()
		return

	if not ProjectSettings.load_resource_pack(PCK, false):
		print("OUT could not mount pck")
		quit()
		return

	var port_path: String = args[0]
	var pc_path: String = args[1]
	if not ResourceLoader.exists(pc_path):
		print("OUT pc path missing: ", pc_path)
		quit()
		return

	_dump("PC", load(pc_path))
	_dump("PORT", load(port_path))
	quit()

func _dump(tag: String, scene: PackedScene) -> void:
	if scene == null:
		print("OUT ", tag, " load failed")
		return

	var state: SceneState = scene.get_state()
	print("OUT ", tag, " nodes=", state.get_node_count())

	for i in state.get_node_count():
		var path: String = str(state.get_node_path(i))
		print("OUT ", tag, " node ", path, " [", state.get_node_type(i), "]")

		for p in state.get_node_property_count(i):
			var pname: StringName = state.get_node_property_name(i, p)
			var value: Variant = state.get_node_property_value(i, p)

			if value is AnimationLibrary:
				_dump_library(tag, path, value)
			elif value is Animation:
				_dump_animation(tag, path + " " + str(pname), value)
			elif value is Resource:
				# Resources print as an object id that changes every run, which
				# would show up as a difference on every single line.
				print("OUT ", tag, "   ", pname, " = <", value.get_class(), " ",
					value.resource_path, ">")
			else:
				print("OUT ", tag, "   ", pname, " = ", value)

func _dump_library(tag: String, owner_path: String, lib: AnimationLibrary) -> void:
	var names: Array = []
	for n in lib.get_animation_list():
		names.append(str(n))
	names.sort()
	print("OUT ", tag, "   library on ", owner_path, " anims=", names.size())
	for n in names:
		_dump_animation(tag, owner_path + " " + n, lib.get_animation(StringName(n)))

func _dump_animation(tag: String, label: String, anim: Animation) -> void:
	if anim == null:
		return
	print("OUT ", tag, "   anim ", label, " len=", "%.4f" % anim.length,
		" tracks=", anim.get_track_count())
	for t in anim.get_track_count():
		print("OUT ", tag, "     ", label, " t", t, " type=", anim.track_get_type(t),
			" path=", anim.track_get_path(t))
