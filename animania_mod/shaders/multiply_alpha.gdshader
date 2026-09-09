// Multiply que respeta el alfa del fragmento, como el multiply de HaxeFlixel.
//
// El BLEND_MODE_MUL de Godot es (DST_COLOR, ZERO) a secas: ignora el alfa del
// fragmento, asi que una vineta con agujero transparente (rgb negro, a 0) pone
// en negro todo lo que se ve a traves del agujero en vez de dejarlo intacto.
// mainStageAmTake dibuja asi sus dos vinetas, y de ahi el "ovalo negro enorme"
// en mitad del escenario.
//
// La salida del shader re-codifica el alfa dentro del rgb, de modo que el blend
// multiply de fabrica componga igual que HaxeFlixel:
//
//   dst * COLOR.rgb   =   dst * mix(vec3(1), tex.rgb, tex.a)
//
// Los bordes se oscurecen como toca; el agujero transparente deja pasar el
// fondo sin tocar. `blend_mul` selecciona el mismo blend de fabrica, y el
// re-codificado de arriba lo vuelve fiel a Flixel.
shader_type canvas_item;
render_mode blend_mul;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// Flixel multiplica en sRGB tal cual, sin tocar el alfa del destino.
	// El alfa propio del nodo (modulate) entra en el peso: es como Flixel lleva
	// `alpha`, y es lo que usa el .hx para tener a vin2 apagada hasta su tween.
	float w = tex.a * COLOR.a;
	COLOR.rgb = mix(vec3(1.0), tex.rgb, w);
	COLOR.a = 1.0;
}
