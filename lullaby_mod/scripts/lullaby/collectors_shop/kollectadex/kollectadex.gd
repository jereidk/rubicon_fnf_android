@tool
class_name Kollectadex
extends Control


const SIDE_ORIGINAL_X: float = 848
const SIDE_TWEEN_SPD: float = 0.25

@export var sequences: ShopSequences
@export var focus_left_area: FocusArea3D
@export var kollectadex_anims: AnimationPlayer

@export var inputs_container: Control

@export var character_sprite: TextureRect

@export var character_name: Label
@export var character_subtitle: Label

@export var collection_label: Label

@export_group("Sounds")

@export var music: AudioStreamPlayer
@export var switch_sound: AudioStreamPlayer
@export var select_sound: AudioStreamPlayer
@export var select_failed_sound: AudioStreamPlayer
@export var close_sound: AudioStreamPlayer

@export_group("Side Panel")

@export var side_panel: TextureRect

@export var side_name: Label
@export var side_info: Label
@export var side_collectors_info: Label

var seen_on: String = "???"

var cur_index: int = 0:
	set(v):
		if cur_index != v:
			cur_index = v

var can_move: bool = true

var collected: int = 0
var collected_max: int = 0

var music_tween: Tween

var focused: bool = false;

func _ready() -> void :
	if Engine.is_editor_hint():
		return

	collected_max = 0

	for child in inputs_container.get_children():
		if child.unlocked:
			collected += 1

		collected_max += 1

		if not child.change_focus.is_connected(change_dex):
			child.change_focus.connect(change_dex)

	setup_from_save()
	# UPDATE_ONCE, not DISABLED. A viewport that has never rendered has no
	# texture to show, and this one's is on a prop standing in the room - so
	# switching it straight off would leave the Kollectadex's screen blank
	# until the first time the player opened it. One frame gives the prop the
	# still image it shows for the rest of the visit, and the mode disables
	# itself afterwards.
	var viewport: Viewport = get_viewport()
	if viewport is SubViewport:
		(viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	if kollectadex_anims != null \
			and not kollectadex_anims.animation_finished.is_connected(_on_close_animation_finished):
		kollectadex_anims.animation_finished.connect(_on_close_animation_finished)

## Whether the book's SubViewport is allowed to render.
##
## KollectadexSubViewport is 620x464 - 0.288 megapixels, the same count as the
## whole game at its 800x360 render scale - and the device log has it rendering
## in 62 of 78 shop samples, 79% of the visit, for a book that is open almost
## none of that time. The shop's six live SubViewports come to 1.38 megapixels
## against the main viewport's 0.288, and its GPU totals 16.24ms at the median
## against a 16.7ms budget, so this is not a rounding error.
##
## It cannot be gated on anything's visibility: the texture is shown by
## Environment/shop_base/KollectadexOffset/prp_kollectadex/Screen, a mesh that
## is part of the room and always on camera. And it cannot be refreshed only
## when its contents change, which was the first plan, because the background
## is a Parallax2D with autoscroll = (16, 16) - it moves on its own for as long
## as it renders, so an on-demand refresh would freeze it.
##
## So it renders while the book is open and not otherwise. Walking around the
## room leaves a still image on a screen across the room, and what stops moving
## in it is a grid at 29% alpha drifting sixteen pixels a second.
##
## Set from _ready() as well as the two transitions, because the scene authors
## the viewport at UPDATE_ALWAYS and the book starts closed.
func _set_render_live(live: bool) -> void:
	var viewport: Viewport = get_viewport()
	if viewport is SubViewport:
		(viewport as SubViewport).render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
		)

## close() drops focused immediately and then plays `return`, so switching the
## render off on the flag alone would freeze the book mid-close - the one
## moment the player is looking straight at it. It waits for the animation.
##
## Guarded on focused because the same player also drives the opening
## animation, and that one finishing must not switch anything off.
func _on_close_animation_finished(_anim_name: StringName) -> void:
	if not focused:
		_set_render_live(false)

func open():
	focused = true
	_set_render_live(true)

	can_move = true
	setup_from_save()

func close():
	if music_tween and music_tween.is_running():
		music_tween.custom_step(9999)
		music_tween.kill()

	music_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	music_tween.tween_property(music, ^"volume_linear", 0.0, 1.0)
	music_tween.finished.connect( func stop(): music.stop(), CONNECT_ONE_SHOT)

	focus_left_area.can_interact = true
	focus_left_area.register_trigger()

	if sequences:
		sequences.animation_player.play(&"focus_left")

	if kollectadex_anims:
		kollectadex_anims.play(&"kollectadex_animations/return")

	if close_sound:
		close_sound.play()

	focused = false

	# Belt and braces: without an animation player there is no
	# animation_finished to wait for, and the render would stay on for good.
	if kollectadex_anims == null:
		_set_render_live(false)

func _input(event: InputEvent) -> void :
	if Engine.is_editor_hint():
		return
	if event.is_echo() or not event.is_pressed():
		return

	if not focused:
		return

	if event.is_action(&"ui_cancel"):
		if not can_move:
			inspect()
		else:
			close()

	if event.is_action(&"ui_accept"):
		if not inputs_container.get_child(cur_index).unlocked:
			select_failed_sound.play()
		elif can_move:
			inspect()

	for c: Node in inputs_container.get_children():
		c.focus_mode = Control.FOCUS_ALL if can_move else Control.FOCUS_NONE


func inspect():
	if can_move:
		select_sound.play()

	can_move = not can_move
	var t: = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(
		side_panel, 
		^"position:x", 
		SIDE_ORIGINAL_X if can_move
		else 0.0, 
		SIDE_TWEEN_SPD
	);
	if can_move:
		await get_tree().create_timer(SIDE_TWEEN_SPD).timeout
		inputs_container.get_child(cur_index).focus_mode = Control.FOCUS_ALL
		inputs_container.get_child(cur_index).grab_focus();

func setup_from_save() -> void :
	cur_index = 0
	inputs_container.get_child(cur_index).grab_focus()



func change_dex(entry: KollectadexEntry, sound: bool = true) -> void :
	if sound and cur_index != entry.index - 1:
		switch_sound.play()

	cur_index = entry.index - 1

	character_sprite.texture = load(entry.character_image.resource_path)
	character_sprite.custom_minimum_size = character_sprite.texture.get_size() * 5
	character_name.text = entry.character_name
	character_subtitle.text = entry.character_subtitle

	side_name.text = entry.character_name;
	side_info.text = entry.character_desc;

	update_collection_info(entry)

	if Engine.is_editor_hint():
		character_sprite.modulate = Color.WHITE
		return

	if entry.unlocked:
		character_sprite.modulate = Color.WHITE
		seen_on = entry.seen_on
	else:
		character_sprite.modulate = Color.BLACK
		seen_on = "???"



func update_collection_info(entry: KollectadexEntry) -> void :
	collection_label.text = "Seen On: %s\nCollected: %03d / %03d" % [
		seen_on, 
		collected, 
		collected_max, 
	]
