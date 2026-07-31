extends AudioStreamPlayer3D

func _on_console_play_sound(filename: String) -> void :
	stream = load("res://lullaby_mod/resources/audio/sfx/shop/console/" + filename + ".wav")
	play()
