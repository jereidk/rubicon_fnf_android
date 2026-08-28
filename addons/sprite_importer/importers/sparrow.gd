@tool
extends SpriteImporter

func get_format_name() -> StringName:
	return "Sparrow"

func get_importer_data_class() -> String:
	return "SparrowImporterSpriteData"

func needs_atlas_path() -> bool:
	return true

func get_atlas_extension() -> String:
	return ".xml"

## Sparrow packs a frame sideways when it fits better that way and marks it
## `rotated="true"`, and the reader is expected to turn it back. This importer did not, so
## those frames drew on their side - 13 of the 64 in Animania's tadano icon, which is why it
## looked like it had fallen over while komi's, with none, was fine.
##
## An AtlasTexture cannot rotate, so a rotated frame cannot be a window onto the sheet: it
## has to be baked into an image of its own. Everything else still goes through AtlasTexture,
## and SpriteFrames takes either.
##
## The XML says which is which. A rotated entry carries the region AS PACKED and the frame
## size UNPACKED, transposed against each other - 146x171 in the sheet for a 171x146 frame.
var _baked_rotations: Dictionary = {}


func convert_sprite(sprite_data_array:Array, disabled_anims:Array[String] = []) -> SpriteFrames:
	var sprite_frames:SpriteFrames = SpriteFrames.new()
	sprite_frames.remove_animation("default")
	_baked_rotations.clear()
	
	var last_replaced_anim:String
	var frame_list:Dictionary[String, Array]
	for sprite_data:SparrowImporterSpriteData in sprite_data_array:
		sprite_data.read_atlas(sprite_data.atlas_path)
		var atlas:XMLParser = sprite_data.atlas
		
		var last_frame:AnimationFrame = AnimationFrame.new()
		last_frame.atlas_texture.atlas = sprite_data.texture
		
		while atlas.read() == OK:
			if atlas.get_node_type() != XMLParser.NODE_ELEMENT:
				continue
			
			if atlas.get_node_name().to_lower() != "subtexture":
				continue
			
			var frame:AnimationFrame = AnimationFrame.new()
			var anim_name:String = atlas.get_named_attribute_value("name")
			var anim_index_raw:String = get_anim_index(anim_name)
			var indexless_anim:String = anim_name.replace(anim_index_raw, "")
			
			if sprite_data.anim_aliases.has(anim_name):
				if anim_name != last_replaced_anim:
					print("Animation:" + anim_name + " replaced with: " + sprite_data.anim_aliases[anim_name])
				last_replaced_anim = anim_name
				anim_name = sprite_data.anim_aliases[anim_name]
				
			frame.anim_name = indexless_anim
			frame.frame_idx = int(anim_index_raw)
			frame.atlas_texture.atlas = sprite_data.texture
			
			frame.atlas_texture.region = Rect2(
				atlas.get_named_attribute_value("x").to_float(),
				atlas.get_named_attribute_value("y").to_float(),
				atlas.get_named_attribute_value("width").to_float(),
				atlas.get_named_attribute_value("height").to_float()
				)
			frame.atlas_texture.filter_clip = true
			
			if atlas.has_attribute("frameX"):
				frame.atlas_margin = Rect2(
					-atlas.get_named_attribute_value_safe("frameX").to_float(),
					-atlas.get_named_attribute_value_safe("frameY").to_float(), 
					atlas.get_named_attribute_value_safe("frameWidth").to_float() - frame.atlas_texture.region.size.x,
					atlas.get_named_attribute_value_safe("frameHeight").to_float() - frame.atlas_texture.region.size.y
					)
			
			if !frame_list.has(indexless_anim):
				frame_list[indexless_anim] = []
				if !sprite_frames.has_animation(indexless_anim):
					sprite_frames.add_animation(indexless_anim)
					sprite_frames.set_animation_loop(indexless_anim, sprite_data.loop)
					sprite_frames.set_animation_speed(indexless_anim, sprite_data.fps)
			
			if frame.atlas_texture.region == last_frame.atlas_texture.region:
				if sprite_data.use_frame_duration:
					frame_list[indexless_anim][frame_list[indexless_anim].find(last_frame)].frame_duration += 1
					continue
				frame.atlas_texture = last_frame.atlas_texture
				
			if atlas.get_named_attribute_value_safe("rotated") == "true":
				# Baked, and therefore no margin to set: the baked image is already the
				# frame's full size. The margin arithmetic above would use the packed
				# region's width against the unpacked frame's and come out wrong anyway.
				var baked: Texture2D = _bake_rotated(sprite_data.texture,
					frame.atlas_texture.region,
					Vector2(atlas.get_named_attribute_value_safe("frameWidth").to_float(),
						atlas.get_named_attribute_value_safe("frameHeight").to_float()),
					Vector2(atlas.get_named_attribute_value_safe("frameX").to_float(),
						atlas.get_named_attribute_value_safe("frameY").to_float()))
				if baked != null:
					_baked_rotations[frame] = baked
			elif frame.atlas_margin != null:
				frame.atlas_texture.margin = frame.atlas_margin
			
			last_frame = frame
			
			frame_list[indexless_anim].push_back(frame)
	
	for anim:String in frame_list.keys():
		frame_list[anim].sort_custom(sort_frames)
		
		if disabled_anims.has(anim):
			continue
			
		for frame:AnimationFrame in frame_list[anim]:
			sprite_frames.add_frame(anim,
				_baked_rotations.get(frame, frame.atlas_texture), frame.frame_duration)
	
	return sprite_frames

## Turns one packed-sideways region back into an upright frame.
##
## Sparrow rotates clockwise on the way in, so this rotates counter-clockwise on the way
## out. If the frame declares itself bigger than its region - a trimmed frame - the result
## is composited onto a transparent image of the declared size, which is what an
## AtlasTexture margin does for the frames that keep going through it.
func _bake_rotated(sheet:Texture2D, region:Rect2, frame_size:Vector2,
		frame_offset:Vector2) -> Texture2D:
	if sheet == null:
		return null

	var source:Image = sheet.get_image()
	if source == null:
		return null
	if source.is_compressed() and source.decompress() != OK:
		return null

	var cut:Image = source.get_region(Rect2i(region))
	if cut.get_width() == 0 or cut.get_height() == 0:
		return null
	cut.rotate_90(COUNTERCLOCKWISE)

	if frame_size.x > cut.get_width() or frame_size.y > cut.get_height():
		var padded:Image = Image.create_empty(int(frame_size.x), int(frame_size.y),
			false, cut.get_format())
		padded.fill(Color(0, 0, 0, 0))
		padded.blit_rect(cut, Rect2i(Vector2i.ZERO, cut.get_size()),
			Vector2i(-frame_offset))
		cut = padded

	return ImageTexture.create_from_image(cut)


func sort_frames(a:AnimationFrame, b:AnimationFrame) -> bool:
	return a.frame_idx < b.frame_idx

var regex:RegEx = RegEx.new()
func get_anim_index(anim_name:String) -> String:
	if regex.get_pattern().is_empty() or regex.get_pattern() == null:
		regex.compile("\\d+$")
	
	var index:RegExMatch = regex.search(anim_name)
	if index:
		return index.get_string()
	
	return "0"
