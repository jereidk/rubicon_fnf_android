extends CanvasItem

## Keeps a flashing effect off screen when the player has asked for no
## flashing lights.
##
## This is a suppressor and nothing else. It used to read
##
##     visible = Settings.get(&"game_flashing_lights")
##
## which also does the opposite job: with flashing lights ON it forces
## visible = true, overriding whatever the scene authored. Every node carrying
## this script is authored `visible = false`, and four of the six are
## full-screen black ColorRects - Chimera's BlackBoxofAwesomeness, UIBlack and
## Black2, and Monochrome's UIBlackFG - so on any save with flashing lights
## enabled they were all switched on at scene load.
##
## Being visible is only half of what makes a rect black; the other half is
## its alpha, and the animations own that. BlackBoxofAwesomeness is authored
## at color.a = 0, but its RESET writes color = Color(0, 0, 0, 1) and the
## `scene` animation's colour track has its first key at 181.8s, also opaque -
## and Godot holds a track's first value for everything before it, so for the
## first three minutes of the song that track reads full black. The only thing
## standing between that and the screen was the `visible = false` this script
## was overwriting. Monochrome's UIBlackFG and the Boyfriend-scream Cover do
## not even need an animation: they are authored at color.a = 1 already.
##
## That is the reported bug - a black graphic in front of Chimera from the
## moment the sprite plane starts, worse when a second animation stacks on it.
## The census caught it directly, naming BlackBoxofAwesomeness at coverage
## 1.00 while the song was running.
##
## Turning the effect ON is the animations' business: they key `visible`
## explicitly (113_reaching, approach and scene all do), so nothing needs this
## script to reveal anything. With flashing lights off the behaviour is
## unchanged - hidden, exactly as before.
func _ready() -> void:
	if not Settings.get(&"game_flashing_lights"):
		visible = false
