# Builds a SpriteFrames + AnimationLibrary pair out of a Sparrow atlas, headlessly.
#
# The sprite_importer addon only exposes this through an editor dock, but the part
# that does the work is a plain RefCounted, so it drives fine from a --script run.
# Going through it rather than walking the XML by hand keeps the frame-duration
# dedup and the frameX/frameY margin handling that a hand-rolled parser gets wrong.
#
# The library is built here rather than with SpriteFramesKeyframer._make_library,
# and that is deliberate: the keyframer ignores frame durations. It sets
# `length = step * get_frame_count()` and drops a key at `i * step`, both over the
# DEDUPED frame count -- so komi's idle, 15 authored frames that dedup to 4 held
# for [2, 2, 2, 9], comes out 0.167s long instead of 0.625s and plays four times
# too fast. The addon's own source says as much ("temporary until frame duration
# usage is fixed") with the duration-aware version sitting commented out beside it.
# Keying off the running duration total is that version.
#
#   godot --headless --path . --script tools/animania/build_sparrow_character.gd \
#       -- <png> <out_dir> <basename> [fps] [loop]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: <png> <out_dir> <basename> [fps] [loop]")
		quit(1)
		return

	var png: String = args[0]
	var out_dir: String = args[1]
	var basename: String = args[2]
	var fps: int = int(args[3]) if args.size() > 3 else 24
	var loop: bool = args.size() > 4 and args[4] == "loop"

	var xml: String = png.get_basename() + ".xml"
	if not FileAccess.file_exists(ProjectSettings.globalize_path(xml)):
		push_error("no atlas beside %s" % png)
		quit(1)
		return

	var data := SparrowImporterSpriteData.new()
	data.texture = load(png)
	data.atlas_path = xml
	data.fps = fps
	data.loop = loop

	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	var frames: SpriteFrames = importer.convert_sprite([data])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var frames_path: String = "%s/%s_frames.tres" % [out_dir, basename]
	var err: int = ResourceSaver.save(frames, frames_path)
	if err != OK:
		push_error("could not save %s (%d)" % [frames_path, err])
		quit(1)
		return

	var library: AnimationLibrary = _make_library(frames, basename)
	var library_path: String = "%s/%s_library.tres" % [out_dir, basename]
	err = ResourceSaver.save(library, library_path)
	if err != OK:
		push_error("could not save %s (%d)" % [library_path, err])
		quit(1)
		return

	for anim: String in frames.get_animation_names():
		var animation: Animation = library.get_animation("%s_%s" % [basename, anim])
		print("OUT %-12s distinct=%d length=%.3fs" % [
			anim, frames.get_frame_count(anim), animation.length])
	print("OUT saved %s" % frames_path)
	print("OUT saved %s" % library_path)
	quit(0)


# Each animation drives the AnimatedSprite2D's own `animation` and `frame`, which is
# the shape rubicon_character.gd's root player dispatches into (see bf.tscn).
func _make_library(frames: SpriteFrames, prefix: String) -> AnimationLibrary:
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
		library.add_animation("%s_%s" % [prefix, anim], animation)

	return library
