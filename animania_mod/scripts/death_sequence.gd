extends Node
## Tadano's death sequence.
##
## Rubicon has no game-over machinery at all: RubiconHealthModule emits `health_depleted`
## and nothing in the engine listens. So all of this is new, and all of it is
## tadano-stand.hx's createDeathSprites() and tadano.hx's setupDeath() transcribed - the two
## forms the song can die in, which differ in how elaborate they are rather than in shape.
##
## Distances are Funkin's and scale by 1.5, being screen distances. Times and eases are
## verbatim.
##
## What this does NOT do is retry. There is no pause menu, no game-over scene and no song
## select on this branch to go back to, so `confirm()` plays the confirm beat and stops -
## whatever drives the flow later calls it and then does the transition itself.

## createDeathSprites: darkBg tweens to 0.75 over 1.25s backOut after half a second.
const DARK_ALPHA := 0.75
const DARK_SECONDS := 1.25
const DARK_DELAY := 0.5

## The two black panels, only in the standing form. 400 wide, sliding in over six seconds.
const PANEL_WIDTH := 400.0
const PANEL_FROM := -400.0
const PANEL_TO := -100.0
const PANEL_SECONDS := 6.0
## deathConfirm slides them further, over 3.5s.
const PANEL_CONFIRM := -300.0
const CONFIRM_SECONDS := 3.5

## The HUD leaves the same way beat 332 sends it, with the strumlines a beat and a half
## behind instead of a quarter second.
const HUD_DISTANCE := 250.0
const HUD_SECONDS := 1.75
const HUD_DELAY_STRUMLINES := 0.15

## The retry text appears a quarter second in, and the death music fades up over twelve.
const RETRY_DELAY := 0.25
const MUSIC_FADE_SECONDS := 12.0

## Conductor.forceBPM(112) - the death music's tempo, and what paces the zoom creep and the
## retry text's replay.
const DEATH_BPM := 112.0
## onBeatHit, every other beat: FlxG.camera.zoom += 0.0075.
const ZOOM_CREEP := 0.0075

## The `death` block in each character's JSON: where the camera goes when they die, and how
## far in. GameOverSubState re-aims the camera at the dying character - it does not inherit
## wherever the song left it - which is what puts the retry text, placed 850 to the left, in
## frame at all.
const DEATH_CAMERA := {
	"phone": {"offsets": Vector2(-350.0, 50.0), "zoom": 1.05},
	"standing": {"offsets": Vector2(190.0, -40.0), "zoom": 1.1},
}

## deathLoop: the camera slides 450 left over 3.5s, which is what brings the retry text -
## placed 850 left of the character - into frame at all.
const LOOP_CAMERA_SLIDE := -450.0
const LOOP_SECONDS := 3.5
## deathConfirm: the camera pulls up 350 over 3.5s.
const CONFIRM_CAMERA_RISE := -350.0

const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SCREEN := Vector2(1920.0, 1080.0)

@export var health_module: Node
@export var song: Node
@export var clock: Node
@export var camera: Camera2D
@export var events: Node

@export var dark: ColorRect
@export var left_panel: ColorRect
@export var right_panel: ColorRect
@export var retry_text: AnimateSymbol
@export var retry_player: AnimationPlayer

@export var music: AudioStreamPlayer
@export var loss_sound: AudioStreamPlayer
@export var confirm_music: AudioStreamPlayer

## The phone pair and the standing pair, so the sequence can use whichever is on screen.
@export var phone_player: Node2D
@export var phone_opponent: Node2D
@export var stand_player: Node2D
@export var stand_opponent: Node2D

## The retry text has one atlas per form.
@export var phone_text: AnimationLibrary
@export var stand_text: AnimationLibrary

var _dying: bool = false
var _confirmed: bool = false
var _beat_timer: float = 0.0
var _retry_world: Vector2 = Vector2.ZERO


## The retry text sits on a CanvasLayer so the dark wash cannot cover it, so it has to be
## put back where the camera would have drawn it.
func _follow_camera() -> void:
	if retry_text == null or camera == null:
		return
	retry_text.position = (_retry_world - camera.global_position) * camera.zoom \
		+ SCREEN * 0.5


func _ready() -> void:
	if health_module != null and health_module.has_signal(&"health_depleted"):
		health_module.health_depleted.connect(die)
	if retry_player != null:
		retry_player.animation_finished.connect(_on_retry_finished)


func is_standing() -> bool:
	return events != null and events.get(&"_stood_up")


func die() -> void:
	if _dying:
		return
	_dying = true

	# The song stops. Funkin pushes a substate over PlayState; here there is one scene, so
	# the level simply stops being a level.
	#
	# The CLOCK stops too, and that one is not optional: its baked animation writes
	# position_interpolate_target every frame, so a death camera aimed at the dying
	# character is overwritten by the song's next FocusCamera key before it is ever drawn.
	# Pausing also stops the note controllers, which read their time from it.
	if clock != null and clock.animation_player != null:
		clock.animation_player.pause()
	if song != null and song.has_method(&"stop_playing"):
		song.stop_playing()
	if loss_sound != null:
		loss_sound.play()

	var standing: bool = is_standing()
	var player: Node2D = stand_player if standing else phone_player
	var opponent: Node2D = stand_opponent if standing else phone_opponent

	_play_death(player, &"first_death")
	# createDeathSprites: komi stops dancing and plays gameOver. Only the standing komi has
	# the animation - the phone one was never drawn dying.
	if standing:
		_play_death(opponent, &"game_over")

	_aim_camera(player, standing)

	# deathLoop's camera slide, which is what brings the retry text into frame.
	if camera != null:
		create_tween().tween_property(camera, "position_interpolate_target:x",
			camera.position_interpolate_target.x + LOOP_CAMERA_SLIDE * FUNKIN_TO_RUBICON,
			LOOP_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_fade_dark()
	if standing:
		_slide_panels()
	_send_hud_away()
	_show_retry(standing, player)


func _play_death(character: Node2D, animation: StringName) -> void:
	if character == null or not character.animation_player.has_animation(animation):
		return
	# STATE_OVERRIDE, and nothing releases it: the character is dead.
	character.state = character.CharacterState.STATE_OVERRIDE
	character.dancing_should_dance = false
	character.play(animation, true)

	# firstDeath hands over to deathLoop, which is where the character waits. Funkin does it
	# through GameOverSubState calling playAnimation twice; here the first animation ending
	# is the cue.
	var loop := StringName("death_loop" if animation == &"first_death"
		else "%s_loop" % animation)
	if not character.animation_player.has_animation(loop):
		return
	character.animation_player.animation_finished.connect(
		func(finished: StringName) -> void:
			if finished == animation:
				character.play(loop, true),
		CONNECT_ONE_SHOT)


func _fade_dark() -> void:
	if dark == null:
		return
	dark.color = Color(0.0, 0.0, 0.0, 0.0)
	var tween: Tween = create_tween()
	tween.tween_property(dark, "color:a", DARK_ALPHA, DARK_SECONDS) \
		.set_delay(DARK_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _slide_panels() -> void:
	for entry: Array in [[left_panel, PANEL_FROM, PANEL_TO],
			[right_panel, SCREEN.x, SCREEN.x - PANEL_WIDTH * FUNKIN_TO_RUBICON + 150.0]]:
		var panel: ColorRect = entry[0]
		if panel == null:
			continue
		panel.visible = true
		panel.position.x = float(entry[1]) * FUNKIN_TO_RUBICON if entry[1] < 0.0 \
			else float(entry[1])
		create_tween().tween_property(panel, "position:x", float(entry[2]),
			PANEL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Downscroll here, so the bar and its icons go up and the strumlines go down.
func _send_hud_away() -> void:
	if events == null:
		return
	var distance: float = HUD_DISTANCE * FUNKIN_TO_RUBICON
	_tween_away(events.get(&"hud_up"), -distance, 0.0)
	_tween_away(events.get(&"hud_down"), distance, HUD_DELAY_STRUMLINES)


func _tween_away(nodes: Variant, distance: float, delay: float) -> void:
	if nodes == null:
		return
	for node: Node in nodes:
		if node == null or not (node is CanvasItem):
			continue
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(node, "position:y", node.position.y + distance, HUD_SECONDS) \
			.set_delay(delay).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
		tween.tween_property(node, "modulate:a", 0.0, HUD_SECONDS).set_delay(delay)


func _show_retry(standing: bool, player: Node2D) -> void:
	if retry_text == null or retry_player == null:
		return

	var library: AnimationLibrary = stand_text if standing else phone_text
	if library == null:
		return
	if retry_player.has_animation_library(&""):
		retry_player.remove_animation_library(&"")
	retry_player.add_animation_library(&"", library)

	# createDeathSprites places it beside the character; setupDeath, in the phone form, puts
	# it further out and lower. Funkin adds it to the substate, which draws ABOVE darkBg, so
	# here it lives on the death CanvasLayer rather than in the world - otherwise the dark
	# wash covers the one thing the player is meant to read. It still has to move with the
	# camera the way an FlxSprite at scrollFactor 1 does, which _process does.
	# Funkin measures from the character's CORNER; these scenes are anchored bottom-centre,
	# so the corner has to be taken back off before the offset means the same thing.
	if player != null:
		var frame: Vector2 = _drawn_size(player)
		var corner: Vector2 = player.position - Vector2(frame.x * 0.5, frame.y)
		_retry_world = corner + (Vector2(240.0, 0.0) if standing
			else Vector2(-850.0, 450.0)) * FUNKIN_TO_RUBICON
	_follow_camera()

	retry_text.modulate.a = 0.0
	var timer: SceneTreeTimer = get_tree().create_timer(RETRY_DELAY)
	timer.timeout.connect(func() -> void:
		retry_text.modulate.a = 1.0
		retry_player.play(&"start")
		if music != null:
			music.volume_db = -60.0
			music.play()
			create_tween().tween_property(music, "volume_db", 0.0, MUSIC_FADE_SECONDS))


func _on_retry_finished(animation: StringName) -> void:
	# onFinish.addOnce: start hands over to loop, and loop is where it waits.
	if animation == &"start":
		retry_player.play(&"loop")


## The zoom creep and the retry text's replay, both on every other beat of the death music.
func _process(delta: float) -> void:
	if not _dying:
		return

	_follow_camera()
	if _confirmed:
		return

	_beat_timer += delta
	var two_beats: float = 2.0 * 60.0 / DEATH_BPM
	if _beat_timer < two_beats:
		return
	_beat_timer -= two_beats

	if camera != null:
		camera.zoom += Vector2(ZOOM_CREEP, ZOOM_CREEP)
		camera.zoom_interpolate_target = camera.zoom


## deathConfirm. Whatever drives the retry calls this and then does its own transition -
## there is no game-over scene on this branch to transition to.
func confirm() -> void:
	if not _dying or _confirmed:
		return
	_confirmed = true

	if retry_player != null:
		retry_player.play(&"confirm")
	if music != null:
		music.stop()
	if confirm_music != null:
		confirm_music.play()

	if camera != null:
		create_tween().tween_property(camera, "position_interpolate_target:y",
			camera.position_interpolate_target.y + CONFIRM_CAMERA_RISE * FUNKIN_TO_RUBICON,
			CONFIRM_SECONDS).set_delay(0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(
			Tween.EASE_IN_OUT)

	for entry: Array in [[left_panel, PANEL_CONFIRM * FUNKIN_TO_RUBICON],
			[right_panel, SCREEN.x - 100.0 * FUNKIN_TO_RUBICON]]:
		if entry[0] == null:
			continue
		create_tween().tween_property(entry[0], "position:x", float(entry[1]),
			CONFIRM_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)


## GameOverSubState aims at the dying character plus its own death cameraOffsets, and zooms
## by its death cameraZoom. Snapped, not tweened: the substate opens already there.
func _aim_camera(player: Node2D, standing: bool) -> void:
	if camera == null or player == null:
		return

	var entry: Dictionary = DEATH_CAMERA["standing" if standing else "phone"]
	var frame: Vector2 = _drawn_size(player)
	var target: Vector2 = player.position - Vector2(0.0, frame.y * 0.5) \
		+ (entry["offsets"] as Vector2) * FUNKIN_TO_RUBICON

	camera.position_interpolate_target = target
	camera.global_position = target
	var zoom: Vector2 = camera.zoom_interpolate_target * float(entry["zoom"])
	camera.zoom_interpolate_target = zoom
	camera.zoom = zoom


## The drawn size of a character, taken from whichever kind of sprite it uses.
func _drawn_size(character: Node2D) -> Vector2:
	for child: Node in character.get_children():
		if child is AnimatedSprite2D:
			var sprite := child as AnimatedSprite2D
			var texture: Texture2D = sprite.sprite_frames.get_frame_texture(
				sprite.animation, 0)
			if texture != null:
				return texture.get_size() * sprite.scale.abs()
		if child is AnimateSymbol:
			# tadano's phone form is an Adobe atlas with no authored size; this is what
			# tools/animania/harness/measure_character.gd measured it at.
			return Vector2(489.0, 833.0)
	return Vector2.ZERO
