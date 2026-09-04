shader_type canvas_item;
// funkin.graphics.shaders.AdjustColorShader, transcribed from the GLSL the mod carries as a
// literal in its own binary rather than reconstructed from Adobe's AdjustColor docs. The
// three matrices, the grayscale weights, the saturation triple-below-zero, the contrast
// curve and its "Just roll with it..." magic numbers are the mod's, character for character.
//
// createSeasonalEffects hangs one of these on FlxG.camera per season (0x180904a for winter,
// 0x1808e1a for autumn), so it grades the whole menu - which is why this runs as a screen
// pass rather than on any one sprite.

uniform float hue = 0.0;
uniform float saturation = 0.0;
uniform float brightness = 0.0;
uniform float contrast = 0.0;

const vec3 grayscaleValues = vec3(0.3098039215686275, 0.607843137254902, 0.0823529411764706);
const float e = 2.718281828459045;

vec3 applyHueRotate(vec3 aColor, float aHue) {
	float angle = radians(aHue);
	mat3 m1 = mat3(vec3(0.213, 0.213, 0.213), vec3(0.715, 0.715, 0.715), vec3(0.072, 0.072, 0.072));
	mat3 m2 = mat3(vec3(0.787, -0.213, -0.213), vec3(-0.715, 0.285, -0.715), vec3(-0.072, -0.072, 0.928));
	mat3 m3 = mat3(vec3(-0.213, 0.143, -0.787), vec3(-0.715, 0.140, 0.715), vec3(0.928, -0.283, 0.072));
	mat3 m = m1 + cos(angle) * m2 + sin(angle) * m3;
	return m * aColor;
}

vec3 applySaturation(vec3 aColor, float value) {
	if (value > 0.0) { value = value * 3.0; }
	value = (1.0 + (value / 100.0));
	vec3 grayscale = vec3(dot(aColor, grayscaleValues));
	return clamp(mix(grayscale, aColor, value), 0.0, 1.0);
}

vec3 applyContrast(vec3 aColor, float value) {
	value = (1.0 + (value / 100.0));
	if (value > 1.0) {
		value = (((0.00852259 * pow(e, 4.76454 * (value - 1.0))) * 1.01) - 0.0086078159) * 10.0;
		value += 1.0;
	}
	return clamp((aColor - 0.25) * value + 0.25, 0.0, 1.0);
}

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 src = texture(screen, SCREEN_UV);
	vec3 c = src.rgb;
	// The order is the mod's applyHSBCEffect: brightness, hue, contrast, saturation.
	c = c + (brightness / 255.0);
	c = applyHueRotate(c, hue);
	c = applyContrast(c, contrast);
	c = applySaturation(c, saturation);
	COLOR = vec4(c, src.a);
}
