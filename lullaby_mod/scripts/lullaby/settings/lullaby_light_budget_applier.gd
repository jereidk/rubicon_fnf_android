extends Node

## Culls small real-time lights by camera distance on the low quality presets.
##
## Why this exists: Chimera is GPU-bound and the cost tracks how much of the
## screen is covered rather than any count - 101_prelude costs 38.9ms at 10312
## primitives while scene@133 costs 19.5ms at 16671, with the same four shadow
## casters and 10-11 visible lights in both. Godot's mobile renderer evaluates
## every omni/spot light that reaches a fragment, so a wide shot of the house
## pays for all of them on every pixel it fills. Cutting the number of lights
## reaching a pixel is the lever that matches that measurement.
##
## The distance is derived from each light's own range rather than tuned per
## scene, which is what makes this safe to apply everywhere without having
## looked at every shot:
##
##   distance_fade_begin  = range * multiplier
##   distance_fade_length = range
##   distance_fade_shadow = range * multiplier * 0.5
##
## A candle with omni_range 2 stops being evaluated once the camera is more
## than a few metres away, where its contribution was a handful of dim pixels
## anyway. Chimera's TvLight, with omni_range 43.9, would need the camera 130+
## units away before it faded, so scene-wide lights are left alone by
## construction. DirectionalLight3D has no range and is skipped entirely.
##
## Everything is stashed and restored, so raising the preset again puts the
## authored values back exactly rather than guessing defaults.
##
## The multipliers were picked against Chimera's actual lights, whose ranges
## split cleanly into local and scene-wide (the house is roughly 10 units
## across, so anything culling past ~30 would never fire):
##
##   light               range   gone at x3   gone at x2
##   SerenaBase           1.51          6.1          4.5
##   CrawlDoorLight       1.75          7.0          5.2
##   CameraMechanic       3.16         12.6          9.5
##   OutsideGrassLight    5.81         23.2         17.4
##   Camera3D's own       6.51         26.0         19.5   (rides the camera)
##   AmbLight            18.14         72.6         54.4
##   MoonSpotlight       21.46         85.8         64.4
##   TvLight             43.93        175.7        131.8
##
## So Low (x3) and Very Low (x2) drop the four small, dim local lights
## (energy 0.265-1.07) once the camera leaves them, and never touch the four
## that light the whole scene. The camera's own light rides the camera, so its
## distance is always ~0 and it never fades regardless.

## Multiplier of 0 disables the whole pass, which is what High and Medium ship.
const DISABLED: float = 0.0

var _stashed: Dictionary = {}
var _applied_multiplier: float = DISABLED

func _ready() -> void:
	if SceneChanger.has_signal("scene_change_finished"):
		SceneChanger.scene_change_finished.connect(_on_scene_changed)
	if Settings.has_signal("applied"):
		Settings.applied.connect(_on_settings_applied)

	_apply_when_scene_ready()

func _on_scene_changed(_path: String) -> void:
	# The old scene's lights are gone; holding their values would leak and
	# could never match again anyway.
	_stashed.clear()
	_applied_multiplier = DISABLED
	_apply_when_scene_ready()

## Settings.applied fires on every single option row in the console, and
## walking the Collector's Shop tree on each keypress is exactly the cost this
## script exists to avoid. Only re-walk when the value actually moved.
func _on_settings_applied() -> void:
	if Settings.graphics_light_distance_fade == _applied_multiplier:
		return
	_apply_to_current_scene()

## get_tree().current_scene is not assigned on the frame change_scene_to_packed
## runs, and call_deferred fires at the end of that same frame - see the note
## in lullaby_note_layout_applier.gd, which this repeats deliberately.
func _apply_when_scene_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_to_current_scene()

func _apply_to_current_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	var multiplier: float = maxf(0.0, Settings.graphics_light_distance_fade)
	_applied_multiplier = multiplier

	if is_zero_approx(multiplier):
		_restore()
		return

	for light: Light3D in _lights_of(scene):
		var light_range: float = _range_of(light)
		if light_range <= 0.0:
			continue

		var id: int = light.get_instance_id()
		if not _stashed.has(id):
			_stashed[id] = {
				"enabled": light.distance_fade_enabled,
				"begin": light.distance_fade_begin,
				"length": light.distance_fade_length,
				"shadow": light.distance_fade_shadow,
			}

		light.distance_fade_enabled = true
		light.distance_fade_begin = light_range * multiplier
		light.distance_fade_length = light_range
		light.distance_fade_shadow = light_range * multiplier * 0.5

func _restore() -> void:
	for id: int in _stashed:
		var light: Object = instance_from_id(id)
		if not is_instance_valid(light) or not (light is Light3D):
			continue
		var saved: Dictionary = _stashed[id]
		light.distance_fade_enabled = saved["enabled"]
		light.distance_fade_begin = saved["begin"]
		light.distance_fade_length = saved["length"]
		light.distance_fade_shadow = saved["shadow"]
	_stashed.clear()

## Only lights with a finite reach can be distance-faded. A DirectionalLight3D
## covers the whole world and has no range to derive a distance from.
func _range_of(light: Light3D) -> float:
	if light is OmniLight3D:
		return light.omni_range
	if light is SpotLight3D:
		return light.spot_range
	return 0.0

func _lights_of(root: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Light3D:
			out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out
