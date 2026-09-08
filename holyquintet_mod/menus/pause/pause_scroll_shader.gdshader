shader_type canvas_item;
uniform float u_tile : hint_range(0.1, 64.0) = 1.0;
uniform float v_tile : hint_range(0.1, 64.0) = 1.0;
uniform float u_scroll : hint_range(-64.0, 64.0) = 0.0;
uniform float v_scroll : hint_range(-64.0, 64.0) = 0.0;
void fragment() {
	vec2 uv = fract(UV * vec2(u_tile, v_tile) + vec2(u_scroll, v_scroll));
	COLOR = texture(TEXTURE, uv);
}
