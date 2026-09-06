@tool
class_name RubiconLevelNoteMetadata extends Resource

@export var scene : PackedScene

@export_group("Predefines", "predefine_")
@export var predefine_should_miss : bool = false
@export var predefine_count_towards_score : bool = true
## HQ/native seam: notes of this type do not make characters sing when hit.
## Used by the mod's "No Animation" and mechanic notes (the character still
## plays its normal miss animation on a miss).
@export var suppress_sing : bool = false
## HQ/native seam: hits/misses of this note type do not move health at all.
## Used by Bullet/Timestop mechanics which manage health themselves.
@export var suppress_health : bool = false

func note_hit(result : RubiconLevelNoteHitResult) -> RubiconLevelNoteHitResult:
    return result