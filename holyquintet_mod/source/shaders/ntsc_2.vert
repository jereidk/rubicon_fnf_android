#pragma header

// by https://github.com/HEIHUAa/

void main(void) {
	openfl_TextureCoordv = openfl_TextureCoord;

	vec4 position = openfl_Position;
	position.x /= (1920.0 / openfl_TextureSize.x) / 2.0;

	gl_Position = openfl_Matrix * position;
}