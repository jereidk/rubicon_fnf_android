#pragma header

// by https://github.com/HEIHUAa/

const mat3 yiq2rgb_mat = mat3(
	1.0, 0.956, 0.6210,
	1.0, -0.2720, -0.6474,
	1.0, -1.1060, 1.7046);

const mat3 yiq_mat = mat3(
	0.2989, 0.5870, 0.1140,
	0.5959, -0.2744, -0.3216,
	0.2115, -0.5229, 0.3114
);

const vec2 imgSize = vec2(1440.0, 360.0);

void main(void) {
	vec4 s = texture2D(bitmap, openfl_TextureCoordv);
	vec3 yuv = s.rgb * yiq_mat;
	float accumY = 0.0;

	int j = 0;
	for (int i = 0; i <= 2; ++i) {
		vec2 offset = vec2(i, 0) / imgSize;
		float s = 1.0 - dot(texture2D(bitmap, openfl_TextureCoordv + offset).rgb, yiq_mat[0]);
		accumY += s * (20.0 - min(float(i * i + j * j), 1.0) * 40.0);
	}
	for (int i = -2; i <= 0; ++i) {
		vec2 offset = vec2(i, 0) / imgSize * 0.5;
		float s = 1.0 - dot(texture2D(bitmap, openfl_TextureCoordv + offset).rgb, yiq_mat[0]);
		accumY -= s * (20.0 - min(float(i * i + j * j), 1.0) * 40.0);
	}

	yuv.x += accumY * 0.025;

	yuv.y = min(yuv.y, yuv.x * 2.0);
	yuv.z = min(yuv.z * 0.81, yuv.x * 1.4);

	gl_FragColor = vec4(yuv * yiq2rgb_mat, s.a);
}