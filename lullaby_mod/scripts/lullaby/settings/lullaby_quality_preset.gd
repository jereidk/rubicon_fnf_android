class_name LullabyQualityPreset extends Resource

@export var name: String = "Default"

@export var scaling_3d_mode: Viewport.Scaling3DMode = Viewport.Scaling3DMode.SCALING_3D_MODE_BILINEAR
@export var render_scale: float = 1.0
@export var shadows_enabled: bool = true
@export var positional_shadow_atlas_size: int = 4096
@export var positional_shadow_filter_quality: int = 2
@export var msaa_3d_quality: Viewport.MSAA = Viewport.MSAA.MSAA_DISABLED
@export var screen_space_aa_quality: Viewport.ScreenSpaceAA = Viewport.ScreenSpaceAA.SCREEN_SPACE_AA_SMAA
@export var post_processing: LullabySettings.PostProcessing = LullabySettings.PostProcessing.HIGH
@export var ssao: bool = true
@export var ssil: bool = true

## Texture sampling quality, as Viewport.AnisotropicFiltering
## (0 = 1x/off, 1 = 2x, 2 = 4x, 3 = 8x, 4 = 16x).
##
## The project was leaving this at the engine default of 4x everywhere. It is a
## per-sample bandwidth cost on every textured pixel, and this device is bound
## on exactly that - Chimera's GPU time tracks how much of the screen is
## covered, not how many objects or primitives there are. At Low's 0.65 render
## scale on a 720p phone the difference between 4x and off is not visible;
## the bandwidth is.
@export_enum("Off (1x)", "2x", "4x", "8x", "16x")
var anisotropic_filtering: int = 2

## Viewport.mesh_lod_threshold, in pixels: how small a mesh's detail has to get
## before the engine swaps in a cheaper LOD.
##
## Also left at the engine default of 1.0, which effectively means LODs never
## kick in. Raising it makes distant geometry drop detail sooner, which cuts
## both vertex work and the fragments those triangles cover. Godot generates
## the LODs at import time, so this costs nothing to turn on.
@export_range(0.0, 16.0, 0.5) var mesh_lod_threshold: float = 1.0

## Multiplier on each light's own range, past which the light stops being
## rendered - see lullaby_light_budget_applier.gd. 0 disables the pass.
##
## The mobile renderer evaluates every omni/spot light that reaches a fragment,
## and Chimera's cost tracks screen coverage at a constant light count, so
## fewer lights per pixel is the lever that matches the measurement. Deriving
## the distance from the light's own range means small local lights (candles, a
## phone glow) drop out when the camera leaves them while scene-wide lights
## never do, without tuning a number per scene.
@export_range(0.0, 12.0, 0.5) var light_distance_fade: float = 0.0

## Engine.physics_ticks_per_second.
##
## Nothing in this project's gameplay runs on the physics tick: a sweep for
## _physics_process/_integrate_forces across the whole repo finds exactly
## three users, and none of them is timing-critical - Safety Lullaby's
## lamp_flicker.gd accumulates delta (so it is tick-rate independent), and
## the shop's mouse_controller.gd only re-aims the hover raycast. Rubicon
## drives notes off the audio clock in _process. So halving the rate halves
## a cost that buys nothing here: the Collector's Shop logs phys=3-6ms of a
## 24ms frame on 19 Area3Ds and 31 collision pairs, with p3d_objs=0 - there
## is not a single active rigid body in it.
##
## It also breaks a feedback loop. Godot runs up to max_physics_steps_per_frame
## catch-up ticks after a slow frame, so a 141ms shop spike was asking for
## eight physics steps inside the frame that was already late.
@export var physics_ticks_per_second: int = 60

## Frame rate cap. Not a graphics setting in the usual sense - it does
## nothing for image quality - but on a device that cannot hold 60 it is
## worth more than any of the above. Chimera on a moto g53 oscillates
## between 60fps and sub-20 with spikes past 140ms, and that swing is what
## reads as stuttering; a phone locked to a rate it can actually sustain
## feels smooth at half the numbers. 0 means uncapped.
@export var target_fps: int = 0

## Only Very Low sets this - strips every decorative/post-processing shader
## effect in the project (see LullabySettings.EFFECT_SHADER_PATHS) while
## leaving shaders that are a node's actual base material untouched (e.g.
## the shop console's toon shading, the cartridge dissolve-in animation).
@export var disable_shader_effects: bool = false

## How many atlas frames pass between gdanimate symbol updates. 1 is stock.
##
## The only lever on gdanimate's cost that does not require rewriting the
## addon, and it is measured rather than reasoned: with Gold's real atlas in an
## isolated project the rebuild-per-frame-advance ratio is 0.99, so halving the
## advances halves the rebuilds. Playback speed is untouched - after six
## seconds the symbols sit on frame 140 / 139 / 143 at step 1 / 2 / 3, all
## against an expected ~144 - because the advance is still `floori(t * fps)`
## atlas frames, only the gate that lets it run is coarser.
##
## Why it is worth a preset row: Monochrome is CPU-bound on both devices
## measured (13-15ms of GPU at 42-49fps) and gdanimate is its biggest single
## item - anim2d p50 56.80 ms/s on a Mali-G57, 112.80 ms/s on a Mali-G52, with
## rebuild at 87% of it. Chimera reads anim2d=0.00, which is why every earlier
## measurement in this project missed it: they were all taken on the one song
## with no Adobe atlas on stage.
##
## What it costs is how the animation reads: at 2 the atlas plays at 12fps
## instead of 24 - same duration, half the distinct drawings.
##
## **Very Low only.** How much that is noticed depends on whether the source
## was animated on twos, and counting the layer-frame durations in Monochrome's
## atlases says it mostly was - Gold, the character on screen all song, is
## 83.8% of layer frames at DU >= 2, and his turnaround 85.2%. But DU is per
## layer and Gold's busiest symbol has 47 of them, so a composite can still
## change every frame even when each layer holds two; the honest claim is that
## the source is far friendlier to this than something drawn on ones, not that
## it is invisible.
##
## So it goes only on the preset that already exists to make the game run at
## all - no shadows, no post-processing, render at 50%, LOD at 8. Low still
## means to look right and keeps 1.
@export_range(1, 4, 1) var atlas_frame_step: int = 1

func is_matching(settings: LullabySettings) -> bool:
	return (settings.graphics_scaling_mode == scaling_3d_mode and
		settings.graphics_render_scale == render_scale and
		settings.graphics_shadows_enabled == shadows_enabled and
		settings.graphics_positional_shadow_atlas_size == positional_shadow_atlas_size and
		settings.graphics_positional_shadow_filter_quality == positional_shadow_filter_quality and
		settings.graphics_msaa_3d_quality == msaa_3d_quality and
		settings.graphics_screen_space_aa_quality == screen_space_aa_quality and
		settings.graphics_post_processing == post_processing and
		settings.graphics_ssao == ssao and
		settings.graphics_ssil == ssil and
		settings.graphics_anisotropic_filtering == anisotropic_filtering and
		settings.graphics_mesh_lod_threshold == mesh_lod_threshold and
		settings.graphics_light_distance_fade == light_distance_fade and
		settings.graphics_physics_ticks_per_second == physics_ticks_per_second and
		settings.display_target_fps == target_fps and
		settings.graphics_disable_shader_effects == disable_shader_effects and
		settings.graphics_atlas_frame_step == atlas_frame_step
	)

func apply(settings: LullabySettings) -> void :
	settings.graphics_scaling_mode = scaling_3d_mode
	settings.graphics_render_scale = render_scale
	settings.graphics_shadows_enabled = shadows_enabled
	settings.graphics_positional_shadow_atlas_size = positional_shadow_atlas_size
	settings.graphics_positional_shadow_filter_quality = positional_shadow_filter_quality
	settings.graphics_msaa_3d_quality = msaa_3d_quality
	settings.graphics_screen_space_aa_quality = screen_space_aa_quality
	settings.graphics_post_processing = post_processing
	settings.graphics_ssao = ssao
	settings.graphics_ssil = ssil
	settings.graphics_anisotropic_filtering = anisotropic_filtering
	settings.graphics_mesh_lod_threshold = mesh_lod_threshold
	settings.graphics_light_distance_fade = light_distance_fade
	settings.graphics_physics_ticks_per_second = physics_ticks_per_second
	settings.display_target_fps = target_fps
	settings.graphics_disable_shader_effects = disable_shader_effects
	settings.graphics_atlas_frame_step = atlas_frame_step
