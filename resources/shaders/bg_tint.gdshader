shader_type canvas_item;

// Color base del brush. Se setea con set_shader_parameter("tint", Color).
// Default: el amarillo del menuBGMagenta original.
uniform vec4 tint : source_color = vec4(0.96, 0.82, 0.29, 1.0);

// Fuerza del tinte. 0.0 = brush original sin cambios, 1.0 = duotone puro.
// 0.85 deja un pelin del color original para que no se vea artificial.
uniform float strength : hint_range(0.0, 1.0) = 0.85;

void fragment() {
    vec4 px = texture(TEXTURE, UV);
    // Luminancia percibida (Rec. 709). Es lo que preserva los trazos
    // oscuros del brush: donde la imagen es oscura, el tinte tambien.
    float lum = dot(px.rgb, vec3(0.2126, 0.7152, 0.0722));
    // Duotone: sombra = 15% del tinte (casi negro), luz = tinte pleno.
    vec3 dark = tint.rgb * 0.15;
    vec3 light = tint.rgb;
    vec3 tinted = mix(dark, light, lum);
    COLOR.rgb = mix(px.rgb, tinted, strength);
    COLOR.a = px.a;
}
