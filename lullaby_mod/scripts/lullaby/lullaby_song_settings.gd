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

	_apply_speed_hack(Settings.lullaby_speed_hack)

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
			# An autoplayed lane normally loses its HIT state inside the same
			# frame it gains it, so the receptor never plays its confirm and
			# the strumline sits there dead while the notes go past. See
			# lane_autoplay_hit_lingers. Only ever turned on for a showcase:
			# the only strumline autoplayed during a real run is the
			# opponent's, and all three songs hide it, so switching this on
			# generally would change nothing except how faithful the port is.
			if "lane_autoplay_hit_lingers" in handler:
				handler.lane_autoplay_hit_lingers = LullabyShowcase.is_active()
			if handler.settings != null and "leniency_multiplier" in handler.settings:
				handler.settings.leniency_multiplier = Settings.game_timing_leniency

## Plays the song at `rate` times its tempo.
##
## Cheap here because of how a level keeps time: the clock reads its position
## straight off one AnimationPlayer (see RubiconLevelClock.time_milliseconds),
## and that animation drives the chart, the camera, the characters and every
## mechanic keyed to the song. Scaling it scales all of them at once, and the
## notes follow because they position themselves from the clock.
##
## The audio is the only thing that does not, since it runs free once
## started, so every player gets a matching pitch_scale. That makes the song
## higher or lower pitched, which Godot gives no way around - there is no
## time-stretch for an AudioStreamPlayer - and is what every other engine's
## speed hack does too.
##
## RubiconLevelSong.check_for_desync() then keeps them locked: it compares
## the reference player's position against the animation's every measure and
## re-seeks the audio if they drift past 45ms. Both sides are scaled by the
## same factor, so that check goes on working untouched.
func _apply_speed_hack(rate: float) -> void:
	var level: RubiconLevel = _find_level()
	if level == null or level.clock == null:
		return

	var timeline: AnimationPlayer = level.clock.animation_player
	if timeline != null:
		timeline.speed_scale = rate

	for song: RubiconLevelSong in _find_songs(level):
		for player: AudioStreamPlayer in song.audio_players:
			if player != null:
				player.pitch_scale = rate

## The level this settings node belongs to. Walked rather than exported: the
## three songs do not agree on what the clock node is called - Monochrome and
## Chimera have "RubiconLevelClock", safety_lullaby has "Clock" - so anything
## that goes by name works in two scenes out of three, which is worse than
## not working at all.
func _find_level() -> RubiconLevel:
	var node: Node = self
	while node != null:
		if node is RubiconLevel:
			return node
		node = node.get_parent()
	return null

func _find_songs(root: Node) -> Array[RubiconLevelSong]:
	var out: Array[RubiconLevelSong] = []
	for child in root.get_children():
		if child is RubiconLevelSong:
			out.append(child)
		out.append_array(_find_songs(child))
	return out
