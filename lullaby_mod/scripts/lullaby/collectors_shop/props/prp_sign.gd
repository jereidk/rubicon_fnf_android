extends Node3D

@export var enabled: bool = false:
	set(value):
		enabled = value
		if not enabled:
			current_option_index = -1
		_update_visual()
@export var lerp_movement: bool = true

@export_group("Internal References")
@export var inactive_emission: Texture2D
@export var shop_emission: Texture2D
@export var talk_emission: Texture2D

@export var sign_player: AnimationPlayer

@export_group("Shop References")
@export var shop: CollectorShop
@export var note_pad: Node3D
@export var briefcase: CollectorBriefcase
@export var focus_area_center: TriggerArea3D

@export_group("Sign Positions")
@export var sign_base_position: Vector3 = Vector3(0.735, -0.392, -0.481)
@export var sign_selected_position: Vector3 = Vector3(0.735, -0.392, -0.481)
@export var sign_offscreen_offset: Vector3 = Vector3(3.6, -0.2, -0.4)
@export var sign_offscreen_anim_time: float = 0.78

@export_group("Selector Model")
@export var selector_model: Node3D
@export var selector_lerp_speed: float = 10.0
@export var shop_position: Vector3 = Vector3(0.0, 0.15, 0.0)
@export var talk_position: Vector3 = Vector3(0.0, -0.15, 0.0)

@export var override_lerp_pos: Vector3 = - Vector3.ONE

@onready var camera_positions: AnimationPlayer = %CameraPositions

@onready var shop_collision_box: Area3D = $Armature_002 / Skeleton3D / BoneAttachment3D / ShopCollisionArea
@onready var talk_collision_box: Area3D = $Armature_002 / Skeleton3D / BoneAttachment3D / TalkCollisionArea

@onready var mesh: MeshInstance3D = $Armature_002 / Skeleton3D / Cylinder

@onready var confirm_snd: AudioStreamPlayer3D = $Confirm
@onready var hover_snd: AudioStreamPlayer3D = $Hover

var current_option_index: int = -1
var current_option_name: String = ""
var mesh_mat: StandardMaterial3D
var options: Array[String] = ["shop", "talk"]

var _selector_target_position: Vector3 = Vector3.ZERO

## La posicion suavizada, SIN el balanceo, del selector y del propio cartel.
##
## El balanceo se sumaba encima de `position` cada fotograma y el lerp del
## fotograma siguiente partia de ese resultado, asi que no era un balanceo: era
## una acumulacion amortiguada, y donde se estabiliza depende de a cuantos fps
## vaya el juego. Con el lerp rapido del selector (`selector_lerp_speed`) el
## coeficiente vale 0.74 a 60fps y 0.93 a 30, o sea que la misma amplitud se
## queda ~26% mas grande a 60. Con el cartel apagado, que usa `delta / 10.0`, el
## coeficiente es 0.013 a 60fps y 0.027 a 30: el balanceo sale multiplicado por
## 75 en un caso y por 37 en el otro, el doble de desplazamiento a 60fps que a
## 30. En un movil que no sostiene 60 el cartel flota en otro sitio.
##
## Separandolo, el lerp trabaja sobre una base limpia y el balanceo es un
## desplazamiento absoluto de la posicion, que es lo que siempre quiso ser.
var _selector_base: Vector3 = Vector3.INF
var _sign_base: Vector3 = Vector3.INF

## El balanceo del cartel de este fotograma, como desplazamiento absoluto sobre
## `_sign_base`. Se calcula donde se calculaba (dentro de `enabled`) y se aplica
## abajo, donde esta el lerp.
var _sign_sway: Vector3 = Vector3.ZERO

var _sick_tween: Tween = null
var _sick_tween_progress: float = 0
var _in_menu: bool = false

## True only while the player is actually picking between shop/talk (not
## once a submenu is open) - separate from `enabled`, which an outro
## animation keeps true for a beat after entering the submenu (see
## env_collector_shop.tscn's CardboardSign tracks). RubiconMenuTouchControls
## reads this (vertical_only_source/property) to mute the on-screen D-pad
## to up/down-only for exactly this chooser, not for whatever comes after.
var is_choosing_option: bool:
	get:
		return enabled and not _in_menu

func _ready() -> void :
	mesh_mat = mesh.get_active_material(0).duplicate()
	mesh.set_surface_override_material(0, mesh_mat)

	if selector_model != null:
		_selector_target_position = selector_model.position
		_selector_base = selector_model.position

	_sign_base = position

	_update_visual()

	_setup_option_triggers(shop_collision_box, 0)
	_setup_option_triggers(talk_collision_box, 1)

func _process(delta: float) -> void :
	focus_area_center.input_ray_pickable = !enabled;

	# Antes del return de abajo: sin selector el cartel esta mal montado, pero
	# dejarse el confirm cedido seria peor que no cederlo.
	shop.mouse_controller.confirm_owned_by_prop = is_choosing_option

	if selector_model == null:
		return

	var elapsed_time: float = Time.get_ticks_msec() / 1000.0;

	# On touch, the sign has no hover to fall back on (see
	# _setup_option_triggers - its mouse_entered/exited are ignored while
	# touch controls are active, since Android's emulated mouse motion
	# would otherwise fight the D-pad for current_option_index). So a
	# selection always exists here instead: default to "shop" and let
	# ui_up/ui_down (the on-screen D-pad, muted to vertical-only for this
	# prop via RubiconMenuTouchControls.vertical_only_source - see this
	# prop's `enabled` wiring on the CardboardSign node) move it.
	var touch_driven: bool = enabled and not _in_menu and shop.mouse_controller.is_touch_controls_active()

	if touch_driven and current_option_index == -1:
		current_option_index = 0
		_update_visual()

	if current_option_index == -1 and not _in_menu:
		_unselect_option()

	if enabled:
		focus_area_center.focused = not _in_menu
		shop.state = shop.ShopStates.BUSY if _in_menu else shop.ShopStates.FOCUSED

		if Input.is_action_just_released("ui_cancel") and _in_menu:
			exit_submenu()

		if touch_driven:
			if Input.is_action_just_pressed("ui_down"):
				_move_selection(1)
			elif Input.is_action_just_pressed("ui_up"):
				_move_selection(-1)

		# Suavizado sobre la base limpia, balanceo sumado despues como
		# desplazamiento absoluto. Ver `_selector_base`: sumandolo sobre
		# `position` se acumulaba, y donde acababa dependia de los fps.
		if _selector_base == Vector3.INF:
			_selector_base = selector_model.position

		_selector_base = _selector_base.lerp(
			_selector_target_position,
			1.0 - pow(0.0003, delta * selector_lerp_speed)
		)

		selector_model.position = _selector_base + Vector3(
			sin(elapsed_time) * 0.0002 + sin(elapsed_time / 2) * 0.0001,
			cos(elapsed_time) * 0.0001 + sin(elapsed_time / 2) * 0.0001,
			sin(elapsed_time) * 5e-05 + cos(elapsed_time / 2) * 0.0001
		)

		selector_model.rotation.x = sin(elapsed_time) * 0.03
		selector_model.rotation.z = cos(elapsed_time) * 0.025

		if lerp_movement:
			_sign_sway = Vector3(
				sin(elapsed_time * 0.8) * 0.0003 + sin(elapsed_time / 2) * 0.0001,
				cos(elapsed_time * 0.8) * 0.0003,
				0.0
			)
	else:
		_sign_sway = Vector3.ZERO

		if Input.is_action_just_released("ui_cancel") and _sick_tween != null:
			_sick_tween.custom_step(999)
			_sick_tween.kill()
			_sick_tween = null

	if lerp_movement:
		var in_override: bool = override_lerp_pos != - Vector3.ONE
		var lerp_pos: Vector3 = sign_selected_position if current_option_index >= 0 else sign_base_position

		if in_override:
			lerp_pos = override_lerp_pos

		if _sign_base == Vector3.INF:
			_sign_base = position

		_sign_base = _sign_base.lerp(
			lerp_pos,
			1.0 - pow(0.0003, delta * selector_lerp_speed if enabled else delta / 10.0)
		)
		position = _sign_base + _sign_sway

		var start_rot_lerp: bool = false;

		if sign_player.current_animation != null:
			start_rot_lerp = (sign_player.current_animation == &"" and enabled) or sign_player.current_animation == &"IntroFirst"

			if sign_player.current_animation == &"Intro" and sign_player.get_playing_speed() > 0 and sign_player.current_animation_position >= 0.9:
				start_rot_lerp = true;

		rotation.y = lerp(
			rotation.y, 
			deg_to_rad(-33.1) if start_rot_lerp else 0.0, 
			1.0 - pow(0.24, delta)
		)

func _input(event: InputEvent) -> void :
	if not enabled or _in_menu or current_option_index == -1:
		return

	# Reuses MouseController's confirm check (real left-click on desktop,
	# or the OK button's synthetic InputEventAction/a gamepad button on
	# touch) instead of the old plain "left_click" check, which was a raw
	# mouse-button action with no touch handling at all - it never fired
	# from the OK button, so this sign was unreachable by anything but a
	# real mouse.
	if shop.mouse_controller.is_confirm_event(event):
		_select_option()

func _move_selection(delta_index: int) -> void :
	var new_index: int = (current_option_index + delta_index + options.size()) % options.size()

	if new_index == current_option_index:
		return

	current_option_index = new_index
	_update_visual()
	hover_snd.play(0)

func _setup_option_triggers(area: Area3D, id: int):
	area.mouse_entered.connect( func entered():
		# Ignored on touch: Android's "emulate mouse from touch" turns
		# every tap into real mouse-motion/button events, which would
		# otherwise hijack current_option_index away from whatever the
		# D-pad selected (see the touch_driven block in _process()).
		if enabled and not shop.mouse_controller.is_touch_controls_active():
			shop.mouse_controller.override_cursor_shape = Input.CURSOR_POINTING_HAND;

			var last_option_name: String = String(current_option_name)

			if current_option_index != id:
				current_option_index = id

			_update_visual()

			if last_option_name != current_option_name:
				hover_snd.play(0)
	)

	area.mouse_exited.connect( func exited():
		if enabled and not shop.mouse_controller.is_touch_controls_active():
			current_option_index = -1
	)

func _unselect_option():
	@warning_ignore("int_as_enum_without_cast", "int_as_enum_without_match")
	shop.mouse_controller.override_cursor_shape = -1

	current_option_index = -1
	set_hover_option("")

var _allow_more_clicks: bool = true

func _select_option():
	if not _allow_more_clicks:
		return

	shop.stop_voiceline()

	# A la base y no a `position`: el balanceo reescribe `position` entera cada
	# fotograma, asi que sumarlo ahi se perdia en el siguiente.
	if _selector_base == Vector3.INF:
		_selector_base = selector_model.position
	_selector_base.x += 0.01
	confirm_snd.play(0)
	_pulse_glow()

	enter_submenu()

	match current_option_index:
		0:
			briefcase.open()
		1:
			note_pad.open()

func _pulse_glow() -> void :
	if mesh_mat == null:
		return

	var base_energy: float = mesh_mat.emission_energy_multiplier
	var glow_tween: Tween = create_tween()
	glow_tween.tween_property(mesh_mat, "emission_energy_multiplier", base_energy * 1.8, 0.08)
	glow_tween.tween_property(mesh_mat, "emission_energy_multiplier", base_energy, 0.35)

func _update_visual() -> void :
	if not enabled:
		set_hover_option("")
		return

	# El indice -1 significa "nada elegido", y en GDScript `options[-1]` NO es un
	# error: devuelve el ULTIMO elemento, o sea "talk".
	#
	# `sequence_sign_intro` escribe `current_option_index = -1` en t=0 y
	# `enabled = true` en t=2, y el setter de `enabled` llama aqui. Asi que al
	# entrar al selector se encendia "talk" y el selector se iba a
	# `talk_position` con el indice todavia en -1 - que es justo lo que
	# `_input()` mira para NO dejar confirmar. Una opcion encendida que no se
	# podia elegir.
	#
	# Con raton no se notaba: el primer hover lo corrige en el acto. En tactil no
	# hay hover, lo corrige el bloque `touch_driven` de `_process()` un fotograma
	# despues y poniendo 0, asi que lo que se ve es "talk" encendiendose y
	# saltando solo a "shop".
	if current_option_index < 0 or current_option_index >= options.size():
		set_hover_option("")
		return

	set_hover_option(options[current_option_index])

func set_hover_option(option: String) -> void :
	if mesh_mat == null:
		return

	if option != "":
		current_option_name = option

	match option:
		"shop":
			mesh_mat.emission_texture = shop_emission
			_selector_target_position = shop_position

		"talk":
			mesh_mat.emission_texture = talk_emission
			_selector_target_position = talk_position

		_:
			mesh_mat.emission_texture = inactive_emission

	mesh_mat.emission_enabled = true


func exit_submenu():
	if note_pad.visible:
		if not note_pad._allow_input:
			return
		else:
			note_pad.close()

	if briefcase.is_focused:
		if not briefcase.close():
			return

	enter_submenu(true)

func enter_submenu(is_exiting: bool = false):
	_in_menu = not is_exiting
	_allow_more_clicks = is_exiting
	note_pad.disable_collisions = is_exiting

	var final_position: Vector3 = sign_base_position + sign_offscreen_offset
	override_lerp_pos = sign_base_position

	if _sick_tween != null:
		_sick_tween.custom_step(999)
		_sick_tween.kill()
		_sick_tween = null

	_sick_tween = create_tween()
	_sick_tween.tween_method(
		func update(val: float):
			var eased_val: float = EasingFunctions.ease_in_out_circ(0.0, 1.0, val)
			override_lerp_pos = lerp(sign_base_position, final_position, eased_val)

			_sick_tween_progress = val, 
		1.0 if is_exiting else 0.0, 
		0.0 if is_exiting else 1.0, 
		sign_offscreen_anim_time
	)


## Devuelve el confirm al soltar la escena, o el boton OK quedaria forzado a
## visible para quien venga despues.
func _exit_tree() -> void :
	if shop != null and shop.mouse_controller != null:
		shop.mouse_controller.confirm_owned_by_prop = false
