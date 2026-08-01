class_name LullabySongSettings extends Node

@export var use_user_settings_on_runtime: bool = true
@export var playable_controllers: Array[RubiconLevelNoteController] = []

@export_group("Settings", "settings_")
@export var settings_downscroll: bool = false
@export var settings_centered: bool = false
@export var settings_speed_multiplier: float = 1.0
@export var settings_baby_mode: bool = false
@export var settings_post_processing: LullabySettings.PostProcessing = LullabySettings.PostProcessing.HIGH
@export var settings_ghost_tapping: bool = true
@export var settings_autoplay: bool = false

func _ready() -> void :
	if Engine.is_editor_hint() or not use_user_settings_on_runtime:
		return

	_update()

	Settings.applied.connect(_update)

func _update() -> void :
	settings_downscroll = Settings.game_downscroll
	settings_centered = Settings.game_centered
	settings_speed_multiplier = Settings.game_speed_multiplier
	settings_baby_mode = Settings.lullaby_baby_mode
	settings_post_processing = Settings.graphics_post_processing
	settings_autoplay = Settings.game_autoplay or Settings.lullaby_showcase_mode

	for controller: RubiconLevelNoteController in playable_controllers:
		controller.inputs = Settings.get_level_note_inputs()
		controller.scroll_speed_multiplier *= Settings.game_speed_multiplier

		# Rubicon note: this engine build's RubiconLevelNoteController has no
		# offset_input/offset_note_position (input/visual timing offset) and
		# RubiconLevelManiaNoteHandler has no allow_misplays (ghost-tap
		# toggle) — those settings are still exposed in the console UI but
		# don't have anything to drive yet on this engine version.
		if "offset_input" in controller:
			controller.offset_input = Settings.game_offset
		if "offset_note_position" in controller:
			controller.offset_note_position = Settings.game_visual_offset

		for handler_id in controller.note_handlers:
			var handler: RubiconLevelNoteHandler = controller.note_handlers[handler_id]
			if handler is RubiconLevelManiaNoteHandler and "allow_misplays" in handler:
				handler.allow_misplays = settings_ghost_tapping
