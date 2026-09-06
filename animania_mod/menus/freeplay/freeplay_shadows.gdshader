// La sombra que los personajes proyectan sobre la cama.
//
// En el mod esto no es un sprite: `shadowsOnBed` es un `FlxLayerGroup` -un grupo que
// dibuja a sus miembros a un framebuffer y luego compone ese framebuffer de una vez-, y
// buildBg 1216-1226 lo deja asi:
//
//   1220  zIndex = 3
//   1221  colorTransform.set_color(0x1C1A2F)          // 0x34cf830
//   1222  colorTransform.alphaMultiplier = 0.8        // el doble en 0x59fa588
//   1223  blend = 11                                  // OVERLAY, del abstract BlendMode
//   1224  new GaussianBlurShader(2.0)                 // el doble en 0x59fa710
//
// Y `initCharacters` mete dentro a los dos personajes y al telefono (lineas 1405, 1412 y
// 1423) SIN sacarlos de la pantalla: cada uno se dibuja dos veces, una normal en su zIndex
// -4 la novia, 5 el jugador- y otra por aqui, en el 3, borrosa y tenida. Eso es la sombra.
//
// `set_color` de OpenFL pone los tres multiplicadores a 0 y los tres desplazamientos al
// color, asi que lo que queda del personaje es su SILUETA en plano; de la textura solo
// hace falta el alfa.
//
// El desenfoque son las siete muestras de siempre de OpenFL, con los pesos y los
// desplazamientos leidos del binario (0x5aac3d8 el fragmento, 0x5aac618 el vertice):
//
//   pesos  0.00443  0.05399  0.24197  0.39894  0.24197  0.05399  0.00443
//   despl.  -1.0     -0.75    -0.5      0.0      0.5      0.75     1.0
//
// Aqui van los dos ejes en una pasada -el producto exterior de la separable, 49 muestras-
// porque encadenar dos SubViewport por un desenfoque de radio 2 no compensa.
shader_type canvas_item;
render_mode blend_mix;

const float W[7] = float[7](0.00443, 0.05399, 0.24197, 0.39894, 0.24197, 0.05399, 0.00443);
const float O[7] = float[7](-1.0, -0.75, -0.5, 0.0, 0.5, 0.75, 1.0);

/// `uRadius` del shader del mod. GaussianBlurShader se construye con 2.0.
uniform vec2 radius = vec2(2.0, 2.0);
/// 0x1C1A2F = rgb(28, 26, 47).
uniform vec4 tint : source_color = vec4(0.10980392, 0.10196078, 0.18431373, 1.0);
/// `colorTransform.alphaMultiplier`.
uniform float layer_alpha : hint_range(0.0, 1.0) = 0.8;
/// Godot no trae mezcla OVERLAY en CanvasItemMaterial, asi que se hace a mano leyendo lo
/// que ya hay pintado debajo.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	vec2 px = radius / vec2(textureSize(TEXTURE, 0));
	float a = 0.0;
	for (int y = 0; y < 7; y++) {
		for (int x = 0; x < 7; x++) {
			a += texture(TEXTURE, UV + vec2(O[x], O[y]) * px).a * W[x] * W[y];
		}
	}
	a = clamp(a, 0.0, 1.0) * layer_alpha;

	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	vec3 src = tint.rgb;
	vec3 over = mix(2.0 * base * src, 1.0 - 2.0 * (1.0 - base) * (1.0 - src), step(vec3(0.5), base));
	COLOR = vec4(mix(base, over, a), 1.0);
}
