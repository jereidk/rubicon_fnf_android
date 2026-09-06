extends RubiconLevelNoteMetadata
class_name HQNoteMetadata

## HQ mechanic note behaviours, ported from the mod's "Bullet Note.hx" and
## "Timestop Note.hx" + NoteHandler/StatusEffects:
##
## Bullet  - pressing the note dodges it (FX + shoot), missing it drains
##           health and bleeds the player for a few seconds.
## Timestop - pressing it freezes the song (inputs off, vocals muted, grey
##           overlay) and counts as a miss, letting it pass costs nothing.

enum Behavior { NORMAL, BULLET, TIMESTOP }

@export var behavior: Behavior = Behavior.NORMAL

func note_hit(result: RubiconLevelNoteHitResult) -> RubiconLevelNoteHitResult:
	if result.handler == null:
		return result
	match behavior:
		Behavior.BULLET:
			_on_bullet(result)
		Behavior.TIMESTOP:
			_on_timestop(result)
	return result


func _on_bullet(result: RubiconLevelNoteHitResult) -> void:
	var tree := result.handler.get_tree()
	if tree == null:
		return
	if result.scoring_rating == RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS:
		HQSaves.hq_bullet_note_missed = true
		tree.call_group(&"hq_note_mechanics", "_hq_bullet_miss")
	else:
		var direction: int = int(result.handler.get("lane_id")) if result.handler.get("lane_id") != null else 0
		tree.call_group(&"hq_note_mechanics", "_hq_bullet_hit", direction)


func _on_timestop(result: RubiconLevelNoteHitResult) -> void:
	var handler := result.handler
	var tree := handler.get_tree()
	if tree == null:
		return

	var bad_window: float = 9999.0
	var settings: Resource = handler.get("settings")
	if settings != null and settings.get("judgment_window_bad") != null:
		var leniency: Variant = settings.get("leniency_multiplier")
		bad_window = float(settings.judgment_window_bad) * (float(leniency) if leniency != null else 1.0)

	if absf(result.time_distance) <= bad_window:
		# Pressed: freeze + the mod counts a pressed timestop as a miss.
		HQSaves.hq_timestop_note_hit = true
		result.scoring_rating = RubiconLevelNoteHitResult.Judgment.JUDGMENT_MISS
		result.scoring_value = 0.0
		tree.call_group(&"hq_note_mechanics", "_hq_timestop_hit")
	else:
		# Passed without pressing: the mod erases the note, no penalty.
		# Unjudged (JUDGMENT_NONE) so it never misses, never breaks combo and
		# never counts in accuracy; value 1.0 keeps the score ceiling whole.
		result.scoring_rating = RubiconLevelNoteHitResult.Judgment.JUDGMENT_NONE
		result.scoring_hit = RubiconLevelNoteHitResult.Hit.HIT_NONE
		result.scoring_value = 1.0
