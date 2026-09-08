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

## `healthIcon.color` de cada personaje. Los que traen puestos son los de tadano y komi,
## que es lo que hasta ahora se pintaba en TODAS las canciones porque la escena de la barra
## es compartida y nadie los cambiaba.
@export var player_color: Color = Color("7d6ec7")
@export var opponent_color: Color = Color("794f92")

## De que lado crece la mitad del jugador.
##
## En Funkin es la DERECHA. En phone-call es la izquierda, y no por capricho: esa cancion
## hace `healthBar.flipped = true` -el mismo intercambio que hacen sus dos filas de notas-
## y la captura del mod lo confirma, con el #7D6EC7 de tadano a la izquierda de los iconos
## y el #794F92 de komi a la derecha.
##
## Estaba escrito a fuego a la izquierda, o sea con el volteo de phone-call metido dentro
## de la barra compartida. dadbattle lo pone en false y se ve como en Funkin.
@export var player_on_left: bool = true


func _ready() -> void:
	super()
	# Connected here rather than in the scene. RubiconHealthBar leans on its .tscn carrying
	# `[connection signal="value_changed"]`, and a connect() made while building a scene in
	# code is NOT stored by PackedScene.pack() unless it is flagged CONNECT_PERSIST - so the
	# built bar came out with no connection at all and sat frozen at 50% for the whole song,
	# icons included, because the parent updates the path follow from that same handler.
	if not value_changed.is_connected(_on_value_changed):
		value_changed.connect(_on_value_changed)
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
	# Lo que le toca al JUGADOR, siempre medido como anchura, no como lado.
	var mine: float = roundf(clampf(get_as_ratio(), 0.0, 1.0) * size.x)

	# El de la izquierda empieza en 0 y el de la derecha en la costura; y un Sprite2D dibuja
	# su region en su propia posicion, asi que el de la derecha tiene que MOVERSE con ella o
	# se le echa encima al otro.
	var seam: float = mine if player_on_left else size.x - mine
	var left: Sprite2D = player_fill if player_on_left else opponent_fill
	var right: Sprite2D = opponent_fill if player_on_left else player_fill

	left.region_enabled = true
	left.region_rect = Rect2(0.0, 0.0, seam, size.y)
	left.position.x = 0.0
	left.modulate = player_color if player_on_left else opponent_color

	right.region_enabled = true
	right.region_rect = Rect2(seam, 0.0, size.x - seam, size.y)
	right.position.x = seam
	right.modulate = opponent_color if player_on_left else player_color
