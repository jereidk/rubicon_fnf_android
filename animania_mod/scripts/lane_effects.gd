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
## holdNoteCover.offsets, taking amtake-base.hx's downscroll branch.
##
## getHoldCoverOffsets() returns [x, -y] and buildNoteHoldCoverSprite sets flipY, both when
## Preferences.downscroll is on - and Rubicon's notes fall toward receptors at the BOTTOM of
## the screen, which is downscroll. So the authored [0, -60] becomes [0, 60] and the sprite
## is flipped.
##
## Rendered the other way round too, with the cover above the receptor where the tail is,
## on the theory that Funkin anchors this somewhere other than the receptor's centre. It
## looked worse: the cover lands on top of the receptor and swallows it. What the offset is
## anchored to in Funkin is not recoverable from this slice, so this follows the source
## rather than a guess about it.
const COVER_OFFSET := Vector2(0.0, 60.0)
## amtake-base.json declares two splash variants per lane and Funkin picks between them.
const SPLASH_VARIANTS := 2

const LANES := ["left", "down", "up", "right"]

@export var effects: SpriteFrames
## The lane this belongs to - a RubiconLevelManiaNoteHandler.
@export var handler: Node

var _splash: AnimatedSprite2D
var _cover: AnimatedSprite2D
var _holding: bool = false


func _ready() -> void:
	if effects == null or handler == null:
		return

	_splash = _make_sprite(SPLASH_SCALE, Vector2.ZERO)
	_cover = _make_sprite(COVER_SCALE, COVER_OFFSET * FUNKIN_TO_RUBICON)
	# buildNoteHoldCoverSprite: target.flipY = Preferences.downscroll.
	_cover.flip_v = true

	handler.just_pressed.connect(_on_pressed)
	handler.just_released.connect(_on_released)
	_splash.animation_finished.connect(func() -> void: _splash.visible = false)
	_cover.animation_finished.connect(_on_cover_finished)


func _make_sprite(sprite_scale: float, offset: Vector2) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = effects
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	sprite.position = offset
	sprite.visible = false
	add_child(sprite)
	return sprite


func _direction() -> String:
	var lane: int = int(handler.lane_id)
	return LANES[lane] if lane >= 0 and lane < LANES.size() else ""


func _on_pressed() -> void:
	var direction: String = _direction()
	if direction.is_empty():
		return

	# Only a perfect hit splashes. Funkin splashes on `sick` and nothing else, and letting
	# every press splash turns the effect into wallpaper.
	var index: int = int(handler.last_hit_note_index)
	var results: Array = handler.results
	if index < 0 or index >= results.size() or results[index] == null:
		return
	if results[index].scoring_rating != RubiconLevelNoteHitResult.Judgment.JUDGMENT_PERFECT:
		return

	var variant: int = randi_range(1, SPLASH_VARIANTS)
	var name := StringName("splash_%s_%d" % [direction, variant])
	if effects.has_animation(name):
		_splash.visible = true
		_splash.rotation_degrees = randf_range(-ROTATION_VARIANCE, ROTATION_VARIANCE) * 0.5
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


func _on_released() -> void:
	if not _holding:
		return
	_holding = false

	var name := StringName("cover_%s_end" % _direction())
	if not effects.has_animation(name):
		_cover.visible = false
		return
	_cover.play(name)


func _on_cover_finished() -> void:
	# The body loops, so only the end animation ever finishes.
	if not _holding:
		_cover.visible = false
