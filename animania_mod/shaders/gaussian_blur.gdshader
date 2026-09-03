shader_type canvas_item;

// Gaussian blur shader — faithful port of Animania's blurX/blurY system.
// The binary uses two-pass Gaussian blur with separate X and Y components.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float blur_x : hint_range(0.0, 20.0) = 0.0; // Horizontal blur amount
uniform float blur_y : hint_range(0.0, 20.0) = 0.0; // Vertical blur amount

void fragment() {
	vec2 pixel_size = SCREEN_PIXEL_SIZE;
	vec4 color = vec4(0.0);
	
	// 9-tap Gaussian kernel for better quality
	// Weights: [1, 4, 6, 4, 1] / 16 (normalized)
	float weights[5] = { 1.0, 4.0, 6.0, 4.0, 1.0 };
	float total_weight = 16.0;
	
	// Horizontal pass
	if (blur_x > 0.0) {
		for (int i = -4; i <= 4; i++) {
			float weight = weights[abs(i)] / total_weight;
			vec2 offset = vec2(float(i) * pixel_size.x * blur_x, 0.0);
			color += texture(screen_texture, SCREEN_UV + offset) * weight;
		}
	} else {
		color = texture(screen_texture, SCREEN_UV);
	}
	
	// Vertical pass
	if (blur_y > 0.0) {
		vec4 v_color = vec4(0.0);
		for (int i = -4; i <= 4; i++) {
			float weight = weights[abs(i)] / total_weight;
			vec2 offset = vec2(0.0, float(i) * pixel_size.y * blur_y);
			v_color += texture(screen_texture, SCREEN_UV + offset) * weight;
		}
		color = mix(color, v_color, 0.5);
	}
	
	COLOR = color;
}
