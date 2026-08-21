@tool
extends Light3D

## Hides a light while its energy is at (or below) zero.
##
## Forward Mobile evaluates every light that reaches a fragment, so a light
## that emits nothing still occupies a slot in that per-fragment loop. Measured
## in isolation on the phone's path (Vulkan, Forward Mobile, one full-screen
## surface, 8 omnis):
##
##     light_energy = 0.35, visible=true    135.8ms
##     light_energy = 0.0,  visible=true    135.1ms   <- same price
##     light_energy = 0.0,  visible=false    16.3ms
##
## A light contributing nothing still costs full price; only `visible = false`
## removes it from the loop.
##
## `light_indirect_energy` and `light_volumetric_fog_energy` do not change that
## verdict on this project: there is no live GI system in use anywhere here
## (renderer/rendering_method.mobile is "mobile" - Forward Mobile - which has
## no SDFGI/VoxelGI path, and no scene uses VoxelGI) and no scene enables
## volumetric fog, so with light_energy at zero this light's radiance is zero
## and there is nothing else that could still be reading it. Confirmed by
## rendering a light at energy=0, indirect_energy=6.026 (the same combination
## authored on Chimera's TvLight) against the same light fully absent: 0/255
## worst pixel error.
##
## Deliberately opt-in per node rather than a scene-wide auto-discovery pass.
## The one thing that would make this unsafe is an animation track writing
## this same light's own `:visible` - the class of bug already documented at
## length in this project (the precache blackout, the flashing-lights
## suppressor) - and resolving that from a runtime NodePath walk over every
## AnimationPlayer in a scene is exactly the kind of thing that has bitten this
## project before (`%Name` lookups, `.` vs name keying, opaque .gltf
## subtrees...). Checking it once by hand against `tools/audit_light_cost.py`
## and attaching this script only where it says the light is not
## animation/script-driven is worth more than an automated check that could be
## subtly wrong. `light_bake_mode == BAKE_STATIC` is skipped for the same
## reason a baked-static mesh is skipped when hiding effect meshes: a light
## meant to be baked once is not this script's business.
func _process(_delta: float) -> void:
	if light_bake_mode == Light3D.BAKE_STATIC:
		return
	var wanted: bool = not is_zero_approx(light_energy)
	if wanted != visible:
		visible = wanted
