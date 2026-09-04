shader_type canvas_item;
// bgMenu.frag from assets/shaders/as/bgMenu.frag, converted from Shadertoy GLSL
// to Godot CanvasItem shader. The animated grid rotates at -30° and pulses
// per-tile with a wave that decays outward from center, then blends with
// the background texture at 85%.
//
// iChannel0 in a flixel Shadertoy wrapper is the SPRITE'S OWN bitmap, so here it
// is TEXTURE. The port had it sampling menuTransparent.png through a uniform,
// and that file is a paletted transparency MASK, not a colour image: mixing 85%
// of its undefined rgb turned the menu's teal background into a purple wash.

void fragment() {
	vec2 resolution = vec2(textureSize(TEXTURE, 0));
	vec2 fragCoord = UV * resolution;

	float aspect_ratio = resolution.y / resolution.x;
	vec2 uv = fragCoord / resolution.x;
	uv -= vec2(0.5, 0.5 * aspect_ratio);

	float rot = radians(-30.0 - TIME);
	mat2 rotation_matrix = mat2(vec2(cos(rot), -sin(rot)), vec2(sin(rot), cos(rot)));
	uv = rotation_matrix * uv;

	vec2 scaled_uv = 20.0 * uv;
	vec2 tile = fract(scaled_uv);
	float tile_dist = min(min(tile.x, 1.0 - tile.x), min(tile.y, 1.0 - tile.y));
	float square_dist = length(floor(scaled_uv));

	float edge = sin(TIME - square_dist * 20.0);
	edge = mod(edge * edge, edge / edge);

	float value = mix(tile_dist, 1.0 - tile_dist, step(1.0, edge));
	edge = pow(abs(1.0 - edge), 2.2) * 0.5;

	value = smoothstep(edge - 0.05, edge, 0.95 * value);

	value += square_dist * 0.1;
	value *= 0.6;

	vec3 final_color = vec3(pow(value, 2.0), pow(value, 1.5), pow(value, 1.2));

	vec2 ogRes = fragCoord / resolution.xy;
	vec4 bg = texture(TEXTURE, ogRes);
	final_color = mix(final_color, bg.rgb, 0.85);

	COLOR = vec4(final_color, 1.0);
}
