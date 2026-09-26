shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

instance uniform vec4 color_multipliers = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform vec4 color_offsets = vec4(0.0);

instance uniform int blend_mode : hint_enum(
	"ADD",
	"ALPHA", // Not implemented, just per Flash n' stuff
	"DARKEN",
	"DIFFERENCE",
	"ERASE", // Not implemented, just per Flash n' stuff
	"HARD LIGHT",
	"INVERT",
	"LAYER", // Not implemented, just per Flash n' stuff
	"LIGHTEN",
	"MULTIPLY",
	"NORMAL",
	"OVERLAY",
	"SCREEN",
	"SHADER", // Not implemented, just per Flash n' stuff
	"SUBTRACT"
) = 10;

// GlowFilter: port de openfl.filters.GlowFilter. Solo se activa cuando
// gdanimate detecta un GF en la frame del layer y activa el canvas group
// mode TRANSPARENT en el RID del layer. En ese caso TEXTURE = la
// composicion del layer (no el sprite individual) y podemos samplear
// alrededor para hacer el blur radial del alpha.
//
// Defaults coinciden con "apagado": glow_enabled = 0 hace que el bloque
// no corra, y el shader se comporta como antes.
instance uniform int glow_enabled : hint_range(0, 1) = 0;
instance uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float glow_blur : hint_range(0.0, 64.0) = 6.0;
instance uniform float glow_strength : hint_range(0.0, 4.0) = 1.0;
instance uniform int glow_inner : hint_range(0, 1) = 0;
instance uniform int glow_knockout : hint_range(0, 1) = 0;

// most from https://godotshaders.com/snippet/blending-modes/
vec3 multiply(vec3 base, vec3 blend){
	return base * blend;
}

vec3 screen(vec3 base, vec3 blend){
	return 1.0 - (1.0 - base) * (1.0 - blend);
}

vec3 darken(vec3 base, vec3 blend){
	return min(base, blend);
}

vec3 lighten(vec3 base, vec3 blend){
	return max(base, blend);
}

vec3 difference(vec3 base, vec3 blend){
	return abs(base - blend);
}

vec3 overlay(vec3 base, vec3 blend){
	vec3 limit = step(0.5, base);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

vec3 add(vec3 base, vec3 blend) {
	return base + blend;
}

vec3 subtract(vec3 base, vec3 blend) {
	return base - blend;
}

vec3 invert(vec3 base) {
	return vec3(1.0) - base;
}

void fragment() {
	COLOR = color_offsets + (COLOR * color_multipliers);

	// GlowFilter: aplicar ANTES del blend mode, para que el blend vea la
	// imagen ya con el glow (que es el orden de Flash/OpenFL).
	if (glow_enabled == 1) {
		// Inline del sampling radial. TEXTURE, UV y TEXTURE_PIXEL_SIZE
		// son built-ins que SOLO existen dentro de vertex/fragment/light
		// (ver shader_types.cpp:301,302); no estan en funciones helper.
		// Por eso el bucle va inline aca y no en una funcion auxiliar.
		vec2 radius_uv = vec2(glow_blur) * TEXTURE_PIXEL_SIZE;
		float ring_sum = 0.0;
		for (int i = 0; i < 12; i++) {
			float angle = float(i) * 0.5235988; // 2*PI/12
			vec2 offset = vec2(cos(angle), sin(angle)) * radius_uv;
			ring_sum += texture(TEXTURE, UV + offset).a;
		}
		float ring = ring_sum / 12.0;

		// Outer glow (default): aplicar donde el sprite NO cubre.
		// Inner glow (glow_inner = 1): aplicar solo dentro del sprite.
		float mask = (glow_inner == 1) ? COLOR.a : (1.0 - COLOR.a);
		float glow_a = ring * mask * glow_strength * glow_color.a;

		// Compuesto aditivo (lo que hace ADD del BlendMode en Flash).
		COLOR.rgb += glow_color.rgb * glow_a;

		// Knockout: ocultar el sprite original (solo queda el glow).
		if (glow_knockout == 1) {
			COLOR.a = 0.0;
		}
	}

	if (blend_mode > -1 && blend_mode != 10) {
		vec4 screen_c = texture(SCREEN_TEXTURE, SCREEN_UV);

		if (blend_mode == 2) {
			COLOR.rgb = darken(COLOR.rgb, screen_c.rgb);
		} else if (blend_mode == 9) {
			COLOR.rgb = multiply(COLOR.rgb, screen_c.rgb);
		} else if (blend_mode == 8) {
			COLOR.rgb = lighten(COLOR.rgb, screen_c.rgb);
		} else if (blend_mode == 12) {
			COLOR.rgb = screen(COLOR.rgb, screen_c.rgb);
		} else if (blend_mode == 11) {
			COLOR.rgb = overlay(screen_c.rgb, COLOR.rgb);
		} else if (blend_mode == 5) {
			COLOR.rgb = overlay(COLOR.rgb, screen_c.rgb);
		} else if (blend_mode == 0) {
			// TODO: Maybe apply this to the other
			// blend modes too, it might need different
			// adjustments per blend mode though
			COLOR.rgb *= COLOR.a;
			COLOR.a = 1.0;
			COLOR.rgb = add(COLOR.rgb, screen_c.rgb);
		} else if (blend_mode == 14) {
			COLOR.rgb = subtract(screen_c.rgb, COLOR.rgb);
		} else if (blend_mode == 3) {
			COLOR.rgb = difference(COLOR.rgb, screen_c.rgb);
		} else if (blend_mode == 6) {
			COLOR.rgb = invert(screen_c.rgb);
		} else if (blend_mode == 1) {
			// ALPHA (BlendShader de maru, Blend.hx):
			//     result.a = b.a;   // b = FG (a = BG)
			// result.rgb queda en bg.rgb. En el pipeline de Godot, para
			// obtener final.rgb = bg.rgb hace falta COLOR.rgb = bg.rgb.
			// El alpha final = mix(bg.a, COLOR.a, COLOR.a), que con bg.a=1
			// da 1-fg.a+fg.a^2 (no exactamente fg.a para fg.a<1). Cerca
			// pero no 1:1. Documentado en FIDELITY.md.
			COLOR.rgb = screen_c.rgb;
			// Sin cambios en COLOR.a (que es el alpha del FG).
		} else if (blend_mode == 4) {
			// ERASE (BlendShader de maru, Blend.hx):
			//     result.a = a.a * (1.0 - b.a);   // a = BG, b = FG
			//     result.rgb = a.rgb;
			// Aproximacion: el FG se dibuja con el rgb del BG y alpha
			// invertido. final.a = mix(bg.a, 1-fg.a, 1-fg.a), que con
			// bg.a=1 da 1 - (1-fg.a) + (1-fg.a)^2 = 1 - fg.a + fg.a^2,
			// cerca de bg.a*(1-fg.a) para fg.a chico. Documentado.
			COLOR.rgb = screen_c.rgb;
			COLOR.a = 1.0 - COLOR.a;
		}
	}
}
