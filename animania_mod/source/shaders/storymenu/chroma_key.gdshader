shader_type canvas_item;

uniform vec3 bg_col : source_color = vec3(0.06, 0.05, 0.1);

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float maxrb = max(col.r, col.b);
	float dg = col.g;
	float k = clamp(dg - maxrb, 0.0, 1.0);
	col.rgb = vec3(max(col.r, max(col.g, col.b)));
	col.rgb *= bg_col.rgb * vec3(0.65);
	COLOR = vec4(mix(col.rgb, bg_col.rgb, k), col.a);
}
