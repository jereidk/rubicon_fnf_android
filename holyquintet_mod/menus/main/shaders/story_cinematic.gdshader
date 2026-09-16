shader_type canvas_item;

// Fuses HQMainMenu.hx beginStoryMode()'s three stacked FlxG.camera filters
// (Bloom, Transverse, adjustColor — see holyquintet_mod/source/shaders/
// Bloom.frag, Transverse.frag, adjustColor.frag for the originals) into one
// canvas_item shader, applied to a TextureRect displaying a SubViewport that
// the whole zoomed/rotated menu gets reparented into for the cinematic (see
// main_menu.gd's _apply_story_cinematic_shader()).
//
// Real Flixel stacks these as three independent post-process passes, each
// reading the previous one's full output. Godot's CanvasItem takes exactly
// one material, and building a true 3-pass chain here would mean two extra
// offscreen buffers just for a ~2s one-way transition. Bloom and Transverse
// both need to resample *neighboring* pixels of whatever comes into them,
// so they can't just be inlined per-pixel the way adjustColor (a pure
// per-pixel operation) can — this fuses the first two by having Transverse
// sample the same raw TEXTURE Bloom does (an approximation: real Transverse
// sees Bloom's already-blurred image) rather than truly chaining them, then
// applies adjustColor last, for real, against that combined result. Given
// the whole cinematic ends in a hard fade to black by the time any of this
// gets extreme (see fadeoutSprite in _begin_story_mode()), the difference
// from a true 3-pass chain is not something a player has time to notice.

uniform float bloom_amt : hint_range(-2.0, 2.0) = 0.0;
uniform float transverse_falloff : hint_range(0.1, 20.0) = 10.0;
uniform float saturation = 0.0;
uniform float contrast = 0.0;

const float BLOOM_BLUR_SIZE = 1.0 / 512.0;
const vec3 GRAYSCALE_VALUES = vec3(0.3098039215686275, 0.607843137254902, 0.0823529411764706);
const float EULER_E = 2.718281828459045;


vec4 bloom_blend(sampler2D tex, vec2 uv) {
	vec4 sum = vec4(0.0);

	sum += texture(tex, vec2(uv.x - 4.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.05;
	sum += texture(tex, vec2(uv.x - 3.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.09;
	sum += texture(tex, vec2(uv.x - 2.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.12;
	sum += texture(tex, vec2(uv.x - 1.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.15;
	sum += texture(tex, uv) * 0.16;
	sum += texture(tex, vec2(uv.x + 1.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.15;
	sum += texture(tex, vec2(uv.x + 2.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.12;
	sum += texture(tex, vec2(uv.x + 3.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.09;
	sum += texture(tex, vec2(uv.x + 4.0 * BLOOM_BLUR_SIZE, uv.y)) * 0.05;

	sum += texture(tex, vec2(uv.x, uv.y - 4.0 * BLOOM_BLUR_SIZE)) * 0.05;
	sum += texture(tex, vec2(uv.x, uv.y - 3.0 * BLOOM_BLUR_SIZE)) * 0.09;
	sum += texture(tex, vec2(uv.x, uv.y - 2.0 * BLOOM_BLUR_SIZE)) * 0.12;
	sum += texture(tex, vec2(uv.x, uv.y - 1.0 * BLOOM_BLUR_SIZE)) * 0.15;
	sum += texture(tex, uv) * 0.16;
	sum += texture(tex, vec2(uv.x, uv.y + 1.0 * BLOOM_BLUR_SIZE)) * 0.15;
	sum += texture(tex, vec2(uv.x, uv.y + 2.0 * BLOOM_BLUR_SIZE)) * 0.12;
	sum += texture(tex, vec2(uv.x, uv.y + 3.0 * BLOOM_BLUR_SIZE)) * 0.09;
	sum += texture(tex, vec2(uv.x, uv.y + 4.0 * BLOOM_BLUR_SIZE)) * 0.05;

	return sum * (-sin(bloom_amt)) + texture(tex, uv);
}


vec3 transverse_aberration(sampler2D tex, vec2 uv) {
	vec2 direction = normalize(uv - 0.5);
	float blur = 0.25;
	vec2 velocity = direction * blur * pow(length(uv - 0.5), transverse_falloff);

	const int SAMPLE_COUNT = 50;
	float inv_count = 1.0 / float(SAMPLE_COUNT);
	vec2 inc0 = velocity * 1.0 * inv_count;
	vec2 inc1 = velocity * 2.0 * inv_count;
	vec2 inc2 = velocity * 4.0 * inv_count;

	vec3 accumulator = vec3(0.0);
	vec2 off0 = vec2(0.0);
	vec2 off1 = vec2(0.0);
	vec2 off2 = vec2(0.0);

	for (int i = 0; i < SAMPLE_COUNT; i++) {
		accumulator.r += texture(tex, uv + off0).r;
		accumulator.g += texture(tex, uv + off1).g;
		accumulator.b += texture(tex, uv + off2).b;

		off0 -= inc0;
		off1 -= inc1;
		off2 -= inc2;
	}

	return accumulator * inv_count;
}


vec3 apply_saturation(vec3 c, float value) {
	if (value > 0.0) {
		value = value * 3.0;
	}
	value = 1.0 + (value / 100.0);
	vec3 gray = vec3(dot(c, GRAYSCALE_VALUES));
	return clamp(mix(gray, c, value), 0.0, 1.0);
}


vec3 apply_contrast(vec3 c, float value) {
	value = 1.0 + (value / 100.0);
	if (value > 1.0) {
		value = ((0.00852259 * pow(EULER_E, 4.76454 * (value - 1.0))) * 1.01 - 0.0086078159) * 10.0;
		value += 1.0;
	}
	return clamp((c - 0.25) * value + 0.25, 0.0, 1.0);
}


void fragment() {
	vec4 bloomed = bloom_blend(TEXTURE, UV);
	vec3 aberrated = transverse_aberration(TEXTURE, UV);
	// Bloom's own blend already mixed in alpha via `texture(tex, uv)`'s .a;
	// Transverse (real code too) only ever touches rgb and forces alpha=1.
	vec3 combined = mix(aberrated, bloomed.rgb, 0.5);

	vec3 graded = apply_contrast(combined, contrast);
	graded = apply_saturation(graded, saturation);

	COLOR = vec4(graded, bloomed.a);
}
