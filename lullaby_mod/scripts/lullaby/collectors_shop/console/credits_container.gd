extends HBoxContainer

@export var console: Console
@export var primary_portrait_animation: AnimationPlayer
@export var secondary_portrait_animation: AnimationPlayer
@export var switch_animation: AnimationPlayer
@export var name_label: Label
@export var next_name_label: Label
@export var prev_name_label: Label
@export var role_label: Control
@export var description_label: RichTextLabel
@export var spotlight_animation: AnimationPlayer

@export var left_arrow_anim: AnimationPlayer
@export var right_arrow_anim: AnimationPlayer
@export var left_arrow_mesh: MeshInstance3D
@export var right_arrow_mesh: MeshInstance3D
@export var material_idle: StandardMaterial3D
@export var material_select: StandardMaterial3D

@export var credits_entries: Array[LullabyCreditsEntry]

## The portrait sheet, as a path, loaded the first time the credits are looked
## at.
##
## dev_portraits.png is 4096x4096 - 16.8 megapixels, 14% of every pixel the
## Collector's Shop pulls in, and about 4MB of VRAM once it is ASTC. The two
## AnimatedSprite2Ds below used to carry it as an ExtResource, so walking into
## the room loaded the whole sheet for a screen that is two menus deep and
## that most visits never open.
##
## Unlike the voicelines, this is one file out of four hundred, so it is not
## expected to move the load time much - the shop's load is bound by per-file
## cost. It is here for the memory.
@export_file("*.tres") var portrait_frames_path: String = "res://lullaby_mod/assets/menus/console/credits/devest_portraits.tres"

var _portraits_loaded: bool = false

var current_portrait_index: int = 0

var enter_cooldown: float = 0.0

signal changed_credits_entry

func _ready() -> void :
	# Rubicon addition: let taps/drags over the description text bubble up
	# to this container's own _gui_input instead of RichTextLabel's default
	# click handling swallowing them.
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Both AnimationPlayers drive the `animation` property of a sprite that has
	# no frames yet. That is harmless - the name is stored and applies as soon
	# as the sheet arrives, and _ensure_portraits() replays them anyway - and
	# it keeps this order identical to what it was before the sheet went lazy.
	primary_portrait_animation.play(credits_entries[0].name)
	secondary_portrait_animation.play(credits_entries[1].name)

	# Covers the case where the credits are the tab already on screen.
	visibility_changed.connect(_ensure_portraits)
	_ensure_portraits()
	var list_end: LullabyCreditsEntry = LullabyCreditsEntry.new()
	list_end.empty()
	credits_entries.append(list_end)
	update_labels()
	changed_credits_entry.emit()


func _process(delta: float) -> void :
	enter_cooldown -= delta


func _input(event: InputEvent) -> void :
	if not get_parent().visible:
		return

	if event.is_action_pressed("ui_accept") and enter_cooldown <= 0.0:
		_open_current_socials_link()

	if event.is_action_pressed("ui_left"):
		_go_next()
	elif event.is_action_pressed("ui_right"):
		_go_previous()
	if event.is_action_released("ui_right"):
		right_arrow_mesh.mesh.surface_set_material(0, material_idle)
	if event.is_action_released("ui_left"):
		left_arrow_mesh.mesh.surface_set_material(0, material_idle)


	if event.is_action("ui_up"):
		description_label.get_v_scroll_bar().value -= 30
	elif event.is_action("ui_down"):
		description_label.get_v_scroll_bar().value += 30

func _open_current_socials_link() -> void :
	console.play_sound.emit("sfx_soulroom_select_alt")
	OS.shell_open(credits_entries[current_portrait_index].socials_link)
	enter_cooldown = 1.0

func _go_next() -> void :
	# Belt and braces: any navigation forces the sheet in, even if the
	# visibility signal never fired for it.
	_ensure_portraits()

	current_portrait_index = wrap(current_portrait_index + 1, 0, credits_entries.size() - 1)
	update_labels()

	if left_arrow_anim.is_playing():
		left_arrow_anim.stop()
	left_arrow_anim.play("ArrowPress_24f")
	left_arrow_mesh.mesh.surface_set_material(0, material_select)

	if switch_animation.is_playing():
		switch_animation.stop()
		next_index()

	changed_credits_entry.emit()
	switch_animation.play("next")
	console.play_sound.emit("sfx_soulroom_click")

func _go_previous() -> void :
	# Belt and braces: any navigation forces the sheet in, even if the
	# visibility signal never fired for it.
	_ensure_portraits()

	current_portrait_index = wrap(current_portrait_index - 1, 0, credits_entries.size() - 1)
	update_labels()

	if right_arrow_anim.is_playing():
		right_arrow_anim.stop()
	right_arrow_anim.play("ArrowPress_24f")
	right_arrow_mesh.mesh.surface_set_material(0, material_select)

	if switch_animation.is_playing():
		switch_animation.stop()
	switch_animation.play("previous")

	changed_credits_entry.emit()
	console.play_sound.emit("sfx_soulroom_click")
	previous_index()

## Clicking the left/right edge of the carousel navigates, clicking the
## middle opens the current person's link (mirrors ui_accept).
const _TAP_EDGE_PERCENT: float = 0.3

func _gui_input(event: InputEvent) -> void :
	if not get_parent().visible:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_tap(event.position)

func _handle_tap(pos: Vector2) -> void :
	var rect: Rect2 = get_global_rect()
	var local_x_percent: float = (pos.x - rect.position.x) / rect.size.x

	if local_x_percent < _TAP_EDGE_PERCENT:
		_go_next()
	elif local_x_percent > 1.0 - _TAP_EDGE_PERCENT:
		_go_previous()
	elif enter_cooldown <= 0.0:
		_open_current_socials_link()

func _get_next_credit_entry() -> LullabyCreditsEntry:
	return credits_entries[wrap(current_portrait_index + 1, 0, credits_entries.size() - 1)]

func next_index():
	primary_portrait_animation.play(_get_next_credit_entry().name)
	secondary_portrait_animation.play(credits_entries[current_portrait_index].name)


func previous_index():
	primary_portrait_animation.play(credits_entries[current_portrait_index].name)
	secondary_portrait_animation.play(_get_next_credit_entry().name)


func _on_animation_player_animation_finished(_anim_name: StringName) -> void :
	primary_portrait_animation.play(credits_entries[current_portrait_index].name)
	secondary_portrait_animation.play(_get_next_credit_entry().name)


func turn_spotlight_on():
	if spotlight_animation.is_playing():
		spotlight_animation.seek(0)
	else:
		spotlight_animation.play("turn on")


func update_labels() -> void :
	name_label.text = credits_entries[current_portrait_index].name
	next_name_label.text = credits_entries[wrapi(current_portrait_index + 1, 0, credits_entries.size() - 1)].name
	prev_name_label.text = credits_entries[wrapi(current_portrait_index - 1, 0, credits_entries.size() - 1)].name
	description_label.text = credits_entries[current_portrait_index].description
	description_label.get_v_scroll_bar().value = 0
	role_label.text = credits_entries[current_portrait_index].role

## Loads the portrait sheet, once, the first time the credits are on screen.
##
## Driven from visibility_changed and from every navigation entry point rather
## than from visibility alone. The console renders through nested SubViewports
## and a tab container, and a portrait sheet that never arrived would show as
## two blank silhouettes with the names and roles still working - quiet enough
## to ship. Any interaction with the credits forces it.
func _ensure_portraits() -> void:
	if _portraits_loaded:
		return
	if not is_visible_in_tree():
		return
	if portrait_frames_path.is_empty():
		return

	var frames: SpriteFrames = load(portrait_frames_path) as SpriteFrames
	if frames == null:
		push_warning("credits: no pude cargar %s" % portrait_frames_path)
		return

	_portraits_loaded = true
	for player: AnimationPlayer in [primary_portrait_animation, secondary_portrait_animation]:
		if player == null:
			continue
		var sprite := player.get_parent() as AnimatedSprite2D
		if sprite == null:
			continue
		sprite.sprite_frames = frames
		# Assigning frames resets which animation is selected, so put the
		# player's own choice back rather than leaving the sheet's first one.
		var playing: StringName = player.current_animation
		if not playing.is_empty():
			player.play(playing)
