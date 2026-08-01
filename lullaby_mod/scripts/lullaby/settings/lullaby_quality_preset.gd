class_name LullabyQualityPreset extends Resource

@export var name: String = "Default"

@export var scaling_3d_mode: Viewport.Scaling3DMode = Viewport.Scaling3DMode.SCALING_3D_MODE_BILINEAR
@export var render_scale: float = 1.0
@export var positional_shadow_atlas_size: int = 4096
@export var positional_shadow_filter_quality: int = 2
@export var msaa_3d_quality: Viewport.MSAA = Viewport.MSAA.MSAA_DISABLED
@export var screen_space_aa_quality: Viewport.ScreenSpaceAA = Viewport.ScreenSpaceAA.SCREEN_SPACE_AA_SMAA
@export var post_processing: LullabySettings.PostProcessing = LullabySettings.PostProcessing.HIGH
@export var ssao: bool = true
@export var ssil: bool = true

## Only Very Low sets this - strips every decorative/post-processing shader
## effect in the project (see LullabySettings.EFFECT_SHADER_PATHS) while
## leaving shaders that are a node's actual base material untouched (e.g.
## the shop console's toon shading, the cartridge dissolve-in animation).
@export var disable_shader_effects: bool = false

func is_matching(settings: LullabySettings) -> bool:
	return (settings.graphics_scaling_mode == scaling_3d_mode and
		settings.graphics_render_scale == render_scale and
		settings.graphics_positional_shadow_atlas_size == positional_shadow_atlas_size and
		settings.graphics_positional_shadow_filter_quality == positional_shadow_filter_quality and
		settings.graphics_msaa_3d_quality == msaa_3d_quality and
		settings.graphics_screen_space_aa_quality == screen_space_aa_quality and
		settings.graphics_post_processing == post_processing and
		settings.graphics_ssao == ssao and
		settings.graphics_ssil == ssil and
		settings.graphics_disable_shader_effects == disable_shader_effects
	)

func apply(settings: LullabySettings) -> void :
	settings.graphics_scaling_mode = scaling_3d_mode
	settings.graphics_render_scale = render_scale
	settings.graphics_positional_shadow_atlas_size = positional_shadow_atlas_size
	settings.graphics_positional_shadow_filter_quality = positional_shadow_filter_quality
	settings.graphics_msaa_3d_quality = msaa_3d_quality
	settings.graphics_screen_space_aa_quality = screen_space_aa_quality
	settings.graphics_post_processing = post_processing
	settings.graphics_ssao = ssao
	settings.graphics_ssil = ssil
	settings.graphics_disable_shader_effects = disable_shader_effects
