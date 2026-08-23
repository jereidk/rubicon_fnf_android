extends Control

const INTRO_SCENE := "res://menus/intro/intro.tscn"

## Same pairing the console's Misc tab uses (list_button.gd's
## display_list/values_list), so the two rows cannot drift apart. The display
## names are deliberately NOT translated - a language is named in its own
## language on every language picker, which is also why "Español" is spelt
## that way in an English build.
const LANGUAGE_VALUES: Array[String] = ["en", "es"]

@export var language_button: OptionButton

## One row for both halves of "what should the Collector's welcome do", which
## is two questions that are never asked at the same time:
##
##   never seen it   Play it  /  Skip it            -> SaveData "intro_seen"
##   seen it         Leave it /  Replay on launch   -> Settings.lullaby_force_shop_intro
##
## It was two CheckBoxes and all three of the player's complaints came from
## that shape: 47 characters of label made the panel wider than the screen,
## two extra rows made it taller than 720px, and Godot's `unchecked` icon is
## a near-black square on a dark panel so the box read as a plain label. An
## OptionButton is the control the two rows above it already use, it costs one
## row instead of two, and it labels its own state.
@export var intro_button: OptionButton

## Whether the row is asking the never-seen question or the seen-it question.
## Decided once in _ready, not per frame: choosing "Skip it" writes the very
## flag this reads, and a live condition would relabel the row under the
## finger that just used it.
var _intro_already_seen: bool = false

## Kept as the source of the two option labels rather than authoring them in
## the scene, because the row has to say different things in the two states
## and the scene can only hold one pair.
const INTRO_FIRST_TIME: Array[String] = ["Play it", "Skip it"]
const INTRO_SEEN: Array[String] = ["Leave it", "Replay on launch"]

func _ready() -> void:
	if language_button != null:
		var current: int = LANGUAGE_VALUES.find(Settings.lullaby_language)
		language_button.selected = maxi(current, 0)

	_intro_already_seen = SaveData.get_flag(&"intro_seen")
	if intro_button != null:
		var labels: Array[String] = INTRO_SEEN if _intro_already_seen else INTRO_FIRST_TIME
		intro_button.clear()
		for label: String in labels:
			# tr() by hand: these are built here rather than authored on the
			# node, so Control auto-translation never sees them.
			intro_button.add_item(tr(label))
		intro_button.selected = 1 if (_intro_already_seen
			and Settings.lullaby_force_shop_intro) else 0

func _on_language_changed(index: int) -> void:
	if index < 0 or index >= LANGUAGE_VALUES.size():
		return
	Settings.lullaby_language = LANGUAGE_VALUES[index]
	# apply_settings() is what calls TranslationServer.set_locale(); every
	# Control on this screen re-reads its own text from
	# NOTIFICATION_TRANSLATION_CHANGED, so the rest of the panel relabels
	# itself without anything here touching it.
	Settings.apply_settings()
	Settings.save()

## Index 1 is the non-default in both states: "Skip it" before the tour has
## ever played, "Replay on launch" after.
func _on_intro_choice_changed(index: int) -> void:
	var chose_second: bool = index == 1

	if not _intro_already_seen:
		# Skipping is done by making the save look like the tour already
		# happened, which is the same flag the shop reads - rather than adding
		# a second condition next to the first.
		SaveData.set_flag(&"intro_seen", chose_second)
		SaveData.save()
		return

	Settings.lullaby_force_shop_intro = chose_second
	# Armed here too, because this screen sits between the launch that arms it
	# and the shop that spends it - picking it has to reach the very next
	# visit, and unpicking it has to call that off.
	Settings.force_shop_intro_pending = chose_second
	Settings.save()

## Uses the same LullabyQualityPreset resources (render_scale, shadows,
## ssao/ssil, post-processing, shader effects) the console's Settings
## screen applies - this used to only flip 2D MSAA/screen-space AA via the
## long-dead apply_quality_preset()/QualityPreset enum (removed from
## settings.gd, this was its only caller), which barely changed anything
## and was never saved, so picking a preset here didn't survive past this
## screen.
func _on_preset_changed(index: int) -> void:
	var preset: LullabyQualityPreset
	match index:
		1: preset = Settings.PRESET_VERY_LOW
		2: preset = Settings.PRESET_LOW
		3: preset = Settings.PRESET_MEDIUM
		4: preset = Settings.PRESET_HIGH
		_: return

	preset.apply(Settings)
	Settings.apply_settings()
	Settings.save()

func apply_and_continue() -> void:
	SceneChanger.change_to(INTRO_SCENE, &"hypno")
