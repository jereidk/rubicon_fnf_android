# Authors animania_mod/ui/health_bar.tscn - the mod's drawn health bar, in place of the
# Funkin one Rubicon ships.
#
# What it is not: a ProgressBar with a theme. The mod's bar is a hand-drawn stroke that
# ARCHES and tapers to a point at both ends, and it ships as three PNGs rather than as a
# rectangle - see animania_mod/scripts/animania_health_bar.gd for what each one is and for
# the measurements off a capture of the mod running.
#
# The arc is not written down here either: the Path2D the icons ride, and the placement of
# the fill inside the outline, are both READ OUT of the textures at build time, so if the
# art is ever replaced the layout follows it instead of drifting from it.
#
#   godot --headless --path . --script tools/animania/build_health_bar.gd
extends SceneTree

const OUT := "res://animania_mod/ui/health_bar.tscn"
const ART := "res://animania_mod/source/images/healthbar"
const SCRIPT := "res://animania_mod/scripts/animania_health_bar.gd"

# Funkin is 1280x720 and this project is 1920x1080.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

# Where the bar sits, measured on the capture: the fill's top-left lands at (270, 45) of a
# 1280x720 frame, which is centred horizontally with 45 above it.
const TOP := 45.0

# The fill is 46px narrower and 14px shorter than the outline, and sits centred in it: at
# (+23, +7) the tops of the two line up column for column down the whole span.
const FILL_INSET := Vector2(23.0, 7.0)

## How many points the icons' path is built from. The arc is shallow and smooth, so this is
## about being able to see the numbers in the scene rather than about fidelity.
const PATH_SAMPLES := 17

## The icons do not sit ON the stroke, they hang below it. Measured on the capture: their
## art runs y 37..129 of a 1280x720 frame, so their centre is 83 against the stroke's 57.
## Carried on the CURVE rather than as a sprite offset, because a sprite offset is in the
## sprite's own space and the two icons are scaled by different amounts to reach the same
## height - komi's frame is 158 tall and tadano's 146.
const ICON_DROP := 26.0


func _init() -> void:
	var outline: Texture2D = load("%s/healthbar.png" % ART)
	var fill: Texture2D = load("%s/whitebar.png" % ART)
	if outline == null or fill == null:
		push_error("faltan las texturas de la barra en %s" % ART)
		quit(1)
		return

	var fill_size: Vector2 = fill.get_size()
	var root := ProgressBar.new()
	root.name = "HealthBar"
	root.set_script(load(SCRIPT))
	root.show_percentage = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.step = 0.01
	root.value = 50.0
	# The bar draws itself; the ProgressBar underneath is only the value and the ratio the
	# icons ride on. Left with its theme it would paint a rectangle behind the art.
	for part: String in ["background", "fill"]:
		root.add_theme_stylebox_override(part, StyleBoxEmpty.new())

	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.offset_left = -fill_size.x * FUNKIN_TO_RUBICON * 0.5
	root.offset_right = fill_size.x * FUNKIN_TO_RUBICON * 0.5
	root.offset_top = TOP * FUNKIN_TO_RUBICON
	root.offset_bottom = (TOP + fill_size.y) * FUNKIN_TO_RUBICON

	# Everything drawn hangs off one node at the bar's top-left, scaled by the 1.5 the rest
	# of the port carries, so the two fills and the outline cannot drift from each other.
	#
	# The mirroring lives HERE rather than on each sprite. Sprite2D.flip_v on a sprite that
	# is not centred does not mirror inside its own box: it negates the destination rect's
	# height, so the art draws UPWARD from the origin and the whole bar came out 37px high
	# of where the Control puts it. A negative scale on the parent, with the origin pushed
	# down by the height it is about to mirror through, keeps the box where it is.
	var art := Node2D.new()
	art.name = "Art"
	art.scale = Vector2(FUNKIN_TO_RUBICON, -FUNKIN_TO_RUBICON)
	art.position = Vector2(0.0, fill_size.y * FUNKIN_TO_RUBICON)
	root.add_child(art)

	# UNDER the fill, and its own top-left is the fill inset back out again. Under, because
	# the fill is TALLER than the outline is hollow - 24px against 17 at the same column -
	# so an outline on top eats 4px of colour off the stroke and it measured 19 against the
	# capture's 23-24. Behind, what is left of it is the black rim around the colour, which
	# is what an outline is.
	var frame := Sprite2D.new()
	frame.name = "Outline"
	frame.texture = outline
	frame.centered = false
	frame.position = -FILL_INSET
	art.add_child(frame)

	var player_fill: Sprite2D = _fill_sprite(fill, "PlayerFill")
	var opponent_fill: Sprite2D = _fill_sprite(fill, "OpponentFill")
	art.add_child(player_fill)
	art.add_child(opponent_fill)

	var path := Path2D.new()
	path.name = "Path2D"
	path.curve = _curve_of(fill)
	root.add_child(path)

	var follow := PathFollow2D.new()
	follow.name = "PathFollow2D"
	follow.rotates = false
	# Not progress_ratio: that only takes outside the tree if the path is in one, and the
	# bar sets it from the health on _ready anyway.
	path.add_child(follow)

	# The icons do NOT ride this one. phone-call.script sets `icon.x` directly every frame
	# to `healthBar.centerPoint.x` plus a small fixed offset - never to anything derived
	# from health - so their separation is constant and their shared position is the bar's
	# own middle, always. Riding the health-driven follow point put them there only at
	# exactly 50% and slid them apart from each other's true resting point everywhere else.
	# A second follow point pinned at the middle of the arc gives them the bow's curve
	# without any of the drift.
	var icon_anchor := PathFollow2D.new()
	icon_anchor.name = "IconAnchor"
	icon_anchor.rotates = false
	icon_anchor.progress_ratio = 0.5
	path.add_child(icon_anchor)

	# Rubicon's own bar names them IconL and IconR and build_level_scene's _dress_icons
	# rewrites both, so the names are load-bearing. IconL is drawn mirrored, which is what
	# puts it on the far side of the anchor.
	for icon_name: String in ["IconL", "IconR"]:
		var icon := AnimatedSprite2D.new()
		icon.name = icon_name
		if icon_name == "IconL":
			icon.scale = Vector2(-1.0, 1.0)
		icon_anchor.add_child(icon)

	root.set(&"player_fill", player_fill)
	root.set(&"opponent_fill", opponent_fill)
	root.set(&"path", path)
	root.set(&"path_follow", follow)
	# No connect() here: PackedScene.pack() drops a connection that is not CONNECT_PERSIST,
	# and the bar wires its own on _ready.

	for node: Node in [art, frame, player_fill, opponent_fill, path, follow, icon_anchor,
			icon_anchor.get_child(0), icon_anchor.get_child(1)]:
		node.owner = root

	var packed := PackedScene.new()
	packed.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT).get_base_dir())
	ResourceSaver.save(packed, OUT)
	print("OUT barra %.0fx%.0f, arco de %d puntos -> %s" % [
		fill_size.x, fill_size.y, PATH_SAMPLES, OUT])
	quit(0)


func _fill_sprite(texture: Texture2D, node_name: String) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, texture.get_size())
	return sprite


## The stroke's own centreline, read off the fill's alpha, mirrored the way the sprite is.
## The icons ride this, so they follow the bow instead of cutting across it.
func _curve_of(texture: Texture2D) -> Curve2D:
	var image: Image = texture.get_image()
	var width: int = image.get_width()
	var height: int = image.get_height()
	var curve := Curve2D.new()

	for sample: int in PATH_SAMPLES:
		# The very ends taper to a point and their centre reads as noise, so the samples
		# stop short of them and the curve's own ends extrapolate.
		var x: int = int(roundf(lerpf(width * 0.06, width * 0.94, float(sample)
			/ float(PATH_SAMPLES - 1))))
		var top: int = -1
		var bottom: int = -1
		for y: int in height:
			if image.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
		if top < 0:
			continue
		# Mirrored, because the sprites are.
		var centre: float = float(height - 1) - (float(top + bottom) * 0.5)
		curve.add_point(Vector2(float(x), centre + ICON_DROP) * FUNKIN_TO_RUBICON)

	return curve
