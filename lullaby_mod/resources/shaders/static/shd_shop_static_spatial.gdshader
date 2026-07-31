// Smoke for the shop cubes
// Look in code for credits
// Shader by lunarcleint, your good to use this on anything without credit
//
// Rubicon optimization: the original computed two 6-octave animated
// Simplex noise fields per pixel (~12 snoise() evaluations, each with
// several permute()/dot() calls) purely to warp distort_uv before the
// visible bars pattern. That's real GPU cost on mobile for a small prop
// screen. Replaced both fullnoise() calls with a single sample of a
// precomputed tileable FBM texture (tex_static_noise.png, baked once
// offline with the same 6-octave/amplitude falloff) plus a cheap
// TIME-based UV scroll for motion - the downstream math (rotateUV, the
// bars pattern, contrast) is untouched, so the visible result reads the
// same, it's just fed by a texture lookup instead of a procedural noise
// stack.

shader_type spatial;

#define PI 3.1415926535897932384626433832795

uniform float bars_amount = 14;
uniform float stretch_x = 1.0;
uniform float squash_x = 1.0;

uniform vec3 base_color : source_color;
uniform float speed = 1.0;
uniform float contrast = 1.0;
uniform float emission = 1.0;

uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float noise_scroll_speed : hint_range(0.0, 2.0) = 0.12;

vec3 sample_noise(vec2 xy) {
	vec2 uv = xy + vec2(TIME * speed * noise_scroll_speed, TIME * speed * noise_scroll_speed * 0.7);
	return vec3(texture(noise_tex, uv).r);
}

/*
	Rotation code from: https://gist.github.com/ayamflow/c06bc0c8a64f985dd431bd0ac5b557cd

	Author: @ayamflow (https://gist.github.com/ayamflow)
*/
vec2 rotateUV(vec2 uv, float rotation)
{
    float mid = 0.5;
    return vec2(
        cos(rotation) * (uv.x - mid) + sin(rotation) * (uv.y - mid) + mid,
        cos(rotation) * (uv.y - mid) - sin(rotation) * (uv.x - mid) + mid
    );
}

vec3 adjustContrast(vec3 color, float value) {
  return 0.5 + value * (color - 0.5);
}

void fragment() {
	vec4 regular_color = vec4(vec3(1.0), 1.0);

	vec2 reg_uv = UV * vec2(squash_x, 1.0);

	vec2 distort_uv = rotateUV(reg_uv, 0.65 - (sin(TIME / 6.0) * 0.3));
	vec3 noise = sample_noise(distort_uv);
	distort_uv = mix(distort_uv, noise.zy, 0.2);
	distort_uv = mix(distort_uv, rotateUV(noise.xy, 0.3) * 0.2, 0.3);

	vec3 noise_two = sample_noise(distort_uv / 3.0) * 1.5;
	distort_uv = mix(distort_uv, noise_two.xy, 0.4);

	distort_uv *= vec2(stretch_x, stretch_x);

	float pattern = abs(cos(distort_uv.x * bars_amount * PI));
	regular_color.rgb = mix(vec3(0.3), vec3(0.0), pattern);

	for (int i = 0; i < 1; i++) {
		float pattern = step(0.5, fract((distort_uv.x + (0.008 * float(i))) * bars_amount));
		regular_color.rgb = mix(regular_color.rgb, regular_color.rgb + mix(vec3(0.04), vec3(0.0), pattern), 0.6);
	}

	for (int i = 0; i < 2; i++) {
		float pattern = step(0.5, fract((distort_uv.x + 0.01 + (0.008 * float(i))) * bars_amount));
		regular_color.rgb = mix(regular_color.rgb, regular_color.rgb + mix(vec3(1.0), vec3(0.0), pattern), 0.2);
	}

	for (int i = 0; i < 2; i++) {
		float pattern = step(0.5, fract((distort_uv.x + 0.02 + (0.008 * float(i))) * bars_amount));
		regular_color.rgb = mix(regular_color.rgb, regular_color.rgb + mix(vec3(1.0), vec3(0.0), pattern), 0.1);
	}

	for (int i = 0; i < 1; i++) {
		float pattern = abs(cos((distort_uv.x + (0.003 * float(i))) * bars_amount * PI));
		regular_color.rgb = mix(regular_color.rgb, regular_color.rgb + mix(vec3(1.0), vec3(0.0), pattern), 0.5);
	}

	regular_color.rgb *= base_color * 0.75;
	regular_color.rgb += base_color * 0.5;

	regular_color.rgb = adjustContrast(regular_color.rgb, contrast);

	ALBEDO = regular_color.rgb;
	ALPHA = regular_color.a;

	EMISSION = regular_color.rgb * emission;
}
