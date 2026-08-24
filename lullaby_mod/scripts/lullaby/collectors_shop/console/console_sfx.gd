extends AudioStreamPlayer3D

## Where console sounds live, and in what shapes they might be found.
##
## Two folders because the Hacks tab's prank code wants sfx/misc/'s fart sound
## and everything else is in sfx/shop/console/. Four extensions because that
## folder genuinely holds four kinds: .wav, .ogg, .res and .mp3.
##
## The pair used to be hardcoded as "console/<name>.wav, else misc/<name>.mp3",
## and the device error log of 2026-08-24 caught what that costs:
##
##     No loader found for resource:
##     res://lullaby_mod/resources/audio/sfx/misc/sfx_soulroom_select.mp3
##
## sfx_soulroom_select is a .res in shop/console/. Neither guess matched it, so
## the console's select sound has been silent. Swept every name that reaches
## play_sound and it was the only one broken - but sfx_console_startup.ogg and
## sfx_soulroom_power.ogg sit in the same folder and would have failed the same
## way the day anything emitted them, which is why this resolves instead of
## guessing twice.
const SOUND_DIRS: Array[String] = [
	"res://lullaby_mod/resources/audio/sfx/shop/console/",
	"res://lullaby_mod/resources/audio/sfx/misc/",
]
const SOUND_EXTENSIONS: Array[String] = [".wav", ".ogg", ".res", ".mp3"]

func _on_console_play_sound(filename: String) -> void :
	for dir: String in SOUND_DIRS:
		for extension: String in SOUND_EXTENSIONS:
			var path: String = dir + filename + extension
			if ResourceLoader.exists(path):
				stream = load(path)
				play()
				return

	# Said once, plainly, rather than handed to load() to fail on: the engine's
	# "No loader found" names a path this function invented, which reads like a
	# missing file rather than like a name nothing matches.
	push_warning("console: no hay sonido llamado '%s' en %s"
		% [filename, ", ".join(SOUND_DIRS)])
