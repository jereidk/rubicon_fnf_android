extends Control

## Port of Lullaby's scn_debug_select.tscn — the demo's song-select hub.
## Song scenes (chimera/monochrome/safety_lullaby) haven't been ported to
## Rubicon yet, so "Play" currently always loads songs/test/test.tscn
## regardless of the dropdown selection until real charts land.

const WARNING_SCENE := "res://menus/warning/warning.tscn"
const PLACEHOLDER_SONG_SCENE := "res://songs/test/test.tscn"

@onready var song_selector: OptionButton = %OptionButton
@onready var not_legole_fart: AudioStreamPlayer = %NotLegoleFart

func _on_play_pressed() -> void:
	SceneChanger.change_to(PLACEHOLDER_SONG_SCENE, &"hypno")

func _on_warning_pressed() -> void:
	SceneChanger.change_to(WARNING_SCENE, &"hypno")

func _on_logo_pressed() -> void:
	%Logo.hide()
	%Baldgo.show()
	not_legole_fart.play()
