shader_type canvas_item;
// phoneCallStreet.hx line 58: `if (Preferences.shaders) FlxG.camera.setFilters([new
// ShaderFilter(bloomShader)])`. A filter on the GAME camera, so it lands over the stage
// and under the letterbox and the HUD - which is why a capture of the mod has the wall
// washed out and the black bars still pure black.
//
// Translated line for line from the mod's own assets/shaders/bloom.frag, which it ships as
// plain text. BloomShader.hx sets blurSize [50, 50] and quality 2 and never changes them
// for this stage.
//
// What it does, since the constants hide it: it takes sixteen samples in a square around
// the pixel, raises each to the TWENTY-FIFTH power - so only what is already almost white
// survives - averages the three channels into one number, and adds that back as grey. The
// wall's red is already at 255, so what the bloom adds shows up almost entirely in green
// and blue, which is the +39 a capture of the mod measures against this port.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// The mod's [50, 50], in Funkin pixels, at this project's 1.5.
uniform vec2 blur_size = vec2(75.0, 75.0);

// quality 2, as a constant rather than a uniform: the loop step is 1/quality, and a loop a
// GLES driver cannot unroll is a loop it can refuse. Nothing in this stage calls
// setQuality, so there is nothing to lose by fixing it.
const int TAPS = 4;
const float QUALITY = 2.0;

const vec3 MULT_COLOR_1 = vec3(25.0);
const vec4 MULT_COLOR_2 = vec4(250.0, 250.0, 250.0, 50.0) / vec4(350.0);


void fragment() {
	vec2 step_uv = blur_size * SCREEN_PIXEL_SIZE;
	vec4 sum = texture(screen_tex, SCREEN_UV);

	for (int ix = 0; ix < TAPS; ix++) {
		float x = -1.0 + float(ix) / QUALITY;
		for (int iy = 0; iy < TAPS; iy++) {
			float y = -1.0 + float(iy) / QUALITY;
			vec4 tap = texture(screen_tex, SCREEN_UV + vec2(x, y) * step_uv);
			tap.rgb = pow(tap.rgb, MULT_COLOR_1);
			sum += (tap.r + tap.g + tap.b) / 3.0 / QUALITY / QUALITY * MULT_COLOR_2
				* clamp(1.0 - pow(x * x + y * y, 1.0 / 5.0), 0.0, 1.0) * 0.5;
		}
	}

	COLOR = vec4(sum.rgb, 1.0);
}
