shader_type canvas_item;

// Approximates BlurFilter.hx's effect (background blur behind the message
// window) without transliterating its 4-pass AGAL downsample/blur/upsample
// pipeline, which is tied to OpenFL's camera.addShader() stack and doesn't
// map onto Godot's renderer. This is a single-pass 2D gaussian-weighted
// blur reading SCREEN_TEXTURE; visually equivalent softening, same trigger
// (window open) and same 0.5s ramp, different implementation underneath.
uniform float blur_amount : hint_range(0.0, 8.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * blur_amount;
	vec4 sum = vec4(0.0);
	float total = 0.0;
	float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
	sum += texture(screen_tex, SCREEN_UV) * weights[0];
	total += weights[0];
	for (int i = 1; i < 5; i++) {
		float w = weights[i];
		float o = float(i);
		sum += texture(screen_tex, SCREEN_UV + vec2(o, 0.0) * px) * w;
		sum += texture(screen_tex, SCREEN_UV - vec2(o, 0.0) * px) * w;
		sum += texture(screen_tex, SCREEN_UV + vec2(0.0, o) * px) * w;
		sum += texture(screen_tex, SCREEN_UV - vec2(0.0, o) * px) * w;
		total += w * 4.0;
	}
	COLOR = sum / total;
}
