shader_type canvas_item;
// funkin.graphics.shaders.BoilShader, ported by behaviour rather than by source.
//
// The GLSL itself is not shipped - assets/shaders/ has no boil frag - so it is compiled
// into the binary as a Haxe string. What the binary DOES give is the class's shape:
// set_amount(double), loadBoilTexture(String) with a DEFAULT_BOIL_TEXTURE static, and the
// pair bumpTimer()/updateBoil() beside a BOIL_INTERVAL and a boilTimer on the title state.
//
// That pair is the whole technique and the reason the effect reads the way it does: the
// displacement is NOT continuous. It is re-rolled on an interval, so the line jitters in
// discrete steps like hand-drawn animation shot on twos, instead of swimming smoothly.
// A continuous version of this looks wrong even with the right texture.
//
// The texture is the mod's own boil_texture.png.

uniform sampler2D boil_texture : filter_linear, repeat_enable;
// set_amount(). How far the UVs are pushed, in UV space.
uniform float amount : hint_range(0.0, 0.05) = 0.006;
// Stepped by the level's boilTimer rather than read from TIME, so the step is controlled
// from outside and matches BOIL_INTERVAL.
uniform vec2 boil_offset = vec2(0.0);

void fragment() {
	vec2 displacement = texture(boil_texture, UV + boil_offset).rg;
	// The texture is a displacement map centred on grey.
	vec2 push = (displacement - vec2(0.5)) * 2.0 * amount;
	COLOR = texture(TEXTURE, UV + push);
}
