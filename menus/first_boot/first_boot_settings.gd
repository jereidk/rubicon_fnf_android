extends Control

const INTRO_SCENE := "res://menus/intro/intro.tscn"

## Same pairing the console's Misc tab uses (list_button.gd's
## display_list/values_list), so the two rows cannot drift apart. The display
## names are deliberately NOT translated - a language is named in its own
## language on every language picker, which is also why "Español" is spelt
## that way in an English build.
const LANGUAGE_VALUES: Array[String] = ["en", "es", "pt_BR"]

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

## The quality row, so _ready can point it at what is actually saved.
##
## It was never wired, and the scene ships `selected = 4`, so this screen said
## "High" on every launch whatever was stored - which is exactly the report:
## "por cada sesion se ve High, cuando yo habia puesto Optimized en una sesion
## anterior". The saved values really were Optimized; only the row was lying.
## That is worse than cosmetic: this row is also how the player checks what they
## are running, and a wrong readout invites re-picking a preset already set.
@export var preset_button: OptionButton

## The diagnostics log, on the one screen every launch passes through.
##
## It lives in the console's Misc tab too, and that was the only way to reach
## it - which is fine for a setting nobody needs and wrong for this one. The
## log now ships OFF, so the moment it is actually wanted is the moment someone
## is about to reproduce a bug, and making them enter the shop, walk to the
## console, switch it on and then restart to catch the boot is the wrong shape
## for that. Here it is two taps before anything has happened, which is also
## the only place it can be turned on in time to record a load.
##
## An OptionButton and not a CheckBox, for the reason the Intro row above
## records: Godot's `unchecked` icon is a near-black square at half alpha on a
## dark panel, so a box reads as a plain label until it is ticked.
##
## THREE states, not two, because GPUSPLIT belongs here and nests inside this
## one rather than beside it.
##
##   0  Off                        no log
##   1  On                         the log
##   2  On + GPU split (flashes)   the log, plus the five-way GPU breakdown
##
## GPUSPLIT lived only in the console's Misc tab, which is inside the
## Collector's Shop: switching it on meant entering the shop, crossing to the
## TV, turning it on, opening Settings, finding Misc and walking back. What it
## measures is the frames of one particular scene, so half the time the scene
## somebody wanted to measure was the one they had to cross to reach the
## switch.
##
## It is a third state and not a fourth row for two independent reasons, and
## the first is the one that matters: GPU split WITHOUT the log does nothing at
## all. The diagnostics node calls `set_process(false)` and returns when the
## log is off, so `_step_gpu_split()` never runs - and its output is written
## into that same log file. Two separate rows would offer a combination that
## silently does nothing.
##
## The second is that the panel had no room. Measured at 1920x1080, the content
## scale space this project authors in: the options panel is 1080 tall EXACTLY,
## and a fourth row took it to 1183. The header of this file already records
## the same wall being hit once before - "two extra rows made it taller than
## 720px" - so this is the second time the layout has been at its ceiling, and
## a row that has to exist would have shipped it broken.
##
## WHAT GPU SPLIT DOES, so the label is not the only explanation. Every 20
## seconds it switches one thing off for ONE frame and subtracts: the lighting,
## the overdraw, the whole 3D pass, the shadows, the post-processing. Five
## turns rotating, about 100 seconds for a full round, after which `gpu=13.7ms`
## is five numbers instead of one.
##
## The wrong frame is the price and it is on the label. The player reported it
## without knowing the feature existed - "un flash blanco opaco" - so the
## option says "flashes" rather than springing it on them.
@export var log_button: OptionButton

## The GPU pipeline cache, on the only screen a phone this breaks can reach.
##
## Godot writes a Vulkan pipeline cache on the first run and hands it back to
## the driver on the next, and a weak mobile driver choking on the cache it
## wrote itself is a real failure - reported as "the game opens the first time
## and closes itself at the end of every load after that". Settings detects it
## and blocks the cache on its own, but it needs two failed launches and only
## takes effect on the one after that, so a phone it is happening to dies
## three times before it heals.
##
## This is the row that lets someone skip the wait, and the reason it is HERE
## and not in the console's Misc tab with everything else: the console lives
## inside the Collector's Shop, and the shop's load is exactly where these
## devices die. A setting only reachable past the crash is not reachable.
@export var gpu_cache_button: OptionButton

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

	if log_button != null:
		# El split solo puede estar puesto con el log puesto, asi que el estado 2
		# implica el 1 y no hace falta comprobar los dos.
		log_button.selected = (2 if Settings.diagnostics_gpu_split
			else (1 if Settings.lullaby_diagnostics_log else 0))

	_show_gpu_cache()
	_show_current_preset()

## Points the GPU cache row at what is stored, and says what "Automatic" has
## actually decided.
##
## The label matters more here than on the other rows. Automatic is a row that
## reads as "nothing is happening", and on a phone that has been blocked
## something very much is - it is running cold pipelines on every launch. If
## the player is looking at this row at all it is because the game has been
## crashing, and "Automatic" with no state is the least useful thing it could
## say to them.
func _show_gpu_cache() -> void:
	if gpu_cache_button == null:
		return

	gpu_cache_button.selected = clampi(Settings.lullaby_pipeline_cache_mode, 0, 2)
	if gpu_cache_button.item_count > 0:
		# tr() by hand: built here rather than authored on the node, so the
		# Control's auto-translation never sees it.
		gpu_cache_button.set_item_text(0, "%s (%s)" % [
			tr("Automatic"),
			tr("off") if Settings.lullaby_pipeline_cache_blocked else tr("on"),
		])

## Index matches Settings.PipelineCacheMode: 0 automatic, 1 keep, 2 discard.
##
## Applied through Settings rather than written here, so what each mode means
## is described in one place - and so choosing Discard blocks the write
## immediately instead of at the next launch.
func _on_gpu_cache_changed(index: int) -> void:
	Settings.set_pipeline_cache_mode(index)
	_show_gpu_cache()

## Index 1 is On, matching the row's own order.
##
## apply_settings() rather than only writing the var, for the same reason the
## language row calls it: the log reads the setting when it decides whether to
## open its file, and nothing re-reads it on its own.
## Index 1 and 2 are both On; 2 adds GPU split. See log_button's docstring.
##
## apply_settings() rather than only writing the var, for the same reason the
## language row calls it: the log reads the setting when it decides whether to
## open its file, and nothing re-reads it on its own.
##
## save() persists the log choice and deliberately does NOT persist the split.
## That is not an oversight in the ordering: `diagnostics_gpu_split` is the one
## Settings var with no prefix, and save() only writes prefixed vars, so it is
## skipped whatever the order. The name has no prefix on purpose - an earlier
## build shipped the split on by default, it got written into the settings.ini
## of every phone that ran it, and load_from() restored it over the new default
## ("el destello blanco sigue" after it had supposedly been turned off). So the
## row comes back reading Off or On, never On+split, and no install returns
## flashing.
func _on_log_changed(index: int) -> void:
	Settings.lullaby_diagnostics_log = index >= 1
	Settings.diagnostics_gpu_split = index == 2
	Settings.apply_settings()
	Settings.save()

## Points the quality row at whatever is actually saved.
##
## Matched with the preset's own `matches()`, the same comparison the console's
## row uses, so index 0 - CUSTOM, which the scene ships disabled - appears
## exactly when the saved values are nobody's preset, rather than being a fifth
## thing this screen decides on its own.
func _show_current_preset() -> void:
	if preset_button == null:
		return
	for index in range(1, 5):
		var preset: LullabyQualityPreset = _preset_for_index(index)
		if preset != null and preset.is_matching(Settings):
			preset_button.selected = index
			return
	preset_button.selected = 0

## Shared by the row that reads the setting and the row that writes it, so the
## two cannot drift.
func _preset_for_index(index: int) -> LullabyQualityPreset:
	match index:
		1: return Settings.PRESET_VERY_LOW
		2: return Settings.PRESET_LOW
		3: return Settings.PRESET_MEDIUM
		4: return Settings.PRESET_HIGH
	return null

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
	var preset: LullabyQualityPreset = _preset_for_index(index)
	if preset == null:
		return

	preset.apply(Settings)
	Settings.apply_settings()
	Settings.save()

func apply_and_continue() -> void:
	SceneChanger.change_to(INTRO_SCENE, &"hypno")
