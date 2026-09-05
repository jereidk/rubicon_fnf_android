# Builds a standalone sparrow stage prop (AnimatedSprite2D + per-animation library) out of
# a png+xml atlas, for props like game/speakersmain whose bop is a sparrow animation.
#
#   godot --headless --path . --script tools/holyquintet/build_sparrow_prop.gd \
#       -- <png> <out_dir> <basename> <anim_name=symbol> [anim_name=symbol ...]
extends SceneTree

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("usage: <png> <out_dir> <basename> <anim=symbol> ...")
		quit(1)
		return

	var png: String = args[0]
	var out_dir: String = args[1]
	var basename: String = args[2]

	var xml: String = png.get_basename() + ".xml"
	var data := SparrowImporterSpriteData.new()
	data.texture = load(png)
	data.atlas_path = xml
	data.fps = 24
	data.loop = true

	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	var frames: SpriteFrames = importer.convert_sprite([data])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var frames_path: String = "%s/%s_frames.tres" % [out_dir, basename]
	var err: int = ResourceSaver.save(frames, frames_path)
	if err != OK:
		push_error("could not save %s (%d)" % [frames_path, err])
		quit(1)
		return

	var library := AnimationLibrary.new()
	for clip_arg: String in args.slice(3):
		var pair := clip_arg.split("=", true, 1)
		var anim := StringName(pair[0])
		var symbol: String = pair[1]
		var sprite_anim := _symbol_anim(frames, symbol)
		if sprite_anim == "":
			push_error("%s: no sparrow animation for prefix '%s'" % [basename, symbol])
			quit(1)
			return
		library.add_animation(anim, _library_anim(frames, sprite_anim))

	var library_path: String = "%s/%s_library.tres" % [out_dir, basename]
	err = ResourceSaver.save(library, library_path)
	if err != OK:
		push_error("could not save %s (%d)" % [library_path, err])
		quit(1)
		return

	var root := Node2D.new()
	root.name = basename
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = frames
	sprite.centered = false
	root.add_child(sprite)
	sprite.owner = root
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library(&"", library)
	sprite.add_child(player)
	player.owner = root
	player.autoplay = &"bop"

	var packed := PackedScene.new()
	err = packed.pack(root)
	if err != OK:
		push_error("could not pack prop (%d)" % err)
		quit(1)
		return
	var scene_path: String = "%s/%s.tscn" % [out_dir, basename]
	err = ResourceSaver.save(packed, scene_path)
	if err != OK:
		push_error("could not save %s (%d)" % [scene_path, err])
		quit(1)
		return
	print("OUT saved %s (anims: %s)" % [scene_path, ", ".join(library.get_animation_list())])
	quit(0)


## The sparrow importer names animations after their XML prefix; find the one that starts
## with `symbol` - the mod's addAnim prefixes can include spaces and trailing digits.
func _symbol_anim(frames: SpriteFrames, symbol: String) -> String:
	for anim: String in frames.get_animation_names():
		if anim.begins_with(symbol) or symbol.begins_with(anim):
			return anim
	return ""


func _library_anim(frames: SpriteFrames, anim: String) -> Animation:
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
	return animation
