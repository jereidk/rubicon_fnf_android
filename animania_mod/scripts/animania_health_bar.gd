@tool
extends RubiconHealthBar
## Animania's health bar: a drawn stroke, not a progress rectangle.
##
## The mod ships three pieces in assets/shared/images/ui/healthbar - HEALTHBAR.png (774x51,
## the black outline, hollow inside), WHITEBAR.png (728x37, the fill) and evil-grad.png
## (364x37, exactly half the fill, a red-to-white gradient). The fill being WHITE and
## separate from the outline is what says the colours come from code: each half is tinted
## with the character's own healthIcon.color.
##
## Measured against a capture of the mod running: the stroke is 23-24px thick on a 1280x720
## frame, which is WHITEBAR's own thickness, so it is drawn at scale 1. Its ends sit at
## y=67 and its middle at y=57 - an arch. The asset arcs the other way, so it is drawn
## MIRRORED VERTICALLY. Left of the icons the stroke measures (135, 125, 200) against
## tadano's #7D6EC7, right of them (133, 95, 156) against komi's #794F92; the cross
## pairings are off by 1.58x and 0.78x on a channel, so there is nothing to weigh up.
##
## Rubicon drives the icons off a Path2D, and that is left alone: the split between the two
## halves is put exactly under the follow point, so the bar's own fill and the icons cannot
## drift apart whatever the health does.
##
## evil-grad.png is vendored but not used yet. It is half the fill wide and fades red to
## white, which reads as a warning over the losing half - but the only capture of the bar
## there is sits at 50% health, where it does not appear, so what triggers it is not known.

## The fill's two halves. Both show the same texture, region-clipped either side of the
## split, so there is no seam to line up.
@export var player_fill: Sprite2D
@export var opponent_fill: Sprite2D

## tadano.json and komi.json's healthIcon.color. The player's half is the LEFT one - the
## same swap the strumlines make, and what the capture measures.
@export var player_color: Color = Color("7d6ec7")
@export var opponent_color: Color = Color("794f92")


func _ready() -> void:
	super()
	_repaint()


func _on_value_changed(new_value: float) -> void:
	super(new_value)
	_repaint()


## Moves the seam to wherever the icons are.
func _repaint() -> void:
	if player_fill == null or opponent_fill == null:
		return
	var texture: Texture2D = player_fill.texture
	if texture == null:
		return

	var size: Vector2 = texture.get_size()
	var split: float = roundf(clampf(get_as_ratio(), 0.0, 1.0) * size.x)

	player_fill.region_enabled = true
	player_fill.region_rect = Rect2(0.0, 0.0, split, size.y)
	player_fill.modulate = player_color

	# Its region starts at the split, and a Sprite2D draws a region at its own position, so
	# the node has to move with it or the right half slides over the left.
	opponent_fill.region_enabled = true
	opponent_fill.region_rect = Rect2(split, 0.0, size.x - split, size.y)
	opponent_fill.position.x = split
	opponent_fill.modulate = opponent_color
