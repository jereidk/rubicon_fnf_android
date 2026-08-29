# Authors stg_phone_call_street.tscn out of phoneCallStreet.json and phoneCallStreet.hx.
#
# The JSON is the prop layout; the .hx is what the stage does to it at build time, and
# the two disagree in four places where the script wins:
#
#   * `lightShade` gets scrollFactor (0, 1) - not the (0.0, 0.5) in the JSON - blend
#     NORMAL, alpha 0.1, scale.x 1882.6*3 and double height. light.png is 1x1741, a
#     one-pixel vertical gradient column, so those scales are the whole prop.
#   * `overlay-all` ships shouldDraw off and the script turns it on.
#   * every prop whose name contains "stand-" is hidden. Six of the eighteen are, so
#     they are built here as authored and shipped `visible = false` rather than dropped,
#     which keeps the scene diffable against the JSON.
#   * the sky is not a prop at all: it is an FlxBackdrop added in code, repeating on X
#     (FlxAxes 0x01), drifting at 20 px/s.
#
# Two conversions, both deliberate and both stated so nobody re-derives them:
#
#   * Coordinates stay VERBATIM in Funkin's 1280x720 space. This project is 1920x1080,
#     and that 1.5x belongs on the level camera - putting it here would resample the art
#     and make every number in the scene un-diffable against the JSON.
#   * `zoomFactor` has no Godot equivalent. The two props authored at 0 (`overlay-all`
#     and `introText`) mean "ignore camera zoom entirely", which is a CanvasLayer, and
#     that is ported exactly. `bushes right` at 0.9 is a partial exemption with no clean
#     equivalent; it is built at 1.0 and called out here rather than faked.
extends SceneTree

const JSON_PATH := "res://animania_mod/source/data/phoneCallStreet.json"
const IMAGES := "res://animania_mod/source/images/phoneCallStreet"
const OUT := "res://animania_mod/stages/stg_phone_call_street.tscn"

# The .hx overrides for lightShade, applied after the JSON.
const LIGHT_SHADE_WIDTH := 1882.6 * 3.0


func _init() -> void:
	var text: String = FileAccess.get_file_as_string(JSON_PATH)
	var data: Dictionary = JSON.parse_string(text)
	if data == null:
		push_error("could not read %s" % JSON_PATH)
		quit(1)
		return

	var root := Node2D.new()
	root.name = "PhoneCallStreet"
	# Read by whatever level scene instances this stage.
	root.set_meta(&"camera_zoom", float(data["cameraZoom"]))
	root.set_meta(&"camera_speed", float(data["cameraSpeed"]))
	root.set_meta(&"ratings_offset", _vec(data["ratingsOffset"]))

	_add_sky(root)

	# One Parallax2D per distinct scroll factor, in the order the props first ask for it,
	# so the scene reads in the same order as the JSON.
	var layers: Dictionary = {}
	for prop: Dictionary in data["props"]:
		_add_prop(root, layers, prop)

	_add_characters(root, layers, data["characters"])
	_add_leaves(root)
	_add_screen_space(root, data["props"])

	_own(root, root)

	var packed := PackedScene.new()
	var err: int = packed.pack(root)
	if err != OK:
		push_error("could not pack (%d)" % err)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		push_error("could not save %s (%d)" % [OUT, err])
		quit(1)
		return

	print("OUT saved %s" % OUT)
	_describe(root, 0)
	quit(0)


func _vec(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))


# FlxBackdrop(sky, FlxAxes.X, -1885.85, -831.5), scroll 0.1, velocity.x 20, scale 1.2.
func _add_sky(root: Node2D) -> void:
	var texture: Texture2D = load("%s/sky.png" % IMAGES)

	var parallax := Parallax2D.new()
	parallax.name = "Sky"
	parallax.scroll_scale = Vector2(0.1, 0.1)
	# FlxAxes.X: tiles horizontally, once vertically.
	parallax.repeat_size = Vector2(texture.get_width() * 1.2, 0.0)
	parallax.repeat_times = 3
	# FlxBackdrop.velocity.x moves the backdrop itself, which is what autoscroll does.
	parallax.autoscroll = Vector2(20.0, 0.0)
	parallax.z_index = -13
	root.add_child(parallax)

	var sprite := Sprite2D.new()
	sprite.name = "SkySprite"
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(-1885.85, -831.5)
	sprite.scale = Vector2(1.2, 1.2)
	parallax.add_child(sprite)


func _layer_for(root: Node2D, layers: Dictionary, scroll: Vector2) -> Node2D:
	var key: String = "%.4f_%.4f" % [scroll.x, scroll.y]
	if layers.has(key):
		return layers[key]

	var parallax := Parallax2D.new()
	parallax.name = "Scroll_%s_%s" % [
		String.num(scroll.x, 3).replace(".", "p"),
		String.num(scroll.y, 3).replace(".", "p")]
	parallax.scroll_scale = scroll
	root.add_child(parallax)
	layers[key] = parallax
	return parallax


func _add_prop(root: Node2D, layers: Dictionary, prop: Dictionary) -> void:
	var prop_name: String = prop["name"]
	# The two zoomFactor-0 props are screen space and are built in _add_screen_space.
	if prop_name in ["overlay-all", "introText"]:
		return

	var texture: Texture2D = load("%s/%s.png" % [IMAGES, String(prop["assetPath"]).trim_prefix("stages/phoneCallStreet/")])
	if texture == null:
		push_error("no texture for prop %s" % prop_name)
		quit(1)
		return

	var scroll: Vector2 = _vec(prop["scroll"])
	if prop_name == "lightShade":
		scroll = Vector2(0.0, 1.0)  # buildStage() overrides the JSON's (0, 0.5)

	var sprite := Sprite2D.new()
	sprite.name = prop_name.replace(" ", "_").replace("-", "_")
	sprite.texture = texture
	sprite.centered = false
	sprite.position = _vec(prop["position"])
	sprite.z_index = int(prop["zIndex"])

	var authored_scale: float = float(prop.get("scale", 1.0))
	sprite.scale = Vector2(authored_scale, authored_scale)
	if prop.has("alpha"):
		sprite.modulate.a = float(prop["alpha"])

	if prop_name == "lightShade":
		sprite.scale = Vector2(LIGHT_SHADE_WIDTH, authored_scale * 2.0)
		sprite.modulate.a = 0.1

	# for prop in namedProps: if name contains "stand-" -> visible = false
	if prop_name.contains("stand-"):
		sprite.visible = false

	_layer_for(root, layers, scroll).add_child(sprite)


# addCharacter() gives DAD scrollFactor (0.9, 0.95); BF and GF keep (1, 1). The marker
# positions are the stage JSON's, and the character JSON's own `offsets` are added on
# top of them by whatever places the characters.
func _add_characters(root: Node2D, layers: Dictionary, characters: Dictionary) -> void:
	var slots: Dictionary = {
		"dad": "OpponentPoint", "bf": "PlayerPoint", "gf": "GirlfriendPoint"}

	for slot: String in ["dad", "bf", "gf"]:
		var entry: Dictionary = characters[slot]
		var marker := Marker2D.new()
		marker.name = slots[slot]
		marker.position = _vec(entry["position"])
		marker.z_index = int(entry["zIndex"])
		marker.set_meta(&"camera_offsets", _vec(entry["cameraOffsets"]))

		if slot == "dad":
			_layer_for(root, layers, Vector2(0.9, 0.95)).add_child(marker)
		else:
			root.add_child(marker)


func _add_leaves(root: Node2D) -> void:
	var leaves := Node2D.new()
	leaves.name = "Leaves"
	leaves.set_script(load("res://animania_mod/scripts/phone_call_leaves.gd"))
	leaves.z_index = 900
	leaves.set(&"leaf_frames", load("res://animania_mod/stages/leafs_frames.tres"))
	leaves.set(&"leaf_animation", &"leaf")
	root.add_child(leaves)


# zoomFactor 0 means the camera's zoom does not reach these, which is a CanvasLayer.
func _add_screen_space(root: Node2D, props: Array) -> void:
	var layer := CanvasLayer.new()
	layer.name = "ScreenSpace"
	root.add_child(layer)

	# A CanvasLayer draws in tree order, so these go in ascending zIndex: overlay-all
	# (5000) under introText (6000), which is the order the JSON does NOT list them in.
	var screen_props: Array = props.filter(
		func(p: Dictionary) -> bool: return String(p["name"]) in ["overlay-all", "introText"])
	screen_props.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["zIndex"]) < int(b["zIndex"]))

	for prop: Dictionary in screen_props:
		match String(prop["name"]):
			"overlay-all":
				var overlay := Sprite2D.new()
				overlay.name = "OverlayAll"
				overlay.texture = load("%s/light.png" % IMAGES)
				overlay.centered = false
				overlay.position = _vec(prop["position"])
				# "scale": [1280, 1] - light.png is 1px wide, so this is the width.
				overlay.scale = _vec(prop["scale"])
				overlay.modulate.a = float(prop["alpha"])
				# "blend": "add"
				var material := CanvasItemMaterial.new()
				material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				overlay.material = material
				layer.add_child(overlay)

			"introText":
				var intro := AnimatedSprite2D.new()
				intro.name = "IntroText"
				intro.sprite_frames = load("res://animania_mod/stages/intro_frames.tres")
				intro.animation = &"intro text"
				intro.centered = false
				intro.position = _vec(prop["position"])
				intro.autoplay = &"intro text"
				# The one prop shipped against its authored state. No chart event names
				# it and phoneCallStreet.hx does not touch it, so it looked like the mod's
				# PlayState had to be hiding it - and phone-call.script turned out to be
				# what does: beat 1 centres it and fades it up over 2.5s, beat 11 fades it
				# out. The level scene owns that, so this ships it off.
				intro.visible = false
				layer.add_child(intro)

	_add_bloom(layer)


## phoneCallStreet.hx line 58: a ShaderFilter on FlxG.camera, gated behind
## Preferences.shaders. A camera filter is a full-screen pass over everything the GAME
## camera drew, so here it is a full-screen rect at the END of ScreenSpace: above the stage
## and above overlay-all, and below the Overlays, CinematicBars and UILayer canvases, which
## is why a capture of the mod has a washed-out wall and a still-black letterbox.
##
## Measured before it existed: the mod's wall reads +39 on green and +40 on blue against
## this port's, with red pinned at 255 in both, and the letterbox reads 0 in both.
##
## It is sixteen texture samples a pixel over the whole screen. Nothing here has a quality
## ladder yet - the mod puts this behind Preferences.shaders - so it ships as an exported
## flag on the stage that a settings menu can turn off when there is one.
func _add_bloom(layer: CanvasLayer) -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://animania_mod/shaders/bloom.gdshader")

	var bloom := ColorRect.new()
	bloom.name = "Bloom"
	bloom.material = material
	bloom.color = Color.WHITE
	bloom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bloom.offset_right = 1920.0
	bloom.offset_bottom = 1080.0
	layer.add_child(bloom)


func _own(node: Node, owner: Node) -> void:
	for child: Node in node.get_children():
		if child != owner:
			child.owner = owner
		_own(child, owner)


func _describe(node: Node, depth: int) -> void:
	var extra: String = ""
	if node is Parallax2D:
		extra = " scroll=%s" % [(node as Parallax2D).scroll_scale]
	elif node is CanvasItem:
		extra = " z=%d%s" % [(node as CanvasItem).z_index,
			"" if (node as CanvasItem).visible else " HIDDEN"]
	print("OUT %s%s (%s)%s" % ["  ".repeat(depth), node.name, node.get_class(), extra])
	for child: Node in node.get_children():
		_describe(child, depth + 1)
