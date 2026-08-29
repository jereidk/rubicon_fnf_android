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

## Lo ultimo que se pidio reproducir, para poder aplicarlo cuando lleguen los
## frames. Conducir las pistas antes de eso es lo que llenaba el .error.
var _wanted_primary: StringName = &""
var _wanted_secondary: StringName = &""

var current_portrait_index: int = 0

var enter_cooldown: float = 0.0

signal changed_credits_entry

func _ready() -> void :
	# Rubicon addition: let taps/drags over the description text bubble up
	# to this container's own _gui_input instead of RichTextLabel's default
	# click handling swallowing them.
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Se recuerdan, no se tocan. El comentario que habia aqui decia que
	# conducir `animation` sobre un sprite sin frames era inofensivo porque el
	# nombre se guarda y se aplica cuando llega la hoja. El .error del
	# dispositivo del 2026-08-24 dice que no:
	#
	#     There is no animation with name 'serena'.        (x11)
	#     There is no animation with name 'Anniebuue'.
	#     There is no animation with name 'BeefStarchJello'.
	#     animated_sprite_2d.cpp:585 set_animation
	#
	# Cada llave de esas pistas escribe `:animation` sobre el sprite vacio y
	# suelta un error rojo. Formatear un error y recorrer su traza no sale
	# gratis, y son veintitantos por visita a la tienda.
	_want_portraits(credits_entries[0].name, credits_entries[1].name)

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
		_paint(right_arrow_mesh, material_idle)
	if event.is_action_released("ui_left"):
		_paint(left_arrow_mesh, material_idle)


	if event.is_action("ui_up"):
		description_label.get_v_scroll_bar().value -= 30
	elif event.is_action("ui_down"):
		description_label.get_v_scroll_bar().value += 30

## Igual que en home_button.gd, y por el mismo motivo.
##
## surface_set_material() escribe en el recurso Mesh, compartido, asi que un
## null no deja la flecha como estaba: la deja SIN material, y en un
## SubViewport con own_world_3d y sin una sola luz el material por defecto de
## Godot sale negro. Este nodo tenia su material_select escrito ANTES de
## `script =` en la escena, y una propiedad de script puesta antes de que el
## script exista no se aplica ni se queja: quedaba null, y pulsar una flecha la
## borraba.
func _paint(mesh_node: Node, material: StandardMaterial3D) -> void:
	if material == null:
		push_warning("credits: material sin asignar, la flecha se deja como esta")
		return
	if mesh_node is MeshInstance3D and mesh_node.mesh != null:
		mesh_node.mesh.surface_set_material(0, material)


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
	_paint(left_arrow_mesh, material_select)

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
	_paint(right_arrow_mesh, material_select)

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
	_want_portraits(_get_next_credit_entry().name,
		credits_entries[current_portrait_index].name)


func previous_index():
	_want_portraits(credits_entries[current_portrait_index].name,
		_get_next_credit_entry().name)


func _on_animation_player_animation_finished(_anim_name: StringName) -> void :
	_want_portraits(credits_entries[current_portrait_index].name,
		_get_next_credit_entry().name)


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

	# Ahora que hay hoja, se reproduce lo que se pidio mientras no la habia.
	_apply_portraits()


## Pide un par de retratos, y los reproduce solo si ya hay hoja.
##
## Las animaciones de estos dos AnimationPlayer llevan pistas que escriben
## `CreditsPortrait*:animation`, o sea que reproducirlas sin `sprite_frames`
## suelta un error rojo por llave. Se guarda lo pedido y `_ensure_portraits()`
## lo aplica en cuanto la hoja llega; el orden que ve el jugador no cambia
## porque la hoja se carga en la primera visita a la pestana.
func _want_portraits(primary: StringName, secondary: StringName) -> void:
	_wanted_primary = primary
	_wanted_secondary = secondary
	if _portraits_loaded:
		_apply_portraits()


func _apply_portraits() -> void:
	if primary_portrait_animation != null and not _wanted_primary.is_empty():
		primary_portrait_animation.play(_wanted_primary)
	if secondary_portrait_animation != null and not _wanted_secondary.is_empty():
		secondary_portrait_animation.play(_wanted_secondary)
