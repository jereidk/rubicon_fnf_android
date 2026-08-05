class_name LullabyNoteLayout extends Resource

## How the note lanes are arranged on screen. Same shape as
## LullabyQualityPreset: a resource per layout, so adding one is a .tres and
## a list entry rather than a code change.
##
## The VSlice layout comes from NightmareVision's impostor-legacy-android
## branch (source/funkin/objects/note/StrumNote.hx), where its constants were
## measured by overlaying real device screenshots on the reference. Those are
## HaxeFlixel numbers against a 1280x720 stage with its own anchoring, so
## they are NOT copied across - what carries over is the *proportions* that
## make the layout recognisable:
##
##   - the player strumline sits centred rather than off to one side
##   - notes are larger (VSLICE_PLAYER_SIZE_SCALE 0.79 against a 104px base)
##   - lanes are spaced further apart than the notes grew
##     (VSLICE_PLAYER_SPACING_MULT 1.77), which is what reads as the "bigger
##     separator"
##   - the opponent strumline is much smaller (VSLICE_OPPONENT_SCALE 0.34)
##
## Expressed here as multipliers on whatever the song scene already uses, so
## a song that lays its lanes out differently still gets a sane result and
## the numbers stay tunable without touching code.

@export var name: String = "Classic"

## Horizontal anchor of each strumline, 0 = left edge, 1 = right edge. The
## scenes ship 0.75 / 0.25; VSlice centres the player.
@export_range(0.0, 1.0, 0.01) var player_anchor: float = 0.75
@export_range(0.0, 1.0, 0.01) var opponent_anchor: float = 0.25

## Multipliers on the lane spacing the scene was authored with (150px in
## every Lullaby song). Above 1.0 pushes the lanes apart.
@export var player_spacing_scale: float = 1.0
@export var opponent_spacing_scale: float = 1.0

## Extra gap opened in the MIDDLE of the strumline, in pixels, split evenly
## either side of centre. This is the part of VSlice that a uniform spacing
## multiplier cannot reproduce: its lanes are not evenly spread, they are two
## pairs with a wide channel between them (left/down .... up/right).
## StrumNote.hx calls it VSLICE_PLAYER_SPLIT_GAP_COEFF; without it the layout
## is merely "wider", which is what the first implementation got wrong.
@export var player_split_gap: float = 0.0
@export var opponent_split_gap: float = 0.0

## Multipliers on note size.
@export var player_note_scale: float = 1.0
@export var opponent_note_scale: float = 1.0

## Extra vertical nudge in pixels, positive = down. VSlice's own layout
## needed one of these (VSLICE_PLAYER_Y_NUDGE_DOWNSCROLL) once measured
## against a screenshot, so the knob exists here too.
@export var player_y_nudge: float = 0.0
@export var opponent_y_nudge: float = 0.0
