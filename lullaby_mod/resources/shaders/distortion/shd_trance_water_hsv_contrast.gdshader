// Water distortion + HSV + contrast, fused into a single canvas_item pass.
// Original math ported unmodified from (all by lunarcleint, credit-free to use):
//   shd_water_distortion.gdshader, shd_hsv.gdshader, shd_contrast.gdshader
//
// Rubicon optimization: safety_lullaby's trance_shaders.gd drove these three
// as separate full-screen CanvasLayer/ColorRect passes stacked in draw order
// (water -> hsv -> contrast), each reading the prior pass's fully composited
// output via its own hint_screen_texture backbuffer copy - 3 screen-texture
// round-trips every frame for the whole song. Since nothing else is drawn
// between them, chaining the same three operations inline in one fragment()
// produces the same result with one pass instead of three. (The radial blur
// pass stays separate - it's a genuinely spatial multi-tap operation that
// doesn't commute with HSV/contrast the way a straight-line color chain
// does, so fusing it would cost more ALU than the backbuffer copy it'd save.)

shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform sampler2D NOISE_TEXTURE : source_color, repeat_enable, filter_linear;

uniform float WAVE_STRENGTH : hint_range(0.0, 2.0);
uniform float GHOST_STRENGTH : hint_range(0.0, 1.0);

uniform float HUE : hint_range(0.0, 360.0);
uniform float SATURATION : hint_range(0.0, 3.0);
uniform float VALUE : hint_range(0.0, 1.0) = 1.0;

uniform float CONTRAST : hint_range(0.0, 2.0);

// Functions from: https://gamedev.stackexchange.com/questions/59797/glsl-shader-change-hue-saturation-brightness
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Function from: https://tsev.dev/posts/2020-06-19-colour-correction-with-webgl/
vec3 adjustContrast(vec3 color, float value) {
  return 0.5 + value * (color - 0.5);
}

void fragment() {
	vec4 WAVY_COLOR = vec4(1.0);

	if (WAVE_STRENGTH <= 0.0) {
		WAVY_COLOR = texture(SCREEN_TEXTURE, SCREEN_UV);
	} else {
		vec2 NOISE_SAMPLE_UV = SCREEN_UV * vec2(3.0, 1.0);

		NOISE_SAMPLE_UV.x -= TIME * 0.15;

		// Flip texture every other repeat for looping
		float NOISE_INDEX = floor(NOISE_SAMPLE_UV.x);
		bool INDEX_IS_ODD = mod(NOISE_INDEX, 2.0) != 0.0;

		vec2 NOISE_LOCAL_UV = fract(NOISE_SAMPLE_UV);

		if (INDEX_IS_ODD) {
			NOISE_LOCAL_UV.x = 1.0 - NOISE_LOCAL_UV.x;
		}

		vec4 NOISE = texture(NOISE_TEXTURE, NOISE_LOCAL_UV);

		vec2 OFFSET = NOISE.xy * WAVE_STRENGTH * 0.0125;

		WAVY_COLOR = texture(SCREEN_TEXTURE, (SCREEN_UV + OFFSET));
		WAVY_COLOR += texture(SCREEN_TEXTURE, SCREEN_UV + (OFFSET * (1.0 - GHOST_STRENGTH)));
		// Average out the two to not scrotch my eyes
		WAVY_COLOR *= 0.5;
	}

	vec3 HSV = rgb2hsv(WAVY_COLOR.rgb);
	HSV.x *= (360.0 - HUE) / 360.0;
	HSV.y *= SATURATION;
	HSV.z *= VALUE;
	WAVY_COLOR.rgb = hsv2rgb(HSV);

	WAVY_COLOR.rgb = adjustContrast(WAVY_COLOR.rgb, CONTRAST);

	COLOR = WAVY_COLOR;
}
