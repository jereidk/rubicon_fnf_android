extends Node2D
## The hit splash and the hold cover for one lane.
##
## Rubicon has no slot for either: a Lane is a receptor with a three-state AnimationTree and
## nothing else, and Note.tscn draws the note and its trail. Animania's amtake-base note
## style ships both effects and turns them on (`noteSplash.enabled`, `holdNoteCover.enabled`
## in amtake-base.json), so they are new nodes driven from the handler's own signals.
##
## Numbers are amtake-base.json's, scaled 1.5x into this project's 1920x1080 where they are
## screen distances - the two atlases themselves are already Funkin-sized, like the notes
## and receptors, so only the OFFSETS scale.

## noteSplash.scale and holdNoteCover.scale.
const SPLASH_SCALE := 0.9
const COVER_SCALE := 0.7
## Funkin is 1280x720 and this project is 1920x1080.
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
## noteSplash.rotationVariance, in degrees, applied either way from centre.
const ROTATION_VARIANCE := 180.0
## holdNoteCover.offsets is NOT applied, and that is the source's decision rather than an
## omission here. `amtake-base.hx` overrides `getHoldCoverOffsets()` to negate y under
## downscroll, but the line in `buildNoteHoldCoverSprite` that would push the sprite by it -
## `target.frameOffset.set(...)` - is **commented out** in the mod. So the cover sits on the
## receptor.
##
## The first version of this port applied the offset anyway, from reading the override and
## assuming something used it. On a device the covers hung 90px below the receptors,
## detached from the notes they belong to. `flipY = Preferences.downscroll` on line 30 does
## still apply, so the sprite is flipped and not offset.
const COVER_OFFSET := Vector2.ZERO
## amtake-base.json declares two splash variants per lane and Funkin picks between them.
const SPLASH_VARIANTS := 2

## AnimaniaModule.onNoteHit splashes the two sides by DIFFERENT rules, and this port had
## both on the player's. Funkin splashes the player only on a perfect; the opponent gets
## `FlxG.random.bool(60)` - six notes in ten, at random, whatever the judgment.
##
## It matters because the opponent is autoplayed and therefore perfect on every note, so one
## rule for both meant komi's side splashed on all 167 of hers.
const OPPONENT_SPLASH_CHANCE := 0.6

const LANES := ["left", "down", "up", "right"]

@export var effects: SpriteFrames
## The lane this belongs to - a RubiconLevelManiaNoteHandler.
@export var handler: Node

var _splash: AnimatedSprite2D
var _cover: AnimatedSprite2D
var _holding: bool = false
## Which note the last splash belonged to. A press that hits nothing leaves
## `last_hit_note_index` pointing at the PREVIOUS note, whose result is still sitting there
## at perfect - so without this, tapping an empty receptor splashed the last note again.
var _splashed_index: int = -1


func _ready() -> void:
	if effects == null or handler == null:
		return

	_splash = _make_sprite(SPLASH_SCALE, Vector2.ZERO)
	_cover = _make_sprite(COVER_SCALE, COVER_OFFSET * FUNKIN_TO_RUBICON)
	# buildNoteHoldCoverSprite: target.flipY = Preferences.downscroll. The flip alone mirrors
	# the drawing about its own centre and leaves it sitting on the receptor; the cover
	# belongs where the TAIL is, which under downscroll is above. So the position is
	# mirrored with it.
	# BEHIND the receptor. This node is a sibling drawn after it, so both effects landed on
	# top and the cover buried the arrow it belongs to instead of haloing it - a capture of
	# the mod has the arrow drawn over its glow. A relative z_index of -1 puts just the
	# cover under the receptor; the splash stays over it.
	_cover.z_index = -1
	_cover.flip_v = true
	_cover.offset.y = -_cover_height() * 0.5

	handler.just_pressed.connect(_on_pressed)
	handler.just_released.connect(_on_released)
	_splash.animation_finished.connect(func() -> void: _splash.visible = false)
	_cover.animation_finished.connect(_on_cover_finished)
	set_process(true)


## The cover has to end on the HOLD's state, not on a release signal, and that is not a
## refinement - it is the difference between working and leaving textures on the screen.
##
## A sustain that runs to its natural end never emits `just_released`: the handler completes
## it inside `_press` when the note falls past the window, and under autoplay there is no
## release at all - `_autoplay_process` marks the hold HIT_INCOMPLETE and breaks. Driven off
## the signal, every autoplayed hold and every held-to-the-end note left its cover looping
## on screen forever, which is exactly what a device run showed.
##
## While a hold is live the handler parks on it: `note_hit_index` does not advance and the
## result at that index stays HIT_INCOMPLETE. So that is the state to watch.
func _process(_delta: float) -> void:
	if _holding and not _is_note_held():
		_end_cover()


func _is_note_held() -> bool:
	var index: int = int(handler.note_hit_index)
	var results: Array = handler.results
	if index < 0 or index >= results.size() or results[index] == null:
		return false
	return results[index].scoring_hit == RubiconLevelNoteHitResult.Hit.HIT_INCOMPLETE


func _make_sprite(sprite_scale: float, offset: Vector2) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = effects
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.position = offset
	sprite.visible = false
	add_child(sprite)
	return sprite


## Half a cover frame, for mirroring its position when it is flipped.
func _cover_height() -> float:
	for name: StringName in effects.get_animation_names():
		if String(name).begins_with("cover_"):
			var texture: Texture2D = effects.get_frame_texture(name, 0)
			if texture != null:
				return texture.get_height() * COVER_SCALE
	return 0.0


func _direction() -> String:
	var lane: int = int(handler.lane_id)
	return LANES[lane] if lane >= 0 and lane < LANES.size() else ""


func _on_pressed() -> void:
	var direction: String = _direction()
	if direction.is_empty():
		return

	var index: int = int(handler.last_hit_note_index)
	var results: Array = handler.results
	if index < 0 or index >= results.size() or results[index] == null:
		return
	# This press hit nothing new; the index is left over from the last one.
	if index == _splashed_index:
		return
	_splashed_index = index

	if _splashes(results[index]):
		var variant: int = randi_range(1, SPLASH_VARIANTS)
		var name := StringName("splash_%s_%d" % [direction, variant])
		if effects.has_animation(name):
			_splash.visible = true
			_splash.rotation_degrees = randf_range(
				-ROTATION_VARIANCE, ROTATION_VARIANCE) * 0.5
			_splash.play(name)

	# The cover runs for as long as the note is held, so it starts from the note that was
	# hit having an ending row - which is what a hold IS in a RubiChart.
	var notes: Array = handler.data
	if index >= notes.size() or notes[index] == null or notes[index].ending_row == null:
		return

	var cover := StringName("cover_%s" % direction)
	if not effects.has_animation(cover):
		return
	_holding = true
	_cover.visible = true
	_cover.play(cover)


## The player splashes on a perfect and nothing else - letting every press splash turns the
## effect into wallpaper. The opponent splashes six times in ten regardless.
func _splashes(result) -> bool:
	if _is_opponent():
		return randf() < OPPONENT_SPLASH_CHANCE
	return result.scoring_rating == RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT


## Read off the tree rather than off the controller's `autoplay`, which a harness turns on
## for both sides.
func _is_opponent() -> bool:
	var parent: Node = handler.get_parent()
	return parent != null and String(parent.name) == "Opponent"


func _on_released() -> void:
	_end_cover()


func _end_cover() -> void:
	if not _holding:
		return
	_holding = false

	var name := StringName("cover_%s_end" % _direction())
	if not effects.has_animation(name):
		_cover.visible = false
		return
	_cover.play(name)


func _on_cover_finished() -> void:
	# The body loops, so only the end animation ever finishes - and when it does the sprite
	# goes away unconditionally. Guarding this on `_holding` was how a cover that was ended
	# and then immediately re-held could leave its last frame up.
	_cover.visible = false
