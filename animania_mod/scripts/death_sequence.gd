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
## Retrying is the one place this cannot follow the mod. Funkin's GameOverSubState.update
## ends the confirm by building a StickerSubState and going back into PlayState through it,
## and there is no sticker transition here - so this reloads the level instead. The standing
## form's own curtain is black by then and covers the swap; the phone form's confirm has no
## curtain, so there the reload is visible. That is a gap, not a choice.

## createDeathSprites: darkBg tweens to 0.75 over 1.25s backOut after half a second.
const DARK_ALPHA := 0.75
const DARK_SECONDS := 1.25
const DARK_DELAY := 0.5
## setupDeath darkens the other way round: it opens at 0.9, dips to 0.5 over a second and
## comes back to 0.75 from a second in - the two tweens overlap and the later one wins.
const PHONE_DARK_FROM := 0.9
const PHONE_DARK_DIP := 0.5
const PHONE_DIP_SECONDS := 1.0
const PHONE_DARK_DELAY := 1.0

## The two black panels, only in the standing form. 400 wide, sliding in over six seconds.
const PANEL_WIDTH := 400.0
const PANEL_FROM := -400.0
const PANEL_TO := -100.0
const PANEL_SECONDS := 6.0
## deathConfirm slides them further, over 3.5s.
const PANEL_CONFIRM := -300.0
const CONFIRM_SECONDS := 3.5

## The HUD leaves the same way beat 332 sends it, with the strumlines behind the bar. Both
## forms send the same things the same distance; setupDeath just waits longer to start.
const HUD_DISTANCE := 250.0
const HUD_SECONDS := 1.75
const HUD_DELAY_BAR := 0.0
const HUD_DELAY_STRUMLINES := 0.15
const PHONE_HUD_DELAY_BAR := 0.25
const PHONE_HUD_DELAY_STRUMLINES := 0.5

## createDeathSprites shows the retry text on a quarter-second timer and starts the death
## music itself, faded up from nothing over twelve seconds. setupDeath does neither: its
## text waits for deathLoop, and its music is GameOverSubState's, which opens at full
## volume the moment the substate does.
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

## deathLoop, in the PHONE form only: the camera slides 450 left over 3.5s, which is what
## brings the retry text - placed 850 left of the character - into frame at all. The
## standing form has no deathLoop branch and no slide: tadano-stand.hx returns on that
## animation without touching the camera, and its text sits beside the character anyway.
##
## And it does not start at death. GameOverSubState only plays deathLoop when firstDeath
## ends, which is four seconds of dying later.
const LOOP_CAMERA_SLIDE := -450.0
const LOOP_SECONDS := 3.5
## deathConfirm: the camera pulls up 350 over 3.5s.
const CONFIRM_CAMERA_RISE := -350.0

## How long the confirm runs before the level comes back: its own tweens, which are 3.5s
## from where each form starts them - the standing one immediately, the phone one after its
## 0.8 delay.
const RETRY_DELAY_STANDING := 0.2
const RETRY_DELAY_PHONE := 0.8

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

## The black curtain the standing form's confirm wipes down. Screen space, like its
## scrollFactor.set().
@export var gradient: Control
## The lane hitboxes. They are not part of the HUD the death sends away, and while they are
## up they eat the tap that is meant to retry - and a dead player cannot hit notes anyway.
@export var mobile_controls: CanvasLayer
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

	# onBeatHit opens with `if (isPlayerDying) return`, which is what stops the strumline
	# pulse the moment the player is dead.
	# `dying` lives on the level's AnimaniaModule now. It goes through the
	# events node so this script needs no handle on the module. The old
	# events.set(&"dying", true) silently did nothing once the property moved:
	# Object.set() on a property that does not exist is not an error.
	if events != null:
		events.set_dying(true)

	if mobile_controls != null:
		mobile_controls.visible = false

	var standing: bool = is_standing()
	var player: Node2D = stand_player if standing else phone_player
	var opponent: Node2D = stand_opponent if standing else phone_opponent

	# The phone form has a deathLoop and hangs its camera slide and its retry text off it;
	# the standing form has neither the animation nor the branch, so nothing waits.
	_play_death(player, &"first_death", Callable() if standing else _on_death_loop)
	# createDeathSprites: komi stops dancing and plays gameOver. Only the standing komi has
	# the animation - the phone one was never drawn dying.
	if standing:
		_play_death(opponent, &"game_over")

	_aim_camera(player, standing)
	_fade_dark(standing)
	if standing:
		_slide_panels()
	_send_hud_away(standing)
	_prepare_retry(standing, player)

	if standing:
		# createDeathSprites: the text and the music both wait out a quarter second.
		get_tree().create_timer(RETRY_DELAY).timeout.connect(func() -> void:
			_begin_retry()
			_start_music(true))
	else:
		# GameOverSubState starts the death music as it opens, at full volume.
		_start_music(false)


func _play_death(character: Node2D, animation: StringName,
		on_loop: Callable = Callable()) -> void:
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
			if finished != animation:
				return
			character.play(loop, true)
			if on_loop.is_valid():
				on_loop.call(),
		CONNECT_ONE_SHOT)


## deathLoop, in the phone form. Both of these wait out firstDeath's four seconds, because
## that is when Funkin plays the animation they hang off.
func _on_death_loop() -> void:
	if camera != null:
		create_tween().tween_property(camera, "position_interpolate_target:x",
			camera.position_interpolate_target.x + LOOP_CAMERA_SLIDE * FUNKIN_TO_RUBICON,
			LOOP_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_begin_retry()


func _fade_dark(standing: bool) -> void:
	if dark == null:
		return

	if standing:
		dark.color = Color(0.0, 0.0, 0.0, 0.0)
		create_tween().tween_property(dark, "color:a", DARK_ALPHA, DARK_SECONDS) \
			.set_delay(DARK_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return

	# setupDeath opens dark and lightens before it settles. The second tween reads its start
	# value when its delay runs out, so it picks the dip up wherever the first one left it.
	dark.color = Color(0.0, 0.0, 0.0, PHONE_DARK_FROM)
	create_tween().tween_property(dark, "color:a", PHONE_DARK_DIP, PHONE_DIP_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	create_tween().tween_property(dark, "color:a", DARK_ALPHA, DARK_SECONDS) \
		.set_delay(PHONE_DARK_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
func _send_hud_away(standing: bool) -> void:
	if events == null:
		return
	var distance: float = HUD_DISTANCE * FUNKIN_TO_RUBICON
	_tween_away(events.get(&"hud_up"), -distance,
		HUD_DELAY_BAR if standing else PHONE_HUD_DELAY_BAR)
	_tween_away(events.get(&"hud_down"), distance,
		HUD_DELAY_STRUMLINES if standing else PHONE_HUD_DELAY_STRUMLINES)


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


func _prepare_retry(standing: bool, player: Node2D) -> void:
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

	# alpha 0.0001 in both scripts, so it is added and laid out but not read yet.
	retry_text.modulate.a = 0.0


## The text is shown and started - on a timer in the standing form, on deathLoop in the
## phone one.
func _begin_retry() -> void:
	if retry_text == null or retry_player == null:
		return
	retry_text.modulate.a = 1.0
	retry_player.play(&"start")


## startDeathMusic(0, false) then fadeIn(12, 0, 1) in the standing form; the phone form
## takes GameOverSubState's own, which is already at volume.
func _start_music(fade: bool) -> void:
	if music == null:
		return
	music.volume_db = -60.0 if fade else 0.0
	music.play()
	if fade:
		create_tween().tween_property(music, "volume_db", 0.0, MUSIC_FADE_SECONDS)


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
##
## The two forms differ here, and this used to run the standing form's numbers for both.
## tadano-stand.hx raises the camera 350 over 3.5s on a 0.2 delay with elasticInOut, slides
## the panels and drops the gradient; tadano.hx cancels the slide it started on deathLoop
## and raises the same 350 over the same 3.5s but on a 0.8 delay with backInOut, and has
## neither panels nor gradient.
func confirm() -> void:
	if not _dying or _confirmed:
		return
	_confirmed = true
	var standing: bool = is_standing()

	if retry_player != null:
		retry_player.play(&"confirm")
	if music != null:
		music.stop()
	if confirm_music != null:
		confirm_music.play()

	if camera != null:
		var rise: Tween = create_tween()
		rise.tween_property(camera, "position_interpolate_target:y",
			camera.position_interpolate_target.y + CONFIRM_CAMERA_RISE * FUNKIN_TO_RUBICON,
			CONFIRM_SECONDS).set_delay(0.2 if standing else 0.8).set_trans(
			Tween.TRANS_ELASTIC if standing else Tween.TRANS_BACK).set_ease(
			Tween.EASE_IN_OUT)

	_retry(standing)

	if not standing:
		return

	for entry: Array in [[left_panel, PANEL_CONFIRM * FUNKIN_TO_RUBICON],
			[right_panel, SCREEN.x - 100.0 * FUNKIN_TO_RUBICON]]:
		if entry[0] == null:
			continue
		create_tween().tween_property(entry[0], "position:x", float(entry[1]),
			CONFIRM_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

	_sweep_gradient()


## ACCEPT while the retry text is looping. On a phone that is a tap: the lane hitboxes are
## hidden by then, so nothing else is holding the screen.
func _unhandled_input(event: InputEvent) -> void:
	if not _dying or _confirmed or not event.is_pressed():
		return
	if event is InputEventKey:
		if (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			confirm()
		return
	if event is InputEventScreenTouch \
			or (event is InputEventMouseButton
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		confirm()


## Seconds from confirm() to the level coming back - each form's delay plus the 3.5s its
## tweens run.
func retry_seconds(standing: bool) -> float:
	return (RETRY_DELAY_STANDING if standing else RETRY_DELAY_PHONE) + CONFIRM_SECONDS


## Only when this level IS the running scene. A harness instances it as a child of its own
## scene, and reloading there would throw away the harness instead.
func _retry(standing: bool) -> void:
	await get_tree().create_timer(retry_seconds(standing)).timeout
	if get_tree().current_scene == owner:
		get_tree().reload_current_scene()


## The last thing tadano-stand.hx's deathConfirm does, and the last thing added to the
## substate, so it draws over everything including the retry text:
##
##     var g = FlxGradient.createGradientFlxSprite(FlxG.width, FlxG.height * 2.25,
##         [FlxColor.BLACK, FlxColor.BLACK, FlxColor.TRANSPERENT]);
##     g.screenCenter(FlxAxes.X); g.scrollFactor.set(); g.y = -(FlxG.height * 2);
##     FlxTween.tween(g, {y: 0}, 3.5, {ease: FlxEase.backIn});
##
## Three colours over a sprite two and a quarter screens tall, so black for the first half
## and fading out over the second - and it comes to rest at y = 0, where the screen only
## ever sees that solid first half. It is a curtain, drawn as a fade.
func _sweep_gradient() -> void:
	if gradient == null:
		return
	gradient.visible = true
	gradient.position = Vector2(gradient.position.x, -SCREEN.y * 2.0)
	create_tween().tween_property(gradient, "position:y", 0.0,
		CONFIRM_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


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
