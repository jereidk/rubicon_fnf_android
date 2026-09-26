shader_type canvas_item;

// F13b-ii: shader de post-proceso de filtros Adobe.
//
// A diferencia de atlas_shader.gdshader (que aplica color matrix + glow
// inline sobre el FG antes del blend), este shader se aplica a una
// TEXTURA ya renderizada (via AdobeRenderBaker) y devuelve la textura
// filtrada. Es el port conceptual de FilterRenderer.applyFilter
// (maru src/animate/internal/FilterRenderer.hx:400-500).
//
// Todos los uniforms son "instance" para que un mismo ShaderMaterial
// pueda servir a multiples capas con filtros distintos sin clonar.
//
// Orden de aplicacion (mismo que maru: cada filtro se aplica al resultado
// del anterior, en el orden del Array de filters):
//   1. Blur    (BLF)
//   2. DropShadow (DSF) - dibuja el shadow detras del contenido
//   3. Glow    (GF)     - dibuja el glow alrededor (outer) o dentro (inner)
//   4. Bevel   (BF)     - highlight en un lado + shadow en el otro
//   5. AdjustColor (ACF) - matriz de color
//
// Este shader cubre Blur, Glow y AdjustColor en un solo pase. DropShadow
// y Bevel necesitan el contenido original + un offset, asi que se hacen
// con un segundo pase (filter_shadow_shader.gdshader, F13b-ii.2).

uniform int filters_count = 0;

// Blur (en UV-space, no pixels). El caller pasa blur_uv = blur_px / size.
uniform vec2 blur_uv = vec2(0.0);
uniform float blur_x = 0.0;  // solo para el glow ring
uniform float blur_y = 0.0;  // solo para el glow ring

// Glow
uniform int glow_enabled = 0;
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_strength = 1.0;
uniform int glow_inner = 0;
uniform int glow_knockout = 0;

// AdjustColor (color matrix 4x5 aplanada a diag + offset).
// El port no aplica cross-talk entre canales (F13a, documentado).
uniform vec4 adjust_mult = vec4(1.0);
uniform vec4 adjust_offset = vec4(0.0);
uniform int adjust_enabled = 0;

// DropShadow
uniform int ds_enabled = 0;
uniform vec4 ds_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2 ds_offset_uv = vec2(0.0);
uniform float ds_blur_uv = 0.0;  // radio del blur aplicado al shadow
uniform float ds_strength = 1.0;

// Bevel (2 sombras opuestas: highlight + shadow).
uniform int bevel_enabled = 0;
uniform vec4 bevel_highlight : source_color = vec4(1.0);
uniform vec4 bevel_shadow : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2 bevel_offset_uv = vec2(0.0);
uniform float bevel_blur_uv = 0.0;
uniform float bevel_strength = 1.0;

// TAU ya existe como built-in en el shader language de Godot 4
// (junto con PI y E). No se puede redeclarar.

// Box blur simple con N samples en cruz (rapido y suficiente para los
// radios que usan los mods). Para radios grandes se podria cambiar a un
// box blur de 2 pasadas, pero por ahora alcanza.
vec4 sample_blur(sampler2D tex, vec2 uv, vec2 radius_uv) {
    if (radius_uv.x <= 0.0 && radius_uv.y <= 0.0) {
        return texture(tex, uv);
    }
    vec4 sum = vec4(0.0);
    float count = 0.0;
    // Muestreo en cruz + diagonales: 9 samples.
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            vec2 off = vec2(float(i), float(j)) * radius_uv;
            sum += texture(tex, uv + off);
            count += 1.0;
        }
    }
    return sum / count;
}

// Suma radial del alpha con blur variable (para DS y Bevel).
// Devuelve el promedio del alpha en un anillo de radio `r` (en UV).
float sample_alpha_ring(sampler2D tex, vec2 uv, float r) {
    if (r <= 0.0) {
        return texture(tex, uv).a;
    }
    float sum = 0.0;
    for (int i = 0; i < 12; i++) {
        float angle = float(i) * TAU / 12.0;
        vec2 off = vec2(cos(angle), sin(angle)) * r;
        sum += texture(tex, uv + off).a;
    }
    return sum / 12.0;
}

// Suma radial del alpha para el glow.
float sample_glow_ring(sampler2D tex, vec2 uv, vec2 radius_uv) {
    float ring = 0.0;
    for (int i = 0; i < 12; i++) {
        float angle = float(i) * TAU / 12.0;
        vec2 off = vec2(cos(angle), sin(angle)) * radius_uv;
        ring += texture(tex, uv + off).a;
    }
    return ring / 12.0;
}

void fragment() {
    vec2 uv = UV;
    vec4 col = texture(TEXTURE, uv);

    // 1. Blur primero: el resto de filtros operan sobre el resultado blureado.
    if (blur_uv.x > 0.0 || blur_uv.y > 0.0) {
        col = sample_blur(TEXTURE, uv, blur_uv);
    }

    // 2. Glow
    if (glow_enabled == 1) {
        float ring = sample_glow_ring(TEXTURE, uv, vec2(blur_x, blur_y) * TEXTURE_PIXEL_SIZE);
        float mask = (glow_inner == 1) ? col.a : (1.0 - col.a);
        float glow_a = ring * mask * glow_strength * glow_color.a;
        col.rgb += glow_color.rgb * glow_a;
        if (glow_knockout == 1) {
            col.a = 0.0;
        }
    }

    // 3. AdjustColor (matriz de color).
    if (adjust_enabled == 1) {
        col = col * adjust_mult + adjust_offset;
    }

    // 4. Bevel (antes de DS: el bevel forma parte del "contenido").
    if (bevel_enabled == 1) {
        float ring_h = sample_alpha_ring(TEXTURE, uv + bevel_offset_uv, bevel_blur_uv);
        float ring_s = sample_alpha_ring(TEXTURE, uv - bevel_offset_uv, bevel_blur_uv);
        // Highlight: aplicado donde el sprite NO cubre (afuera).
        float h_amount = ring_h * (1.0 - col.a) * bevel_strength * bevel_highlight.a;
        col.rgb = mix(col.rgb, bevel_highlight.rgb, h_amount);
        // Shadow: aplicado donde el sprite NO cubre.
        float s_amount = ring_s * (1.0 - col.a) * bevel_strength * bevel_shadow.a;
        col.rgb = mix(col.rgb, bevel_shadow.rgb, s_amount);
        col.a = max(col.a, h_amount + s_amount);
    }

    // 5. DropShadow (compuesto detras del contenido).
    if (ds_enabled == 1) {
        float ds_alpha = sample_alpha_ring(TEXTURE, uv - ds_offset_uv, ds_blur_uv);
        ds_alpha *= ds_color.a * ds_strength;
        // Composicion estandar: fg sobre bg.
        // fg = col (contenido), bg = shadow color con alpha ds_alpha.
        vec3 fg_rgb = col.rgb * col.a;
        vec3 bg_rgb = ds_color.rgb * ds_alpha;
        float out_a = col.a + ds_alpha * (1.0 - col.a);
        if (out_a > 0.0) {
            col.rgb = (fg_rgb + bg_rgb * (1.0 - col.a)) / out_a;
        }
        col.a = out_a;
    }

    COLOR = col;
}
