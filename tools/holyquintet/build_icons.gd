# Builds the health-bar icon SpriteFrames for Holy Quintet's cast (neutral pose), the
# shape rubicon_health_bar.gd plays: one animation literally named "neutral".
#
#   godot --headless --path . --script tools/holyquintet/build_icons.gd
extends SceneTree

const OUT_DIR := "res://holyquintet_mod/ui"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# sayaka is a sparrow icon atlas (icons/sayaka/icon.png + icon.xml + data.xml).
	_build_sparrow_icon("sayaka", "res://holyquintet_mod/source/images/icons/sayaka/icon.png", "SAYAKA-N")
	# bf ships as a bare two-frame strip with no XML; frame 0 is the neutral face. HQ's
	# bf.xml says bf faces right when not flipped, which is what bar's IconR expects.
	_build_strip_icon("bf", "res://holyquintet_mod/source/images/icons/bf/icon.png")
	quit(0)


func _build_sparrow_icon(basename: String, png: String, prefix: String) -> void:
	var data := SparrowImporterSpriteData.new()
	data.texture = load(png)
	data.atlas_path = png.get_basename() + ".xml"
	data.fps = 24
	data.loop = true
	var importer: SpriteImporter = load("res://addons/sprite_importer/importers/sparrow.gd").new()
	var source: SpriteFrames = importer.convert_sprite([data])

	var source_anim := ""
	for anim: String in source.get_animation_names():
		if anim.begins_with(prefix):
			source_anim = anim
			break
	if source_anim == "":
		push_error("%s: no animation starting with %s" % [basename, prefix])
		quit(1)
		return

	var frames := SpriteFrames.new()
	frames.add_animation(&"neutral")
	frames.set_animation_speed(&"neutral", 24.0)
	frames.set_animation_loop(&"neutral", true)
	for i: int in source.get_frame_count(source_anim):
		frames.add_frame(&"neutral", source.get_frame_texture(source_anim, i),
			source.get_frame_duration(source_anim, i))
	var path := "%s/%s_icon.tres" % [OUT_DIR, basename]
	var err: int = ResourceSaver.save(frames, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
		quit(1)
		return
	print("OUT %s (anim=%s frames=%d)" % [path, source_anim, frames.get_frame_count(&"neutral")])


## bf/icon.png is 300x150 - two 150x150 icons side by side - with no atlas XML.
func _build_strip_icon(basename: String, png: String) -> void:
	var image: Image = (load(png) as Texture2D).get_image()
	var crop := image.get_region(Rect2i(0, 0, 150, 150))
	var frames := SpriteFrames.new()
	frames.add_animation(&"neutral")
	frames.add_frame(&"neutral", ImageTexture.create_from_image(crop), 1.0)
	var path := "%s/%s_icon.tres" % [OUT_DIR, basename]
	var err: int = ResourceSaver.save(frames, path)
	if err != OK:
		push_error("could not save %s (%d)" % [path, err])
		quit(1)
		return
	print("OUT %s (strip frame 0)" % path)
