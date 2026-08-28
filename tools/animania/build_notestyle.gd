# Builds the amtake-base note style: the SpriteFrames and AnimationLibraries behind the
# receptors, the notes and the hold trails, plus Lane and Note scenes that use them.
#
# Rubicon names a lane animation `<dir>_lane_<neutral|press|confirm>` and a note animation
# `<dir>_note_<neutral|hold|tail>`, and Lane.tscn / Note.tscn drive those names through
# AnimationTree state machines keyed on `lane_id` and `lane_state`. Animania names the same
# things `LeftStatic` / `left press` / `left confirm` and colours its notes purple, blue,
# green, red. So the whole port is a rename plus a set of regions - the state machines,
# the trail geometry and the hit logic are all Rubicon's and stay untouched.
#
# The frames are built as AtlasTextures over the mod's own PNGs rather than by repacking
# them into a Rubicon-shaped sheet. One SpriteFrames can hold regions from several atlases,
# so notes.png and note-holds.png live side by side in one resource, and every region here
# comes straight out of the mod's XML instead of out of a new sheet nobody can diff.
#
#   godot --headless --path . --script tools/animania/build_notestyle.gd
extends SceneTree

const SOURCE := "res://animania_mod/source/images/notestyle"
const OUT := "res://animania_mod/notestyle"

# amtake-base.json's `data` blocks, which is where the colour-to-lane mapping is stated.
const NOTE_COLOURS := {"left": "purple", "down": "blue", "up": "green", "right": "red"}

# The strum prefixes, exactly as the JSON spells them - capitalised on Static and
# lowercase with a space on the other two.
const LANE_PREFIXES := {
	"neutral": "%sStatic", "press": "%s press", "confirm": "%s confirm",
}

# note-holds.png has no XML: it is eight 64x87 cells with 2-3px gutters, in colour order
# purple, blue, green, red, and within each colour the body first and the tapering end
# second. Read off the image, not assumed - the even cells are opaque top to bottom
# (1344 opaque pixels at each end) and the odd ones taper to 64 at the bottom.
const HOLD_CELLS := [1, 67, 133, 199, 265, 331, 397, 463]
const HOLD_SIZE := Vector2(64.0, 87.0)
const DIRECTIONS := ["left", "down", "up", "right"]

## The trail graphics are not SpriteFrames: Note.tscn draws them with TextureRects over
## eight AtlasTexture sub-resources. These are the funkin regions each one currently holds,
## paired with the amtake cell that replaces it. Confirmed against funkin_notes.xml - the
## scene's rects are the XML's inset by a pixel - rather than matched by eye.
const TRAIL_REGIONS := [
	["Rect2(312, 317, 41, 50)", "Rect2(1, 0, 64, 87)"],    # left hold
	["Rect2(69, 317, 63, 50)", "Rect2(67, 0, 64, 87)"],    # left tail
	["Rect2(267, 317, 41, 50)", "Rect2(133, 0, 64, 87)"],  # down hold
	["Rect2(3, 317, 63, 50)", "Rect2(199, 0, 64, 87)"],    # down tail
	["Rect2(318, 54, 41, 50)", "Rect2(265, 0, 64, 87)"],   # up hold
	["Rect2(201, 317, 63, 50)", "Rect2(331, 0, 64, 87)"],  # up tail
	["Rect2(318, 2, 41, 50)", "Rect2(397, 0, 64, 87)"],    # right hold
	["Rect2(135, 317, 63, 50)", "Rect2(463, 0, 64, 87)"],  # right tail
]

## The four Tail TextureRects have no expand_mode, so their minimum size is their texture's
## size, and a Control's rect is the larger of its anchored size and its minimum. funkin's
## tail graphic happens to be 64x50 and the trail is 50 thick, so the two agree by accident;
## amtake's is 64x87, and the cap came out 87 thick against a 50-thick trail, sticking out
## past both edges. IGNORE_SIZE drops the minimum to zero and lets the anchors decide, which
## is what the trail body already does.
const TAIL_EXPAND := [
	["texture = SubResource(\"AtlasTexture_aha53\")",
		"texture = SubResource(\"AtlasTexture_aha53\")\nexpand_mode = 1"],
	["texture = SubResource(\"AtlasTexture_5p607\")",
		"texture = SubResource(\"AtlasTexture_5p607\")\nexpand_mode = 1"],
	["texture = SubResource(\"AtlasTexture_ajgpx\")",
		"texture = SubResource(\"AtlasTexture_ajgpx\")\nexpand_mode = 1"],
	["texture = SubResource(\"AtlasTexture_h658e\")",
		"texture = SubResource(\"AtlasTexture_h658e\")\nexpand_mode = 1"],
]

const EFFECTS_SCRIPT := "res://animania_mod/scripts/lane_effects.gd"

const LANE_SOURCE := "res://resources/levels/ui/funkin/mania/Lane.tscn"
const NOTE_SOURCE := "res://resources/levels/ui/funkin/mania/Note.tscn"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var lanes: SpriteFrames = _build_lanes()
	_save_pair(lanes, "amtake_lanes")

	var notes: SpriteFrames = _build_notes()
	_save_pair(notes, "amtake_notes")

	var effects: SpriteFrames = _build_effects()
	_save_pair(effects, "amtake_effects")

	_build_scenes()
	quit(0)


## The two scenes are produced by rewriting the funkin ones rather than by rebuilding them.
## Everything that makes them work - the AnimationTree state machines keyed on `lane_id`
## and `lane_state`, the trail masking, the hit logic - is Rubicon's, and repacking it by
## hand would be a large diff to say "the art is different". So the transform is exactly
## three resource paths and eight regions, and anything it fails to find is a hard error
## rather than a silent no-op.
func _build_scenes() -> void:
	# The Lane also gains the hit splash and the hold cover, which Rubicon has no slot for.
	# They go on the note STYLE rather than on the level, because that is what they are:
	# amtake-base.json turns them on and gives them their scales and offsets.
	var lane_extras: String = """
[node name="Effects" type="Node2D" parent="." node_paths=PackedStringArray("handler")]
script = ExtResource("5_fx")
effects = ExtResource("6_fx")
handler = NodePath("..")
"""
	var lane_header: String = (
		'[ext_resource type="Script" path="%s" id="5_fx"]\n' % EFFECTS_SCRIPT
		+ '[ext_resource type="SpriteFrames" path="%s/amtake_effects_frames.tres" id="6_fx"]'
			% OUT)

	_rewrite(LANE_SOURCE, "%s/Lane.tscn" % OUT, [
		["res://assets/levels/ui/funkin/mania/funkin_lanes_frames.tres",
			"%s/amtake_lanes_frames.tres" % OUT],
		["res://assets/levels/ui/funkin/mania/funkin_lanes_library.tres",
			"%s/amtake_lanes_library.tres" % OUT],
	], lane_header, lane_extras)

	# Order matters: the resource PATHS go first, then the library key. The key rename
	# would otherwise rewrite the middle of
	# "res://assets/levels/ui/funkin/mania/funkin_notes_library.tres" and leave the path
	# pointing at a file that does not exist in a directory that does.
	var note_swaps: Array = [
		["res://assets/levels/ui/funkin/mania/funkin_notes.png",
			"%s/note-holds.png" % SOURCE],
		["res://assets/levels/ui/funkin/mania/funkin_notes_frames.tres",
			"%s/amtake_notes_frames.tres" % OUT],
		["res://assets/levels/ui/funkin/mania/funkin_notes_library.tres",
			"%s/amtake_notes_library.tres" % OUT],
		# The library KEY, not a path: Note.tscn mounts the library as `funkin_notes_library`
		# and its animation-track clips are spelled "funkin_notes_library/<anim>". Renaming
		# the key without the clips would silently break every direction switch, so both go
		# in one swap - and the result is a scene with no "funkin" left in it, which is
		# what the guard checks for.
		["funkin_notes_library", "amtake_notes_library"],
	]
	note_swaps.append_array(TRAIL_REGIONS)
	note_swaps.append_array(TAIL_EXPAND)
	_rewrite(NOTE_SOURCE, "%s/Note.tscn" % OUT, note_swaps)


func _rewrite(from: String, to: String, swaps: Array, header: String = "",
		extras: String = "") -> void:
	var text: String = FileAccess.get_file_as_string(from)
	if text.is_empty():
		push_error("no se pudo leer %s" % from)
		quit(1)
		return

	for swap: Array in swaps:
		if not text.contains(swap[0]):
			push_error("%s no contiene %s" % [from, swap[0]])
			quit(1)
			return
		text = text.replace(swap[0], swap[1])

	if not header.is_empty():
		# After the last ext_resource, so the ids the extra nodes reference are declared
		# before anything uses them.
		var last: int = text.rfind("[ext_resource")
		var line_end: int = text.find("\n", last)
		text = text.insert(line_end + 1, header + "\n")

	if not extras.is_empty():
		text += extras

	# A uid= beside a path= WINS, so every swapped ext_resource line has to lose its uid or
	# Godot loads the funkin resource the new path was meant to replace. This caught
	# note-holds.png, which lives outside the output directory and kept funkin_notes.png's
	# uid through the first version of this - a swap that changed the path and nothing else.
	var lines: PackedStringArray = text.split("\n")
	for i: int in lines.size():
		if not lines[i].begins_with("[ext_resource") \
				or not lines[i].contains("res://animania_mod"):
			continue
		var uid_start: int = lines[i].find(" uid=\"")
		if uid_start < 0:
			continue
		var uid_end: int = lines[i].find("\"", uid_start + 6)
		lines[i] = lines[i].substr(0, uid_start) + lines[i].substr(uid_end + 1)

	# The scene's own uid has to go too: two scenes cannot claim the same one.
	if lines[0].begins_with("[gd_scene") and lines[0].contains("uid="):
		var uid_start: int = lines[0].find(" uid=\"")
		var uid_end: int = lines[0].find("\"", uid_start + 6)
		lines[0] = lines[0].substr(0, uid_start) + lines[0].substr(uid_end + 1)

	var file: FileAccess = FileAccess.open(to, FileAccess.WRITE)
	if file == null:
		push_error("no se pudo escribir %s" % to)
		quit(1)
		return
	file.store_string("\n".join(lines))
	file.close()
	print("OUT reescrito %s -> %s (%d sustituciones)" % [
		from.get_file(), to, swaps.size()])


func _sparrow(png: String) -> SpriteFrames:
	var data := SparrowImporterSpriteData.new()
	data.texture = load(png)
	data.atlas_path = png.get_basename() + ".xml"
	data.fps = 24
	data.loop = false
	# sparrow.gd carries `last_frame` across animation boundaries and crashes when an
	# animation's first frame repeats the previous animation's last one - see
	# tools/animania/build_icons.gd. The effect atlases hit it; the note and lane ones do
	# not, but nothing here relies on held frames, so it is off for all of them.
	data.use_frame_duration = false
	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	return importer.convert_sprite([data])


## The importer exposes an `anim_aliases` dictionary that looks like it would do this, but
## it does not work: sparrow.gd computes the alias into a local and then writes
## `frame.anim_name = indexless_anim`, throwing the alias away. Renaming afterwards avoids
## editing vendored addon code for it.
func _rename(frames: SpriteFrames, from: String, to: String) -> void:
	if not frames.has_animation(from):
		push_error("no existe la animacion %s" % from)
		quit(1)
		return
	frames.rename_animation(from, to)


func _build_lanes() -> SpriteFrames:
	var frames: SpriteFrames = _sparrow("%s/strums.png" % SOURCE)
	for direction: String in DIRECTIONS:
		for state: String in LANE_PREFIXES:
			var prefix: String = LANE_PREFIXES[state] % (
				direction.capitalize() if state == "neutral" else direction)
			_rename(frames, prefix, "%s_lane_%s" % [direction, state])
	return frames


func _build_notes() -> SpriteFrames:
	var frames: SpriteFrames = _sparrow("%s/notes.png" % SOURCE)
	for direction: String in DIRECTIONS:
		_rename(frames, NOTE_COLOURS[direction], "%s_note_neutral" % direction)

	var holds: Texture2D = load("%s/note-holds.png" % SOURCE)
	for i: int in DIRECTIONS.size():
		var direction: String = DIRECTIONS[i]
		for pair: int in 2:
			var name: String = "%s_note_%s" % [direction, "hold" if pair == 0 else "tail"]
			frames.add_animation(name)
			frames.set_animation_speed(name, 24.0)
			var region := AtlasTexture.new()
			region.atlas = holds
			region.region = Rect2(Vector2(float(HOLD_CELLS[i * 2 + pair]), 0.0), HOLD_SIZE)
			region.filter_clip = true
			frames.add_frame(name, region)

	return frames


# amtake-base.json's noteSplash and holdNoteCover blocks. Both ship two variants per
# colour; the splash block names both (left1/left2) and the hold-cover block names only the
# first, which is why only variant 1 is built for covers.
const SPLASH_VARIANTS := 2


## The hit splashes and the hold covers. Rubicon has no slot for either - see
## animania_mod/scripts/lane_effects.gd, which is what plays them.
##
## These two atlases cannot go through the importer's naming: it strips the frame index
## with `\\d+$`, and these subtextures are spelled "note splash purple 10000" - the VARIANT
## digit sits immediately before the index, so the regex eats both and variants 1 and 2
## collapse into a single animation named "note splash purple " (trailing space, 8 frames).
## They are separated here by splitting that merged animation in half, which is sound
## because the importer sorts frames by int(index) and 10000..10003 all come before
## 20000..20003.
func _build_effects() -> SpriteFrames:
	var splashes: SpriteFrames = _sparrow("%s/noteSplashes.png" % SOURCE)
	var covers: SpriteFrames = _sparrow("%s/strum-holds.png" % SOURCE)
	var built := SpriteFrames.new()
	built.remove_animation("default")

	for direction: String in DIRECTIONS:
		var colour: String = NOTE_COLOURS[direction]

		# amtake-base.json names both splash variants (left1, left2) and picks between them.
		_split(splashes, "note splash %s " % colour, built,
			["splash_%s_1" % direction, "splash_%s_2" % direction], false)

		# It names only variant 1 for the covers, so variant 2 is built and dropped. The
		# body loops - holdNoteCover's `<dir>Continue` is `<dir>Start`'s clip looped.
		_split(covers, "hold splash %s " % colour, built,
			["cover_%s" % direction, ""], true)
		_split(covers, "note splash %s end " % colour, built,
			["cover_%s_end" % direction, ""], false)

	return built


## Splits one merged animation into `names.size()` equal runs. An empty name drops that run.
func _split(source: SpriteFrames, merged: String, into: SpriteFrames,
		names: Array, looped: bool) -> void:
	if not source.has_animation(merged):
		push_error("no existe la animacion [%s]" % merged)
		quit(1)
		return

	var total: int = source.get_frame_count(merged)
	if total % names.size() != 0:
		push_error("[%s] tiene %d fotogramas, no divisible entre %d" % [
			merged, total, names.size()])
		quit(1)
		return

	var per_variant: int = total / names.size()
	for variant: int in names.size():
		var name: String = names[variant]
		if name.is_empty():
			continue
		into.add_animation(name)
		into.set_animation_speed(name, source.get_animation_speed(merged))
		into.set_animation_loop(name, looped)
		for i: int in per_variant:
			var frame: int = variant * per_variant + i
			into.add_frame(name, source.get_frame_texture(merged, frame),
				source.get_frame_duration(merged, frame))


## Same duration-aware library the character build uses, and for the same reason: the
## keyframer addon lengths an animation by its DEDUPED frame count and would run the
## eight-frame confirm animations at the wrong speed.
func _save_pair(frames: SpriteFrames, basename: String) -> void:
	var frames_path: String = "%s/%s_frames.tres" % [OUT, basename]
	var err: int = ResourceSaver.save(frames, frames_path)
	if err != OK:
		push_error("no se pudo guardar %s (%d)" % [frames_path, err])
		quit(1)
		return

	var library := AnimationLibrary.new()
	for anim: String in frames.get_animation_names():
		var animation := Animation.new()
		animation.step = 1.0 / frames.get_animation_speed(anim)
		animation.loop_mode = Animation.LOOP_LINEAR if frames.get_animation_loop(anim) \
			else Animation.LOOP_NONE

		var name_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(name_track, ^".:animation")
		animation.value_track_set_update_mode(name_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(name_track, Animation.INTERPOLATION_NEAREST)
		animation.track_insert_key(name_track, 0.0, anim)

		var frame_track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(frame_track, ^".:frame")
		animation.value_track_set_update_mode(frame_track, Animation.UPDATE_DISCRETE)
		animation.track_set_interpolation_type(frame_track, Animation.INTERPOLATION_NEAREST)

		var elapsed: float = 0.0
		for i: int in frames.get_frame_count(anim):
			animation.track_insert_key(frame_track, elapsed * animation.step, i)
			elapsed += frames.get_frame_duration(anim, i)

		animation.length = maxf(elapsed * animation.step, animation.step)
		library.add_animation(anim, animation)

	var library_path: String = "%s/%s_library.tres" % [OUT, basename]
	err = ResourceSaver.save(library, library_path)
	if err != OK:
		push_error("no se pudo guardar %s (%d)" % [library_path, err])
		quit(1)
		return

	for anim: String in frames.get_animation_names():
		print("OUT %-22s %d fotogramas  %.3fs" % [
			anim, frames.get_frame_count(anim), library.get_animation(anim).length])
	print("OUT guardado %s" % frames_path)
	print("OUT guardado %s" % library_path)
