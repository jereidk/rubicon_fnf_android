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

/// `uRadius`. El mod construye `GaussianBlurShader(2.0)` -el double de 0x59fa710-, pero ese
/// 2.0 NO es un radio en pixeles: puesto tal cual deja una silueta con dos pixeles de orla y
/// la sombra del mod es mucho mas blanda. Lo que ese `amount` escala dentro del shader del
/// mod no esta leido, asi que el numero se BARRE contra la captura, midiendo el error medio
/// de la pantalla (sin el tubo) y el de la zona de personajes y cama:
///
///     sin sombra   26.34 / 30.30      radio 14   25.07 / 27.78
///     radio  2     24.82 / 27.29      radio 20   24.47 / 26.59   <- minimo
///     radio  8     25.25 / 28.13      radio 26   25.33 / 28.26
///
/// El barrido hay que hacerlo con las seis tomas en la MISMA fase de la nieve del televisor
/// o no mide esto. El primer intento salio con las de referencia desfasadas un fotograma
/// -cada `await` de mas en el arnes adelanta la animacion- y daba la conclusion contraria,
/// que la capa empeoraba el parecido. Con las seis a la misma fase (tubo 120.2 en todas) la
/// capa suma con cualquier radio, y 20 gana por los dos lados.
///
/// Va en pixeles de la textura de origen, que es el SubViewport a 1920x1080; en las 1280x720
/// del mod son 13.3.
uniform vec2 radius = vec2(20.0, 20.0);
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
	// Se saca el resultado con el alfa de la silueta y se deja que `blend_mix` haga la
	// interpolacion contra lo que ya hay: `over*a + fondo*(1-a)`, que es la mezcla que
	// toca. Sacarlo con alfa 1 -o sea reescribiendo `base` en toda la pantalla- tambien
	// "funciona" en teoria, pero pasa TODO lo pintado debajo por un viaje de ida y vuelta
	// a la textura de pantalla, y eso desplaza la gamma: el primer intento subia el brillo
	// de la cama entera en vez de bajarlo.
	COLOR = vec4(over, a);
}
