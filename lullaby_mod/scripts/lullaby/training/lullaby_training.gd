class_name LullabyTraining

## Which mechanic the console's Training tab asked for, and where to practise
## it.
##
## The Training tab was fully built and locked: three buttons - Pendulum,
## Pulse, Typing - wired to a training_button.gd whose _on_button_pressed()
## only played a click, behind a Home icon shipping disabled = true. This is
## the missing middle.
##
## The host is songs/test/test.tscn, Rubicon's own test level. It already has
## a chart, a clock, a health module, a judgment popup, lanes and the mobile
## controls, which is everything a practice run needs and nothing a song
## brings that would get in the way - no cutscenes, no sequence timeline, no
## story state to disturb.
##
## A static rather than a signal or an autoload because the request has to
## survive a scene change, which is exactly what Console.boot_enabled and
## MonochromeGameover.skip_first_part already do here.

enum Mechanic {
	NONE = 0,
	PENDULUM = 1,
	PULSE = 2,
	TYPING = 3,
}

const TEST_SONG := "res://songs/test/test.tscn"

const SCENES := {
	Mechanic.PENDULUM: "res://lullaby_mod/resources/funkin/songs/global/mechanics/mch_pendulum.tscn",
	Mechanic.PULSE: "res://lullaby_mod/resources/funkin/songs/chimera/mch_heartbeat.tscn",
	Mechanic.TYPING: "res://lullaby_mod/resources/funkin/songs/monochrome/scenes/mch_typing.tscn",
}

## Read and cleared by LullabyTrainingHost when the test level loads, so
## reaching the same level any other way is an ordinary run.
static var requested: Mechanic = Mechanic.NONE

static func take_request() -> Mechanic:
	var value: Mechanic = requested
	requested = Mechanic.NONE
	return value
