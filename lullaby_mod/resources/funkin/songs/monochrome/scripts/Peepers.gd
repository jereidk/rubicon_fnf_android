@tool
extends Control

@export var clock: RubiconLevelClock

@export_group("Unowns")
@export var unown_parent: Control

@export_group("Progress")
@export_range(0.0, 1.0, 0.001) var progress: float = 1.0:
	set(value):
		if is_equal_approx(progress, value):
			return
		progress = value
		_shader_dirty = true

@export_range(0.0, 1.0, 0.001) var hold_progress: float = 0.0:
	set(value):
		if is_equal_approx(hold_progress, value):
			return
		hold_progress = value
		_shader_dirty = true

@export_range(0.0, 1.0, 0.001) var hold_percent: float = 0.0:
	set(value):
		if is_equal_approx(hold_percent, value):
			return
		hold_percent = value
		_shader_dirty = true

@export_group("Style")
@export_enum("Normal", "Silhouette") var eye_style: int = 0:
	set(value):
		if eye_style == value:
			return
		eye_style = value
		_shader_dirty = true

@export_group("Stagger")
@export var use_stagger: bool = true:
	set(value):
		if use_stagger == value:
			return
		use_stagger = value
		_shader_dirty = true

@export_range(0.0, 1.0, 0.001) var stagger_amount: float = 0.65:
	set(value):
		if is_equal_approx(stagger_amount, value):
			return
		stagger_amount = value
		_shader_dirty = true

@export var reverse_stagger: bool = false:
	set(value):
		if reverse_stagger == value:
			return
		reverse_stagger = value
		_shader_dirty = true

@export_group("Movement")
@export var movement_enabled: bool = true
@export_range(0.0, 50.0, 0.01) var movement_speed: float = 1.0

@export_group("Wobble")
@export_range(0.0, 15.0, 0.01) var wobble_intensity: float = 1.0

@export_group("Violent Parent Shake")
@export var violent_shake_enabled: bool = false
@export_range(0.0, 500.0, 1.0) var violent_shake_amount: float = 2.0
@export_range(0.0, 250.0, 0.1) var violent_shake_speed: float = 200.0

const EYE_STYLE_PARAMETER: StringName = "eye_style"

var _time: float = 0.0
var _base_position: Vector2 = Vector2.ZERO
var _has_base_position: bool = false
var _shader_dirty: bool = true
var _unowns: Array[ColorRect]

## Resolved once alongside _unowns, because everything below used to be
## re-derived per eye per frame: `"_time" in unown`, has_method(), call(),
## `"glow_node" in unown` and a cast of unown.material. That is a dictionary
## lookup or a dynamic dispatch 128 times a frame for answers that cannot
## change while the scene is loaded.
var _eye_times: Array[bool] = []
var _eye_wobbles: Array[bool] = []
var _eye_glows: Array[Node] = []
var _eye_materials: Array[ShaderMaterial] = []
## The distinct materials, after the 128 became 6. eye_style is one value for
## the whole field, so it needs writing once per material and not once per
## eye - which with shared materials would be 128 writes of the same value to
## the same six objects.
var _unique_materials: Array[ShaderMaterial] = []
var _settings_node: Node
var _settings_looked_up: bool = false


func _ready() -> void :
	_capture_base_position()
	_update_unown_shaders()
	_apply_child_processing()


## Each eye runs its own _process for the wobble, and each glow runs another
## for its scale and rotation - 256 callbacks a frame on top of this node's
## own loops. Godot does not skip _process for an invisible node, so they all
## kept running through every stretch of the song where Peepers is hidden,
## which on Monochrome is most of it.
##
## _process() here already returns early when hidden, so _time stops
## advancing and the children have nothing new to react to anyway.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_apply_child_processing()


func _apply_child_processing() -> void:
	if not is_inside_tree():
		return

	var on: bool = visible
	var unowns: Array[ColorRect] = _get_unowns()
	for index: int in range(unowns.size()):
		unowns[index].set_process(on)
		var glow: Node = _eye_glows[index]
		if glow != null:
			glow.set_process(on)


func _process(delta: float) -> void :
	if not visible:
		return

	if movement_enabled:
		if clock != null:
			_time = (clock.time_milliseconds / 1000.0) * movement_speed
		else:
			_time += delta * movement_speed

	if _shader_dirty or Engine.is_editor_hint():
		_update_unown_shaders()

	_update_unown_wobble()
	_update_parent_shake()


func _get_unown_container() -> Control:
	if unown_parent != null:
		return unown_parent

	return self


func _capture_base_position() -> void :
	var container: Control = _get_unown_container()

	_base_position = container.position
	_has_base_position = true


func _update_parent_shake() -> void :
	var container: Control = _get_unown_container()

	if not _has_base_position:
		_capture_base_position()

	if not violent_shake_enabled or not movement_enabled:
		container.position = _base_position
		return

	container.position = _base_position + Vector2(
		sin(_time * violent_shake_speed), 
		cos(_time * violent_shake_speed * 1.37)
	) * violent_shake_amount * _shake_scale()


func _update_unown_wobble() -> void :
	var final_wobble_intensity: float = wobble_intensity

	if not movement_enabled:
		final_wobble_intensity = 0.0

	var unowns: Array[ColorRect] = _get_unowns()
	for index: int in range(unowns.size()):
		var unown: ColorRect = unowns[index]
		if _eye_times[index]:
			unown.set(&"_time", _time)

		if _eye_wobbles[index]:
			unown.set(&"wobble_intensity", final_wobble_intensity)


func _update_unown_shaders() -> void :
	if not is_inside_tree() or not visible:
		return

	var unowns: Array[ColorRect] = _get_unowns()
	var unown_count: int = unowns.size()

	if unown_count == 0:
		_shader_dirty = false
		return

	# Once per material rather than once per eye: the six materials are
	# shared by all 128 now, and eye_style is a single value for the field.
	for material: ShaderMaterial in _unique_materials:
		material.set_shader_parameter(EYE_STYLE_PARAMETER, eye_style)

	for index: int in range(unown_count):
		_update_unown_shader(unowns[index], index, unown_count)

	_shader_dirty = false


func _update_unown_shader(unown: ColorRect, index: int, unown_count: int) -> void :
	if _eye_times[index]:
		unown.set(&"_time", _time)

	if _eye_materials[index] == null:
		return

	var stagger_index: int = index
	if reverse_stagger:
		stagger_index = unown_count - 1 - index

	var shader_progress: float = progress
	var shader_hold_progress: float = hold_progress

	if use_stagger and unown_count > 1:
		shader_progress = _get_staggered_progress(progress, stagger_index, unown_count)
		shader_hold_progress = _get_staggered_progress(hold_progress, stagger_index, unown_count)

	unown.modulate.a = maxf(shader_progress, shader_hold_progress)

	var glow: Node = _eye_glows[index]
	if glow == null:
		return

	glow.set(&"progress_value", shader_progress)
	glow.set(&"hold_progress_value", shader_hold_progress)
	glow.set(&"eye_style", eye_style)


func _get_staggered_progress(base_progress: float, index: int, unown_count: int) -> float:
	var normalized_index: float = index / maxf(unown_count - 1, 1.0)
	var start: float = normalized_index * stagger_amount
	var end: float = start + (1.0 - stagger_amount)

	if end <= start:
		return 1.0 if base_progress >= start else 0.0

	return smoothstep(start, end, base_progress)


func _get_unowns() -> Array[ColorRect]:
	if _unowns.is_empty():
		var container: Node = _get_unown_container()
		_get_parallax_unowns(container, _unowns)
		_cache_eye_lookups()

	return _unowns


## The per-eye answers that never change once the scene is built.
func _cache_eye_lookups() -> void:
	_eye_times.clear()
	_eye_wobbles.clear()
	_eye_glows.clear()
	_eye_materials.clear()
	_unique_materials.clear()

	for unown: ColorRect in _unowns:
		_eye_times.append("_time" in unown)
		_eye_wobbles.append(unown.has_method("set_wobble_intensity"))

		var glow: Node = null
		if "glow_node" in unown:
			glow = unown.glow_node
		_eye_glows.append(glow)

		var material: ShaderMaterial = unown.material as ShaderMaterial
		_eye_materials.append(material)
		if material != null and not _unique_materials.has(material):
			_unique_materials.append(material)


func _get_parallax_unowns(node: Node, unowns: Array[ColorRect]) -> void :
	for child: Node in node.get_children():
		if child is ColorRect:
			unowns.append(child)

		_get_parallax_unowns(child, unowns)


## Global shake multiplier from the console's Misc > Screen Shake row.
##
## Fetched by node name rather than through the Settings class: this is a
## @tool script, so it also runs in the editor where no autoload exists, and
## get_node_or_null keeps it at full strength there instead of erroring.
func _shake_scale() -> float:
	# Looked up once. This runs inside _update_parent_shake(), which runs
	# every frame, and a get_node_or_null() per frame for a node that cannot
	# appear or disappear mid-scene is a lookup for nothing.
	if not _settings_looked_up:
		_settings_looked_up = true
		_settings_node = get_node_or_null(^"/root/Settings")

	if _settings_node == null:
		return 1.0
	return clampf(float(_settings_node.get(&"lullaby_screen_shake")) / 100.0, 0.0, 1.0)
