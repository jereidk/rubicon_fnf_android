@tool
class_name LullabyVocalMuter
extends Node


@export var target_player: AudioStreamPlayer = null
@export var targets: Array[RubiconLevelNoteController] = []
@onready var miss_sfx: AudioStreamPlayer = get_child(0)


func _ready() -> void :
	for target: RubiconLevelNoteController in targets:
		target.note_changed.connect(_on_note_changed)
		# Rubicon note: this engine build's RubiconLevelManiaNoteHandler has
		# no "misplayed" signal (ghost-tap/anti-mash penalty isn't
		# implemented here), so the primary miss-mutes-vocals behavior
		# below via note_changed is what actually drives this mechanic.
		for handler_id in target.note_handlers:
			var handler: RubiconLevelNoteHandler = target.note_handlers[handler_id]
			if handler is RubiconLevelManiaNoteHandler and handler.has_signal(&"misplayed"):
				handler.misplayed.connect(_on_misplay)

func _on_note_changed(result: RubiconLevelNoteHitResult, _has_ending_row: bool) -> void :
	if not is_instance_valid(target_player):
		return

	if result.scoring_rating == RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS:
		target_player.volume_linear = 0.0
		miss_sfx.pitch_scale = randf_range(0.95, 1.05)
		miss_sfx.play()
	else:
		target_player.volume_linear = 1.0

func _on_misplay(_lane_id: int) -> void :
	target_player.volume_linear = 0.0
	miss_sfx.pitch_scale = randf_range(0.95, 1.05)
	miss_sfx.play()
