extends Node

## Applies the selected LullabyNoteLayout to whatever song scene is running.
##
## An autoload rather than a node in each song scene: the three songs lay
## their lanes out identically (a Player and an Opponent Control holding
## Lane0..3), so putting it here means adding a layout is a .tres, and a
## fourth song picks it up for free instead of needing to remember to wire
## it. It hooks the scene change signals the diagnostics log already added.
##
## Everything is expressed as a multiplier on what the scene was authored
## with, and the authored values are captured once before anything is
## touched - so switching layouts mid-session, or back to Classic, restores
## the original numbers exactly instead of compounding scale factors.

const LAYOUT_CLASSIC: LullabyNoteLayout = preload("res://lullaby_mod/resources/note_layouts/ntl_classic.tres")
const LAYOUT_VSLICE: LullabyNoteLayout = preload("res://lullaby_mod/resources/note_layouts/ntl_vslice.tres")

const PLAYER_PATH := "UILayer/GameUI/Player"
const OPPONENT_PATH := "UILayer/GameUI/Opponent"

## Captured per strumline: the anchor, offsets and lane positions the scene
## shipped with. Keyed by the Control itself, cleared on scene change.
var _authored: Dictionary = {}

func _ready() -> void:
	if SceneChanger.has_signal("scene_change_finished"):
		SceneChanger.scene_change_finished.connect(_on_scene_changed)
	if Settings.has_signal("applied"):
		Settings.applied.connect(_apply_to_current_scene)

	# The first scene of a session is already up by the time this runs, and
	# no scene-change signal will fire for it.
	_apply_to_current_scene.call_deferred()

func get_layout() -> LullabyNoteLayout:
	return LAYOUT_VSLICE if Settings.lullaby_note_layout == 1 else LAYOUT_CLASSIC

func _on_scene_changed(_path: String) -> void:
	# The old scene's Controls are gone; holding their authored values would
	# leak and would never match again anyway.
	_authored.clear()
	_apply_to_current_scene.call_deferred()

func _apply_to_current_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	var layout: LullabyNoteLayout = get_layout()
	var amplification: float = _aspect_amplification()

	_apply_to(scene.get_node_or_null(PLAYER_PATH), layout.player_anchor,
		layout.player_spacing_scale, layout.player_note_scale, layout.player_y_nudge,
		layout.player_split_gap * amplification)
	_apply_to(scene.get_node_or_null(OPPONENT_PATH), layout.opponent_anchor,
		layout.opponent_spacing_scale, layout.opponent_note_scale, layout.opponent_y_nudge,
		layout.opponent_split_gap * amplification)

## The centre channel is not a fixed pixel width in the reference. VSlice
## derives it from the device's aspect ratio -
## (width/height) / (design width/height), pinned to 1.0 at the design
## resolution - because its scale mode keeps the height fixed and lets the
## width grow, so a wider phone gets proportionally more room between the
## two lane pairs. A fixed value looks right on exactly one aspect ratio and
## wrong on every other, which is what the first version shipped.
##
## Measured against the real window rather than the viewport: with a stretch
## mode set, the viewport keeps reporting the design size no matter what the
## device is, which would make this always return 1.0.
func _aspect_amplification() -> float:
	var window: Vector2i = DisplayServer.window_get_size()
	if window.x <= 0 or window.y <= 0:
		return 1.0

	var design_width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	var design_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	if design_width <= 0.0 or design_height <= 0.0:
		return 1.0

	return (float(window.x) / float(window.y)) / (design_width / design_height)

func _apply_to(strumline: Control, anchor: float, spacing_scale: float, note_scale: float,
		y_nudge: float, split_gap: float) -> void:
	if strumline == null:
		return

	if not _authored.has(strumline):
		var lanes: Dictionary = {}
		for lane in _lanes_of(strumline):
			lanes[lane] = lane.position.x
		_authored[strumline] = {
			"anchor": strumline.anchor_left,
			"offset_top": strumline.offset_top,
			"offset_bottom": strumline.offset_bottom,
			"lanes": lanes,
		}

	var authored: Dictionary = _authored[strumline]

	# Midscroll is not a property, it is an AnimationTree ("centered" /
	# "uncentered" states) driving the strumlines' horizontal placement every
	# frame. Writing an anchor here would be overwritten by the animation on
	# the next frame - and in between the two you get the distorted layout
	# that made this show up. So when midscroll is on it owns horizontal
	# placement outright and only the lane spacing and note size below are
	# applied on top of it.
	#
	# That is not a compromise for VSlice specifically: VSlice wants the
	# player strumline centred, which is exactly what midscroll already does,
	# so the two combine into the intended look rather than fighting for it.
	if not Settings.game_centered:
		strumline.anchor_left = anchor
		strumline.anchor_right = anchor

	strumline.offset_top = authored["offset_top"] + y_nudge
	strumline.offset_bottom = authored["offset_bottom"] + y_nudge

	# Lane x positions are symmetric around the strumline's own origin
	# (-225/-75/75/225), so scaling them about zero widens the gap while
	# keeping the whole thing centred on the same point.
	for lane in authored["lanes"]:
		if not is_instance_valid(lane):
			continue

		var x: float = authored["lanes"][lane] * spacing_scale
		# Push each half outward to open the centre channel. Applied after the
		# spacing scale and by sign, so the two inner lanes move apart by
		# split_gap in total while the pairs themselves keep their scaled
		# spacing - widening the middle without stretching the sides.
		if split_gap != 0.0 and not is_zero_approx(x):
			x += (split_gap * 0.5) * signf(x)

		lane.position.x = x
		lane.scale = Vector2(note_scale, note_scale)

func _lanes_of(strumline: Control) -> Array[Control]:
	var out: Array[Control] = []
	for child in strumline.get_children():
		var control := child as Control
		# Lane0..3 are the only Control children; the anti-mash and grader
		# nodes are plain Nodes and filter themselves out here.
		if control != null:
			out.append(control)
	return out
