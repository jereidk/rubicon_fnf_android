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

## Lights this pass switched off, and whether they were visible before. Kept
## separately from _stashed because the two passes are independent: a light can
## be distance-faded, hidden, both or neither.
var _hidden: Dictionary = {}
var _applied_hide_baked: bool = false

## Every Light3D in the current scene, cached at the scene change so the
## zero-energy pass below is a float compare over a small array rather than a
## tree walk. Chimera has twelve, the shop fourteen; everything else has none
## and the pass switches itself off.
var _watched: Array[Light3D] = []

## instance_id -> the cull mask the scene authored, for the lights the pass is
## currently holding at zero. Absent means "not culled by us right now", which
## is what makes the restore exact instead of a guess at the default 0xFFFFF.
var _dark_masks: Dictionary = {}

func _ready() -> void:
	# After the AnimationPlayers. An autoload is at the top of the tree and
	# therefore processes before the scene by default, which would read
	# light_energy one frame stale - and a light coming back on one frame late
	# is a visible flicker on a TV that strobes every two frames.
	process_priority = 100000
	set_process(false)

	if SceneChanger.has_signal("scene_change_finished"):
		SceneChanger.scene_change_finished.connect(_on_scene_changed)
	if Settings.has_signal("applied"):
		Settings.applied.connect(_on_settings_applied)

	_apply_when_scene_ready()

func _on_scene_changed(_path: String) -> void:
	# The old scene's lights are gone; holding their values would leak and
	# could never match again anyway.
	_stashed.clear()
	_hidden.clear()
	_watched.clear()
	_dark_masks.clear()
	set_process(false)
	_applied_multiplier = DISABLED
	_applied_hide_baked = false
	_apply_when_scene_ready()

## Settings.applied fires on every single option row in the console, and
## walking the Collector's Shop tree on each keypress is exactly the cost this
## script exists to avoid. Only re-walk when the value actually moved.
func _on_settings_applied() -> void:
	if Settings.graphics_light_distance_fade == _applied_multiplier \
			and Settings.graphics_hide_baked_lights == _applied_hide_baked:
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

	_watched = _lights_of(scene)
	set_process(not _watched.is_empty())

	_apply_baked_light_cull(scene)

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

## Culls lights that are switched on and contributing nothing.
##
## Godot's mobile renderer pairs a light with an object when the light's range
## reaches the object's AABB. Energy is not part of that test, so a light at
## `light_energy = 0.0` is still handed to the shader and still evaluated on
## every fragment it covers - for a result that is multiplied by zero.
##
## Chimera's TvLight is that light for the first ~78 seconds of the song. It is
## authored at energy 0, `prelude` writes 0 again, and nothing raises it until
## the sequence where Hex first appears. Its range is 43.9 in a house about ten
## units across, so it reaches every fragment of every wide shot - which is the
## stretch the device measures at 57-59ms, the worst sustained part of the song.
## `HexStare` then writes `omni_range = 4096`, and from there to the end it
## reaches everything in the level including the sky.
##
## This is the one light pass that is not a quality trade, so it has no preset
## row and runs at every level including High: a light multiplied by zero looks
## identical whether it is evaluated or not. The other two passes change what
## you see and are gated accordingly.
##
## `light_cull_mask` rather than `visible`, and the difference matters. Six of
## Chimera's sequences animate `visible` on its lights, and a pass that writes
## the same property an animation writes ends up fighting it - that hazard is
## documented on the baked pass below, which avoids it by only touching lights
## no track targets. Nothing in this project animates a cull mask: it appears
## as a static node property in five places and in no track anywhere, checked
## across every .tscn, .tres and .gd. A mask of 0 pairs with no instance, so
## the light is dropped before shading rather than shaded to black.
##
## The authored mask is stashed per light instead of restored to a constant,
## because three of Chimera's lights and two of the shop's ship a custom one.
func _cull_dark_lights() -> void:
	for light: Light3D in _watched:
		if not is_instance_valid(light):
			continue
		var id: int = light.get_instance_id()
		if light.light_energy > 0.0:
			if _dark_masks.has(id):
				light.light_cull_mask = _dark_masks[id]
				_dark_masks.erase(id)
			continue
		if _dark_masks.has(id):
			continue
		_dark_masks[id] = light.light_cull_mask
		light.light_cull_mask = 0

func _process(_delta: float) -> void:
	_cull_dark_lights()

## How many lights the zero-energy pass is holding culled right now. Read by the
## diagnostics log: without it the device log cannot tell a pass that fired from
## one that never found a candidate, and both look like "no change".
func dark_culled_count() -> int:
	return _dark_masks.size()

## Hides lights whose contribution a LightmapGI already carries.
##
## Godot bakes a BAKE_STATIC light into the lightmap and **still renders it in
## real time** - the bake covers the meshes registered with the LightmapGI, the
## real-time pass covers everything else, and on a lightmapped scene the static
## geometry ends up paying for both. Chimera measures that directly: the closet
## shots have three lights reaching the camera and cost 33.5ms, the wide shots
## of the house have four and cost 57-59ms, and the fourth is MoonSpotlight,
## which is BAKE_STATIC. 24ms for one light the bake already contains.
##
## Three conditions, and every one of them is here because of a bug this
## project has already shipped:
##
## 1. **The scene must actually have a LightmapGI with light data loaded.**
##    Hiding the baked lights of a scene whose bake failed to load leaves an
##    unlit black room - which is exactly the eleven-day bug that cost this
##    project ten builds, when a lightmap .exr was deleted as an orphan and a
##    LightmapGI with no texture turned out to be a perfectly legal LightmapGI.
##    Checking light_data is what makes this pass fail safe instead of dark.
##
## 2. **Never a light under a RubiconCharacter.** chr_serena_base.tscn authors
##    its own SpotLight3D as BAKE_STATIC on the character root, and a light
##    that walks around with a character is not in the house bake no matter
##    what its bake mode says. Hiding it would take the light off Serena.
##
## 3. **Only lights that are visible right now**, and the previous value is
##    stashed, so raising the preset puts back what was authored rather than
##    switching on something the scene shipped hidden (Chimera's ClosetLight
##    ships visible = false and nothing anywhere turns it on).
##
## Safe to run on every scene because of condition 1: exactly two scenes in the
## project have a LightmapGI, Chimera and the collector's shop, and they are
## the two heaviest. Everything else falls out at the first check.
##
## What this does NOT protect against is an animation driving one of these
## lights, because a hidden light ignores whatever an animation writes to it.
## Checked before shipping: of Chimera's 27 sequences, **zero** tracks target
## any of its six BAKE_STATIC lights, and no script in the project writes to
## the shop's fourteen. Chimera's TvLight, which nine sequences do animate, is
## BAKE_DISABLED and therefore never a candidate here.
func _apply_baked_light_cull(scene: Node) -> void:
	# Record the setting, not the outcome. A scene with no lightmap leaves
	# _hidden empty, and keying the re-entry guard on that would re-walk the
	# Collector's Shop on every single console keypress - the cost this whole
	# script is written to avoid.
	_applied_hide_baked = Settings.graphics_hide_baked_lights

	if not _applied_hide_baked:
		_restore_hidden()
		return
	if not _hidden.is_empty():
		return
	if not _has_live_lightmap(scene):
		return

	for light: Light3D in _lights_of(scene):
		if light.light_bake_mode != Light3D.BAKE_STATIC:
			continue
		if not light.visible or _is_under_character(light):
			continue
		_hidden[light.get_instance_id()] = true
		light.visible = false

func _restore_hidden() -> void:
	for id: int in _hidden:
		var light: Object = instance_from_id(id)
		if is_instance_valid(light) and light is Light3D:
			(light as Light3D).visible = true
	_hidden.clear()

## A LightmapGI that is in the tree and actually holds a bake. `light_data` is
## the half that matters: the node loads and reports itself perfectly happily
## with none, and then lights nothing.
func _has_live_lightmap(root: Node) -> bool:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var lightmap := node as LightmapGI
		if lightmap != null and lightmap.light_data != null:
			return true
		for child in node.get_children():
			stack.append(child)
	return false

func _is_under_character(light: Light3D) -> bool:
	var node: Node = light
	while node != null:
		if node is RubiconCharacter:
			return true
		node = node.get_parent()
	return false

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
