extends AudioStreamPlayer3D

## Every console sfx used to live in sfx/shop/console/ as a .wav, so the path
## was hardcoded. The Hacks tab's prank code wants sfx/misc/'s fart sound,
## which is neither - falls back there before giving up, rather than growing
## a per-caller special case.
func _on_console_play_sound(filename: String) -> void :
	var path: String = "res://lullaby_mod/resources/audio/sfx/shop/console/" + filename + ".wav"
	if not ResourceLoader.exists(path):
		path = "res://lullaby_mod/resources/audio/sfx/misc/" + filename + ".mp3"
	stream = load(path)
	play()
