@tool
extends ColorRect

## Hides a full-screen effect ColorRect while its effect is turned off.
##
## Monochrome's Front/RadialBlur is a 1920x1080 ColorRect carrying
## shd_radialblur, and it ships visible with no `visible` track of its own.
## The song animates only the shader's `intensity`, which sits at 0.0 for
## almost the whole song and rises for a few seconds.
##
## At 0.0 the shader still runs. Worse, it samples hint_screen_texture, so
## every frame of the song pays a full framebuffer copy - the single most
## expensive thing to ask a tile-based mobile GPU for, because it forces the
## tile to resolve out to memory - plus sixteen texture samples per pixel
## across the whole screen, to produce an image identical to the one it just
## copied.
##
## Reduce Visual Effects already strips this, so at Very Low it costs
## nothing; every preset above that pays it in full. A setting called
## "reduce visual effects" should not be the only thing standing between the
## player and a screen copy for a no-op.
##
## Polling rather than reacting: the parameter is driven by an animation
## track, and there is no signal for a shader parameter changing. Reading one
## float off a material each frame is not measurable next to what it saves.

## Shader parameter that decides whether the effect does anything.
@export var parameter: StringName = &"intensity"

## Value at or below which the effect is a no-op. Exposed rather than
## hardcoded to 0.0 because a different effect's neutral point may not be
## zero.
@export var neutral_value: float = 0.0

## Set false to leave the node alone - the escape hatch if a shader turns out
## to do something visible at its neutral value after all.
@export var gate_enabled: bool = true


func _process(_delta: float) -> void:
	if not gate_enabled:
		return

	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null:
		return

	var value: Variant = shader_material.get_shader_parameter(parameter)
	if value == null:
		return

	var wanted: bool = float(value) > neutral_value
	if wanted != visible:
		visible = wanted
