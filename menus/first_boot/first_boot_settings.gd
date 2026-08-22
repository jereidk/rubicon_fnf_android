extends Control

const INTRO_SCENE := "res://menus/intro/intro.tscn"

## Same pairing the console's Misc tab uses (list_button.gd's
## display_list/values_list), so the two rows cannot drift apart. The display
## names are deliberately NOT translated - a language is named in its own
## language on every language picker, which is also why "Español" is spelt
## that way in an English build.
const LANGUAGE_VALUES: Array[String] = ["en", "es"]

@export var language_button: OptionButton

## Only shown while the Collector's welcome has never played. Ticking it sets
## SaveData's "intro_seen" straight away, which is the same flag the shop
## reads - so the tour is skipped by making the save look like it already
## happened, rather than by adding a second condition next to the first.
@export var skip_intro_check: CheckBox

## Always shown, and bound to a Setting rather than to the flag. See
## Settings.lullaby_force_shop_intro for why the flag alone cannot express
## this: it also gates the entry voicelines.
@export var force_intro_check: CheckBox

func _ready() -> void:
	if language_button != null:
		var current: int = LANGUAGE_VALUES.find(Settings.lullaby_language)
		language_button.selected = maxi(current, 0)

	if skip_intro_check != null:
		# Decided once, here, rather than every frame: ticking the box writes
		# the very flag this reads, and a live condition would make the row
		# vanish under the finger that just ticked it.
		skip_intro_check.visible = not SaveData.get_flag(&"intro_seen")
		skip_intro_check.button_pressed = SaveData.get_flag(&"intro_seen")

	if force_intro_check != null:
		force_intro_check.button_pressed = Settings.lullaby_force_shop_intro

	for box: CheckBox in [skip_intro_check, force_intro_check]:
		if box != null:
			_light_unchecked_box(box)

## Makes an unticked box visible on this screen's dark panel.
##
## Godot's default `unchecked` icon is a near-black square at half alpha -
## measured off ThemeDB at mean RGB 0.10 and max alpha 0.50 - while `checked`
## is light (0.87) and shows fine. On a dark panel that means a ticked option
## reads as a checkbox and an unticked one reads as a plain label, which is
## the opposite of what a checkbox is for.
##
## Tinting cannot fix it: checkbox_unchecked_color multiplies, so a black
## icon stays black however it is coloured. The icon has to be replaced. It
## is rebuilt from the engine's own, keeping its alpha shape and therefore
## its exact size and metrics, rather than shipping two new PNGs for a
## sixteen-pixel square.
func _light_unchecked_box(box: CheckBox) -> void:
	var source: Texture2D = box.get_theme_icon(&"unchecked")
	if source == null:
		return

	var image: Image = source.get_image()
	if image == null:
		return
	image.convert(Image.FORMAT_RGBA8)

	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, minf(pixel.a * 1.5, 0.8)))

	box.add_theme_icon_override(&"unchecked", ImageTexture.create_from_image(image))

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

func _on_skip_intro_toggled(pressed: bool) -> void:
	SaveData.set_flag(&"intro_seen", pressed)
	SaveData.save()

func _on_force_intro_toggled(pressed: bool) -> void:
	Settings.lullaby_force_shop_intro = pressed
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
