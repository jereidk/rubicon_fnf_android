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
	# is_midscroll_active(), not game_centered: VSlice forces midscroll on
	# (see Settings.is_midscroll_active). This is the value the songs'
	# AnimationTrees advance on ("settings_centered" / "not settings_centered").
	settings_centered = Settings.is_midscroll_active()
	settings_speed_multiplier = Settings.game_speed_multiplier
	settings_baby_mode = Settings.lullaby_baby_mode
	settings_post_processing = Settings.graphics_post_processing
	settings_autoplay = Settings.game_autoplay or LullabyShowcase.is_active()

	for controller: RubiconLevelNoteController in playable_controllers:
		controller.inputs = Settings.get_level_note_inputs()
		controller.scroll_speed_multiplier *= Settings.game_speed_multiplier

		# offset_input (judgment timing) and offset_note_position (note
		# drawing) both exist again - they were missing from this fork, so
		# the console's Offset and Visual Offset rows silently did nothing.
		# The `in` guards stay: they cost nothing and keep this working if a
		# controller subclass ever drops them again.
		if "offset_input" in controller:
			controller.offset_input = Settings.game_offset
		if "offset_note_position" in controller:
			controller.offset_note_position = Settings.game_visual_offset

		for handler_id in controller.note_handlers:
			var handler: RubiconLevelNoteHandler = controller.note_handlers[handler_id]
			if handler is RubiconLevelManiaNoteHandler and "allow_misplays" in handler:
				handler.allow_misplays = settings_ghost_tapping
			if handler.settings != null and "leniency_multiplier" in handler.settings:
				handler.settings.leniency_multiplier = Settings.game_timing_leniency
