#pragma header

// by https://github.com/HEIHUAa/

const vec2 pos = vec2(1.0 / 1080.0, 0.0);
const vec2 pos_2 = pos * 2.0;
const vec2 pos_3 = pos * 3.0;
const vec2 pos_4 = pos * 4.0;
const vec2 pos_6 = pos * 6.0;
const vec2 pos_9 = pos * 9.0;
const vec2 pos_12 = pos * 12.0;
const vec2 pos_15 = pos * 15.0;
const vec2 pos_18 = pos * 18.0;
const vec2 pos_21 = pos * 21.0;

const mat3 yiq2rgb_mat = mat3(
	1.0, 0.956, 0.6210,
	1.0, -0.2720, -0.6474,
	1.0, -1.1060, 1.7046);

const mat3 yiq_mat = mat3(
	0.2989, 0.5870, 0.1140,
	0.5959, -0.2744, -0.3216,
	0.2115, -0.5229, 0.3114
);

vec3 applyCrosstalk(vec3 yiq) {
	float y_to_iq = yiq.x * 0.08;

	float i_to_y = yiq.y * 0.05;
	float q_to_y = yiq.z * 0.05;

	float i_to_q = yiq.y * 0.03;
	float q_to_i = yiq.z * 0.03;
	
	return vec3(
		yiq.x + i_to_y + q_to_y,
		yiq.y + y_to_iq + q_to_i,
		yiq.z + y_to_iq + i_to_q
	);
}

void main(void) {
	vec4 y = texture2D(bitmap, openfl_TextureCoordv - pos_3) * 0.015625;
	y += texture2D(bitmap, openfl_TextureCoordv - pos_2) * 0.09375;
	y += texture2D(bitmap, openfl_TextureCoordv - pos) * 0.234375;
	y += texture2D(bitmap, openfl_TextureCoordv) * 0.3125;
	y += texture2D(bitmap, openfl_TextureCoordv + pos) * 0.234375;
	y += texture2D(bitmap, openfl_TextureCoordv + pos_2) * 0.09375;
	y += texture2D(bitmap, openfl_TextureCoordv + pos_3) * 0.015625;

	y.rgb *= yiq_mat;

	vec4 uv = texture2D(bitmap, openfl_TextureCoordv - pos_21) * 0.019;
		uv += texture2D(bitmap, openfl_TextureCoordv - pos_18) * 0.038;
		uv += texture2D(bitmap, openfl_TextureCoordv - pos_15) * 0.075;
		uv += texture2D(bitmap, openfl_TextureCoordv - pos_12) * 0.122;
		uv += texture2D(bitmap, openfl_TextureCoordv - pos_9) * 0.165;
		uv += texture2D(bitmap, openfl_TextureCoordv - pos_6) * 0.187;
		uv += texture2D(bitmap, openfl_TextureCoordv - pos_3) * 0.187;
		uv += texture2D(bitmap, openfl_TextureCoordv) * 0.165;
		uv += texture2D(bitmap, openfl_TextureCoordv + pos_3) * 0.122;
		uv += texture2D(bitmap, openfl_TextureCoordv + pos_6) * 0.075;
		uv += texture2D(bitmap, openfl_TextureCoordv + pos_9) * 0.038;
		uv += texture2D(bitmap, openfl_TextureCoordv + pos_12) * 0.019;

	uv.rgb *= yiq_mat;

	uv.y = min(uv.y, y.x * 2.0);
	uv.z = min(uv.z * 0.81, y.x * 1.4);

	vec3 rgb = vec3(y.x, uv.yz);

	gl_FragColor = vec4(pow(rgb * yiq2rgb_mat, vec3(2.5 / 2.2)), (y.a + uv.a) * 0.5);
}